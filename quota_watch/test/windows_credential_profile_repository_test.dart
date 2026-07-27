import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:quota_watch/data/models/credential_profile.dart';
import 'package:quota_watch/data/models/quota_models.dart';
import 'package:quota_watch/data/repositories/credential_profile_repository.dart';
import 'package:quota_watch/data/repositories/windows_credential_profile_repository.dart';

void main() {
  test('reads defaults and reports only non-secret configuration status',
      () async {
    final secrets = _MemorySecretStore()
      ..values[Provider.kimi] = 'stored-placeholder';
    final repository = WindowsCredentialProfileRepository(
      secretStore: secrets,
      metadataStore: _MemoryMetadataStore(),
      environment: const {},
      codexConfigured: () => true,
    );

    final profiles = await repository.all();

    expect(profiles.map((profile) => profile.provider), Provider.values);
    expect(profiles[0].source, CredentialSource.codexLocalLogin);
    expect(profiles[1].source, CredentialSource.windowsCredentialManager);
    expect(profiles[2].source, CredentialSource.notConfigured);
  });

  test('environment keys take priority without being serialized', () async {
    final metadata = _MemoryMetadataStore();
    final repository = WindowsCredentialProfileRepository(
      secretStore: _MemorySecretStore(),
      metadataStore: metadata,
      environment: const {
        'QUOTA_WATCH_GLM_API_KEY': 'environment-placeholder',
      },
      codexConfigured: () => false,
    );

    final glm = (await repository.all())[2];

    expect(glm.configured, isTrue);
    expect(glm.source, CredentialSource.environment);
    expect(metadata.contents, isNull);
  });

  test('saves a key to the secret store and only its label to metadata',
      () async {
    final secrets = _MemorySecretStore();
    final metadata = _MemoryMetadataStore();
    final repository = WindowsCredentialProfileRepository(
      secretStore: secrets,
      metadataStore: metadata,
      environment: const {},
      codexConfigured: () => false,
    );

    final profile = await repository.saveApiKey(
      provider: Provider.kimi,
      label: '我的 Kimi',
      apiKey: 'short-lived-placeholder',
    );

    expect(profile.configured, isTrue);
    expect(secrets.values[Provider.kimi], 'short-lived-placeholder');
    expect(metadata.contents, contains('我的 Kimi'));
    expect(metadata.contents, isNot(contains('short-lived-placeholder')));
    final decoded = jsonDecode(metadata.contents!) as Map<String, dynamic>;
    final serialized = jsonEncode(decoded);
    expect(serialized, isNot(contains('apiKey')));
    expect(serialized, isNot(contains('secret')));
  });

  test('restores the previous key when metadata persistence fails', () async {
    final secrets = _MemorySecretStore()
      ..values[Provider.kimi] = 'previous-placeholder';
    final metadata = _MemoryMetadataStore()..failWrites = true;
    final repository = WindowsCredentialProfileRepository(
      secretStore: secrets,
      metadataStore: metadata,
      environment: const {},
      codexConfigured: () => false,
    );

    await expectLater(
      repository.saveApiKey(
        provider: Provider.kimi,
        label: 'replacement',
        apiKey: 'new-placeholder',
      ),
      throwsA(isA<CredentialProfileException>()),
    );

    expect(secrets.values[Provider.kimi], 'previous-placeholder');
  });

  test('validates labels, key byte length, and environment ownership',
      () async {
    final repository = WindowsCredentialProfileRepository(
      secretStore: _MemorySecretStore(),
      metadataStore: _MemoryMetadataStore(),
      environment: const {
        'QUOTA_WATCH_KIMI_API_KEY': 'environment-placeholder',
      },
      codexConfigured: () => false,
    );

    for (final call in [
      () => repository.saveApiKey(
            provider: Provider.kimi,
            label: '',
            apiKey: 'placeholder',
          ),
      () => repository.saveApiKey(
            provider: Provider.glm,
            label: 'GLM',
            apiKey: '密' * 700,
          ),
      () => repository.saveApiKey(
            provider: Provider.kimi,
            label: 'Kimi',
            apiKey: 'replacement',
          ),
    ]) {
      await expectLater(call(), throwsA(isA<CredentialProfileException>()));
    }
  });

  test('persists and resolves explicitly manual Codex reset metadata',
      () async {
    final metadata = _MemoryMetadataStore();
    final repository = WindowsCredentialProfileRepository(
      secretStore: _MemorySecretStore(),
      metadataStore: metadata,
      environment: const {},
      codexConfigured: () => true,
    );
    final expiry = DateTime.utc(2026, 8, 1);

    final profile = await repository.saveCodexNote(
      label: '本机 Codex',
      resetCount: 3,
      resetExpiresAt: expiry,
    );
    final allowance = await repository.resolveCodexResetAllowance();

    expect(profile.resetIsManual, isTrue);
    expect(allowance?.count, 3);
    expect(allowance?.expiresAt, expiry);
    expect(allowance?.source, ResetAllowanceSource.manual);

    final cleared = await repository.delete(Provider.codex);
    expect(cleared.resetCount, isNull);
    expect(await repository.resolveCodexResetAllowance(), isNull);
  });

  test('deletes stored provider credentials and metadata together', () async {
    final secrets = _MemorySecretStore();
    final metadata = _MemoryMetadataStore();
    final repository = WindowsCredentialProfileRepository(
      secretStore: secrets,
      metadataStore: metadata,
      environment: const {},
      codexConfigured: () => false,
    );
    await repository.saveApiKey(
      provider: Provider.glm,
      label: 'GLM Local',
      apiKey: 'stored-placeholder',
    );

    final deleted = await repository.delete(Provider.glm);

    expect(deleted.configured, isFalse);
    expect(secrets.values[Provider.glm], isNull);
    expect(metadata.contents, isNot(contains('GLM Local')));
  });
}

class _MemorySecretStore implements CredentialSecretStore {
  final values = <Provider, String>{};

  @override
  Future<String?> read(Provider provider) async => values[provider];

  @override
  Future<void> write(Provider provider, String secret) async {
    values[provider] = secret;
  }

  @override
  Future<void> delete(Provider provider) async {
    values.remove(provider);
  }
}

class _MemoryMetadataStore implements CredentialMetadataStore {
  String? contents;
  bool failWrites = false;

  @override
  Future<String?> read() async => contents;

  @override
  Future<void> write(String contents) async {
    if (failWrites) throw StateError('offline metadata failure');
    this.contents = contents;
  }
}
