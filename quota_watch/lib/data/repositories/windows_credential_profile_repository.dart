import 'dart:convert';
import 'dart:io';

import '../../app/desktop/window_native_io.dart';
import '../models/credential_profile.dart';
import '../models/quota_models.dart';
import '../providers/codex/codex_app_server_client.dart';
import 'credential_profile_repository.dart';

abstract interface class CredentialSecretStore {
  Future<String?> read(Provider provider);
  Future<void> write(Provider provider, String secret);
  Future<void> delete(Provider provider);
}

abstract interface class CredentialMetadataStore {
  Future<String?> read();
  Future<void> write(String contents);
}

class WindowsCredentialProfileRepository implements CredentialProfileStore {
  WindowsCredentialProfileRepository({
    required CredentialSecretStore secretStore,
    required CredentialMetadataStore metadataStore,
    Map<String, String>? environment,
    bool Function()? codexConfigured,
  })  : _secretStore = secretStore,
        _metadataStore = metadataStore,
        _environment = environment ?? Platform.environment,
        _codexConfigured = codexConfigured ?? _detectCodex;

  factory WindowsCredentialProfileRepository.production() {
    return WindowsCredentialProfileRepository(
      secretStore: const _WindowNativeSecretStore(),
      metadataStore: const _WindowNativeMetadataStore(),
    );
  }

  static const int maxSecretBytes = 2048;
  static const int metadataVersion = 1;

  final CredentialSecretStore _secretStore;
  final CredentialMetadataStore _metadataStore;
  final Map<String, String> _environment;
  final bool Function() _codexConfigured;

  @override
  Future<List<CredentialProfileSummary>> all() async {
    final metadata = await _readMetadata();
    return [
      await _summary(Provider.codex, metadata),
      await _summary(Provider.kimi, metadata),
      await _summary(Provider.glm, metadata),
    ];
  }

  @override
  Future<CredentialProfileSummary> saveApiKey({
    required Provider provider,
    required String label,
    required String apiKey,
  }) async {
    if (provider == Provider.codex) {
      throw const CredentialProfileException('Codex 不接受手动 Token');
    }
    final safeLabel = _validateLabel(label);
    final safeSecret = _validateSecret(apiKey);
    if (_environmentSecret(provider) != null) {
      throw const CredentialProfileException('当前由环境变量管理，不能在应用内替换');
    }

    final previousSecret = await _secretStore.read(provider);
    final metadata = await _readMetadata();
    final previousMetadata = metadata[provider];
    await _secretStore.write(provider, safeSecret);
    metadata[provider] = _ProfileMetadata(label: safeLabel);
    try {
      await _writeMetadata(metadata);
    } on Object {
      if (previousSecret == null) {
        await _secretStore.delete(provider);
      } else {
        await _secretStore.write(provider, previousSecret);
      }
      if (previousMetadata == null) {
        metadata.remove(provider);
      } else {
        metadata[provider] = previousMetadata;
      }
      throw const CredentialProfileException('保存本机配置元数据失败');
    }
    return _summary(provider, metadata);
  }

  @override
  Future<CredentialProfileSummary> saveCodexNote({
    required String label,
    required int? resetCount,
    required DateTime? resetExpiresAt,
  }) async {
    final safeLabel = _validateLabel(label);
    if ((resetCount == null) != (resetExpiresAt == null)) {
      throw const CredentialProfileException('请同时填写可重置次数和到期时间');
    }
    if (resetCount != null && (resetCount < 0 || resetCount > 1000000)) {
      throw const CredentialProfileException('配置内容格式不正确');
    }
    final metadata = await _readMetadata();
    metadata[Provider.codex] = _ProfileMetadata(
      label: safeLabel,
      resetCount: resetCount,
      resetExpiresAt: resetExpiresAt?.toUtc(),
    );
    await _writeMetadata(metadata);
    return _summary(Provider.codex, metadata);
  }

  @override
  Future<CredentialProfileSummary> delete(Provider provider) async {
    final metadata = await _readMetadata();
    final previousMetadata = metadata.remove(provider);
    String? previousSecret;
    if (provider != Provider.codex) {
      if (_environmentSecret(provider) != null) {
        throw const CredentialProfileException('当前由环境变量管理，不能在应用内删除');
      }
      previousSecret = await _secretStore.read(provider);
      await _secretStore.delete(provider);
    }
    try {
      await _writeMetadata(metadata);
    } on Object {
      if (provider != Provider.codex && previousSecret != null) {
        await _secretStore.write(provider, previousSecret);
      }
      if (previousMetadata != null) {
        metadata[provider] = previousMetadata;
      }
      throw const CredentialProfileException('保存本机配置元数据失败');
    }
    return _summary(provider, metadata);
  }

  Future<ResetAllowance?> resolveCodexResetAllowance() async {
    final metadata = (await _readMetadata())[Provider.codex];
    if (metadata?.resetCount == null) return null;
    return ResetAllowance(
      count: metadata!.resetCount!,
      expiresAt: metadata.resetExpiresAt,
      source: ResetAllowanceSource.manual,
    );
  }

  Future<CredentialProfileSummary> _summary(
    Provider provider,
    Map<Provider, _ProfileMetadata> metadata,
  ) async {
    final profile = metadata[provider];
    final label = profile?.label ?? _defaultLabel(provider);
    if (provider == Provider.codex) {
      final configured = _codexConfigured();
      return CredentialProfileSummary(
        provider: provider,
        label: label,
        configured: configured,
        source: configured
            ? CredentialSource.codexLocalLogin
            : CredentialSource.notConfigured,
        resetCount: profile?.resetCount,
        resetExpiresAt: profile?.resetExpiresAt,
        resetIsManual: profile?.resetCount != null,
      );
    }

    final environmentSecret = _environmentSecret(provider);
    if (environmentSecret != null) {
      return CredentialProfileSummary(
        provider: provider,
        label: label,
        configured: true,
        source: CredentialSource.environment,
      );
    }
    final stored = await _secretStore.read(provider);
    final configured = stored != null && _isValidRuntimeSecret(stored);
    return CredentialProfileSummary(
      provider: provider,
      label: label,
      configured: configured,
      source: configured
          ? CredentialSource.windowsCredentialManager
          : CredentialSource.notConfigured,
    );
  }

  String? _environmentSecret(Provider provider) {
    final name = switch (provider) {
      Provider.kimi => 'QUOTA_WATCH_KIMI_API_KEY',
      Provider.glm => 'QUOTA_WATCH_GLM_API_KEY',
      Provider.codex => null,
    };
    if (name == null) return null;
    final value = _environment[name]?.trim() ?? '';
    return _isValidRuntimeSecret(value) ? value : null;
  }

  Future<Map<Provider, _ProfileMetadata>> _readMetadata() async {
    final raw = await _metadataStore.read();
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> ||
          decoded['version'] != metadataVersion ||
          decoded['profiles'] is! Map<String, dynamic>) {
        return {};
      }
      final profiles = decoded['profiles'] as Map<String, dynamic>;
      final result = <Provider, _ProfileMetadata>{};
      for (final provider in Provider.values) {
        final item = profiles[provider.name];
        if (item is! Map<String, dynamic>) continue;
        final label = item['label'];
        if (label is! String) continue;
        final resetCount = item['resetCount'];
        final rawExpiresAt = item['resetExpiresAt'];
        result[provider] = _ProfileMetadata(
          label: label,
          resetCount: resetCount is int && resetCount >= 0 ? resetCount : null,
          resetExpiresAt: rawExpiresAt is String
              ? DateTime.tryParse(rawExpiresAt)?.toUtc()
              : null,
        );
      }
      return result;
    } on Object {
      return {};
    }
  }

  Future<void> _writeMetadata(
    Map<Provider, _ProfileMetadata> metadata,
  ) async {
    final payload = {
      'version': metadataVersion,
      'profiles': {
        for (final entry in metadata.entries)
          entry.key.name: {
            'label': entry.value.label,
            if (entry.value.resetCount != null)
              'resetCount': entry.value.resetCount,
            if (entry.value.resetExpiresAt != null)
              'resetExpiresAt':
                  entry.value.resetExpiresAt!.toUtc().toIso8601String(),
          },
      },
    };
    await _metadataStore.write(
      '${const JsonEncoder.withIndent('  ').convert(payload)}\n',
    );
  }
}

class _ProfileMetadata {
  const _ProfileMetadata({
    required this.label,
    this.resetCount,
    this.resetExpiresAt,
  });

  final String label;
  final int? resetCount;
  final DateTime? resetExpiresAt;
}

class _WindowNativeSecretStore implements CredentialSecretStore {
  const _WindowNativeSecretStore();

  @override
  Future<String?> read(Provider provider) {
    return WindowNative.readProviderApiKey(provider.name);
  }

  @override
  Future<void> write(Provider provider, String secret) async {
    if (!await WindowNative.writeProviderApiKey(provider.name, secret)) {
      throw const CredentialProfileException('保存到 Windows 凭据管理器失败');
    }
  }

  @override
  Future<void> delete(Provider provider) async {
    if (!await WindowNative.deleteProviderApiKey(provider.name)) {
      throw const CredentialProfileException('删除 Windows 凭据失败');
    }
  }
}

class _WindowNativeMetadataStore implements CredentialMetadataStore {
  const _WindowNativeMetadataStore();

  @override
  Future<String?> read() => WindowNative.readCredentialMetadata();

  @override
  Future<void> write(String contents) async {
    if (!await WindowNative.writeCredentialMetadata(contents)) {
      throw const CredentialProfileException('保存本机配置元数据失败');
    }
  }
}

bool _detectCodex() {
  try {
    resolveCodexCommand();
    return true;
  } on CodexClientException {
    return false;
  }
}

String _validateLabel(String value) {
  final label = value.trim();
  if (label.isEmpty ||
      label.length > 80 ||
      label.contains('\r') ||
      label.contains('\n')) {
    throw const CredentialProfileException('配置内容格式不正确');
  }
  return label;
}

String _validateSecret(String value) {
  final secret = value.trim();
  if (secret.isEmpty ||
      secret.contains('\r') ||
      secret.contains('\n') ||
      utf8.encode(secret).length >
          WindowsCredentialProfileRepository.maxSecretBytes) {
    throw const CredentialProfileException('配置内容格式不正确');
  }
  return secret;
}

bool _isValidRuntimeSecret(String value) {
  return value.isNotEmpty &&
      value.length <= 8192 &&
      !value.contains('\r') &&
      !value.contains('\n');
}

String _defaultLabel(Provider provider) => switch (provider) {
      Provider.codex => '本机 Codex 登录',
      Provider.kimi => 'Kimi Code',
      Provider.glm => 'GLM Coding Plan',
    };
