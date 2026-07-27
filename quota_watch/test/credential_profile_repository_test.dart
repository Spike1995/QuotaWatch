import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:quota_watch/data/models/credential_profile.dart';
import 'package:quota_watch/data/models/quota_models.dart';
import 'package:quota_watch/data/repositories/backend_endpoint_policy.dart';
import 'package:quota_watch/data/repositories/credential_profile_repository.dart';

void main() {
  test('读取配置状态时只解析非敏感字段', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/v1/credential-profiles');
      return http.Response.bytes(
        utf8.encode(
          '[{"provider":"codex","label":"本机账号","configured":true,'
          '"source":"codex_local_login","resetCount":3,'
          '"resetExpiresAt":"2026-12-31T16:00:00Z",'
          '"resetSource":"manual"}]',
        ),
        200,
      );
    });
    final repository = CredentialProfileRepository(
      client: client,
      baseUrl: 'http://127.0.0.1:8000',
    );

    final profile = (await repository.all()).single;

    expect(profile.provider, Provider.codex);
    expect(profile.configured, isTrue);
    expect(profile.source, CredentialSource.codexLocalLogin);
    expect(profile.resetCount, 3);
    expect(profile.resetIsManual, isTrue);
  });

  test('保存 Key 使用 JSON PUT 且响应模型不含 Key', () async {
    final client = MockClient((request) async {
      expect(request.method, 'PUT');
      expect(request.url.path, '/api/v1/credential-profiles/kimi');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['label'], '我的 Kimi');
      expect(body['apiKey'], 'short-lived-test-input');
      return http.Response.bytes(
        utf8.encode(
          '{"provider":"kimi","label":"我的 Kimi","configured":true,'
          '"source":"windows_credential_manager"}',
        ),
        200,
      );
    });
    final repository = CredentialProfileRepository(
      client: client,
      baseUrl: 'http://localhost:8000',
    );

    final profile = await repository.saveApiKey(
      provider: Provider.kimi,
      label: '我的 Kimi',
      apiKey: 'short-lived-test-input',
    );

    expect(profile.configured, isTrue);
    expect(profile.source, CredentialSource.windowsCredentialManager);
  });

  test('远程 HTTP 后端在发请求前被拒绝', () async {
    var requested = false;
    final client = MockClient((_) async {
      requested = true;
      return http.Response('', 200);
    });
    final repository = CredentialProfileRepository(
      client: client,
      baseUrl: 'http://192.168.1.10:8000',
    );

    await expectLater(
      repository.all(),
      throwsA(
        isA<CredentialProfileException>().having(
          (error) => error.message,
          'message',
          contains('只允许连接本机'),
        ),
      ),
    );
    expect(requested, isFalse);
  });

  test('后端地址策略允许 loopback HTTP 与远程 HTTPS', () {
    expect(isAllowedBackendUrl('http://127.0.0.1:8000'), isTrue);
    expect(isAllowedBackendUrl('http://localhost:8000'), isTrue);
    expect(isAllowedBackendUrl('https://quota.example.com'), isTrue);
    expect(isAllowedBackendUrl('http://quota.example.com'), isFalse);
    expect(isLoopbackBackendUrl('https://quota.example.com'), isFalse);
    expect(isLoopbackBackendUrl('http://127.255.0.1:8000'), isTrue);
    expect(isLoopbackBackendUrl('http://127.999.0.1:8000'), isFalse);
    expect(isLoopbackBackendUrl('http://127.0.0.1.example.com'), isFalse);
  });
}
