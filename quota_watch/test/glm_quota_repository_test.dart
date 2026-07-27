import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:quota_watch/data/models/quota_models.dart';
import 'package:quota_watch/data/repositories/glm_quota_repository.dart';

const _testKey = 'offline-glm-key-placeholder';
const _successPayload = <String, Object?>{
  'data': {
    'limits': [
      {
        'type': 'TOKENS_LIMIT',
        'unit': 3,
        'number': 1,
        'percentage': 75,
        'nextResetTime': 1768000000000,
      },
      {
        'type': 'TIME_LIMIT',
        'unit': 5,
        'number': 1,
        'percentage': 25,
        'remaining': 1,
      },
    ],
  },
};

void main() {
  test('uses the official plugin endpoint and direct Authorization value',
      () async {
    final client = MockClient((request) async {
      expect(request.url, GlmQuotaRepository.usageEndpoint);
      expect(request.headers['Authorization'], _testKey);
      expect(request.headers['Accept-Language'], 'en-US,en');
      expect(request.headers['Content-Type'], 'application/json');
      expect(request.headers.containsKey('Accept'), isFalse);
      expect(request.followRedirects, isFalse);
      return http.Response(jsonEncode(_successPayload), 200);
    });
    final repository = GlmQuotaRepository(
      client: client,
      apiKeyResolver: () async => _testKey,
      clock: () => DateTime.utc(2026, 7, 27, 9),
    );

    final quotas = await repository.all();

    expect(quotas.map((quota) => quota.provider), Provider.values);
    final glm = quotas[2];
    expect(glm.status, QuotaStatus.ok);
    expect(glm.planName, 'GLM Coding Plan');
    expect(glm.windows.map((window) => window.used), [75, 25]);
    expect(
      glm.windows.every((window) => window.note?.contains('本机实验性') == true),
      isTrue,
    );
  });

  test('missing credentials stop before HTTP', () async {
    var sent = false;
    final repository = GlmQuotaRepository(
      client: MockClient((_) async {
        sent = true;
        return http.Response('{}', 200);
      }),
      apiKeyResolver: () async => 'bad\rkey',
    );

    final glm = (await repository.all())[2];

    expect(sent, isFalse);
    expect(glm.status, QuotaStatus.error);
    expect(glm.errorMessage, '需要重新登录或检查凭据');
  });

  for (final testCase in const [
    (302, '服务商接口可能已变化'),
    (401, '需要重新登录或检查凭据'),
    (429, '查询过于频繁，请稍后重试'),
    (500, '无法连接到服务商'),
  ]) {
    test('normalizes HTTP ${testCase.$1} without reading raw errors', () async {
      final repository = GlmQuotaRepository(
        client: MockClient(
          (_) async => http.Response('private response body', testCase.$1),
        ),
        apiKeyResolver: () async => _testKey,
      );

      final glm = (await repository.all())[2];

      expect(glm.errorMessage, testCase.$2);
      expect(glm.errorMessage, isNot(contains('private')));
    });
  }

  test('rejects oversized and contract-drift payloads', () async {
    final responses = [
      http.Response(
        '"${'x' * (GlmQuotaRepository.maxResponseBytes + 1)}"',
        200,
      ),
      http.Response('{"data":{"limits":[]}}', 200),
      http.Response(
        '{"data":{"limits":[{"type":"TOKENS_LIMIT",'
        '"number":1,"percentage":101}]}}',
        200,
      ),
    ];
    var index = 0;
    final repository = GlmQuotaRepository(
      client: MockClient((_) async => responses[index++]),
      apiKeyResolver: () async => _testKey,
    );

    for (var attempt = 0; attempt < responses.length; attempt++) {
      final glm = (await repository.all())[2];
      expect(glm.status, QuotaStatus.error);
      expect(glm.errorMessage, '服务商接口可能已变化');
    }
  });

  test('keeps the last normalized success on a later failure', () async {
    var requestCount = 0;
    final repository = GlmQuotaRepository(
      client: MockClient((_) async {
        requestCount += 1;
        return requestCount == 1
            ? http.Response(jsonEncode(_successPayload), 200)
            : http.Response('ignored', 500);
      }),
      apiKeyResolver: () async => _testKey,
      clock: () => DateTime.utc(2026, 7, 27, 9),
    );

    final success = (await repository.all())[2];
    final stale = (await repository.all())[2];

    expect(success.status, QuotaStatus.ok);
    expect(stale.status, QuotaStatus.error);
    expect(stale.windows, hasLength(2));
    expect(stale.errorMessage, contains('数据可能已过期'));
  });
}
