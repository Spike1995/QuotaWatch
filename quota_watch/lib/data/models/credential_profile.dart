import 'quota_models.dart';

/// 后端只返回配置状态与非敏感标签，永远不返回 API Key。
enum CredentialSource {
  environment,
  windowsCredentialManager,
  codexLocalLogin,
  notConfigured;

  static CredentialSource fromJson(String value) {
    return switch (value) {
      'environment' => CredentialSource.environment,
      'windows_credential_manager' => CredentialSource.windowsCredentialManager,
      'codex_local_login' => CredentialSource.codexLocalLogin,
      'not_configured' => CredentialSource.notConfigured,
      _ => throw FormatException('不支持的 credential source：$value'),
    };
  }
}

class CredentialProfileSummary {
  final Provider provider;
  final String label;
  final bool configured;
  final CredentialSource source;
  final int? resetCount;
  final DateTime? resetExpiresAt;
  final bool resetIsManual;

  const CredentialProfileSummary({
    required this.provider,
    required this.label,
    required this.configured,
    required this.source,
    this.resetCount,
    this.resetExpiresAt,
    this.resetIsManual = false,
  });

  factory CredentialProfileSummary.fromJson(Map<String, dynamic> json) {
    final configured = json['configured'];
    final resetCount = json['resetCount'];
    if (configured is! bool) {
      throw const FormatException('credential profile 缺少 configured');
    }
    if (resetCount != null && resetCount is! int) {
      throw const FormatException('resetCount 必须是整数');
    }
    return CredentialProfileSummary(
      provider: Provider.fromJson(json['provider'] as String),
      label: json['label'] as String,
      configured: configured,
      source: CredentialSource.fromJson(json['source'] as String),
      resetCount: resetCount as int?,
      resetExpiresAt: _optionalDateTime(json['resetExpiresAt']),
      resetIsManual: json['resetSource'] == 'manual',
    );
  }

  String get sourceLabel {
    return switch (source) {
      CredentialSource.environment => '环境变量',
      CredentialSource.windowsCredentialManager => 'Windows 凭据管理器',
      CredentialSource.codexLocalLogin => 'Codex 本机登录',
      CredentialSource.notConfigured => '未配置',
    };
  }
}

DateTime? _optionalDateTime(Object? value) {
  if (value == null) return null;
  if (value is! String) {
    throw const FormatException('resetExpiresAt 必须是 ISO 8601 字符串');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw const FormatException('resetExpiresAt 不是有效时间');
  }
  return parsed;
}
