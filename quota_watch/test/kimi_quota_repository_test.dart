import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:quota_watch/data/models/quota_models.dart';
import 'package:quota_watch/data/repositories/kimi_quota_repository.dart';

const _testKey = 'offline-kimi-key-placeholder';
const _successPayload = <String, Object?>{
  'usage': {
    'name': 'Weekly limit',
    'used': 40,
    'limit': 1000,
    'resetAt': '2026-07-30T00:00:00Z',
  },
  'limits': [
    {
      'detail': {'used': 1, 'limit': 100, 'name': '5h limit'},
      'window': {'duration': 5, 'timeUnit': 'HOUR'},
    },
  ],
};

void main() {
  test('uses the official endpoint and returns the stable provider order',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url, KimiQuotaRepository.usageEndpoint);
      expect(request.headers['Authorization'], 'Bearer $_testKey');
      expect(request.headers['Accept'], 'application/json');
      expect(request.followRedirects, isFalse);
      return http.Response(jsonEncode(_successPayload), 200);
    });
    final repository = KimiQuotaRepository(
      client: client,
      apiKeyResolver: () async => _testKey,
      clock: () => DateTime.utc(2026, 7, 27, 8),
    );

    final quotas = await repository.all();

    expect(quotas.map((quota) => quota.provider), Provider.values);
    expect(quotas[0].status, QuotaStatus.unknown);
    expect(quotas[2].status, QuotaStatus.unknown);
    final kimi = quotas[1];
    expect(kimi.status, QuotaStatus.ok);
    expect(kimi.planName, 'Kimi Code');
    expect(kimi.windows.map((window) => window.label), [
      'Weekly limit',
      '5h limit',
    ]);
    expect(
      kimi.windows.every((window) => window.note?.contains('本机只读') == true),
      isTrue,
    );
    expect(kimi.fetchedAt, DateTime.utc(2026, 7, 27, 8));
  });

  for (final key in [null, '', 'bad\nkey']) {
    test('an invalid key never sends a request: ${key == null}', () async {
      var sent = false;
      final repository = KimiQuotaRepository(
        client: MockClient((_) async {
          sent = true;
          return http.Response('{}', 200);
        }),
        apiKeyResolver: () async => key,
      );

      final kimi = (await repository.all())[1];

      expect(sent, isFalse);
      expect(kimi.status, QuotaStatus.error);
      expect(kimi.errorMessage, '需要重新登录或检查凭据');
    });
  }

  for (final testCase in const [
    (302, '服务商接口可能已变化'),
    (400, '服务商接口可能已变化'),
    (401, '需要重新登录或检查凭据'),
    (402, '需要重新登录或检查凭据'),
    (403, '需要重新登录或检查凭据'),
    (404, '服务商接口可能已变化'),
    (429, '查询过于频繁，请稍后重试'),
    (500, '无法连接到服务商'),
  ]) {
    test('normalizes HTTP ${testCase.$1} without exposing its body', () async {
      final repository = KimiQuotaRepository(
        client: MockClient(
          (_) async => http.Response(
            '{"sensitive":"must-not-be-surfaced"}',
            testCase.$1,
          ),
        ),
        apiKeyResolver: () async => _testKey,
      );

      final kimi = (await repository.all())[1];

      expect(kimi.status, QuotaStatus.error);
      expect(kimi.errorMessage, testCase.$2);
      expect(kimi.errorMessage, isNot(contains('sensitive')));
    });
  }

  test('rejects malformed, non-object, empty, and oversized payloads',
      () async {
    final responses = <http.Response>[
      http.Response('{broken', 200),
      http.Response('[]', 200),
      http.Response('{}', 200),
      http.Response(
        '"${'x' * (KimiQuotaRepository.maxResponseBytes + 1)}"',
        200,
      ),
    ];
    var index = 0;
    final repository = KimiQuotaRepository(
      client: MockClient((_) async => responses[index++]),
      apiKeyResolver: () async => _testKey,
    );

    for (var attempt = 0; attempt < responses.length; attempt++) {
      final kimi = (await repository.all())[1];
      expect(kimi.status, QuotaStatus.error);
      expect(kimi.errorMessage, '服务商接口可能已变化');
    }
  });

  test('normalizes timeout and connection failure', () async {
    final timeoutRepository = KimiQuotaRepository(
      client: MockClient((_) => Completer<http.Response>().future),
      apiKeyResolver: () async => _testKey,
      timeout: const Duration(milliseconds: 1),
    );
    final connectionRepository = KimiQuotaRepository(
      client: MockClient((_) async => throw http.ClientException('offline')),
      apiKeyResolver: () async => _testKey,
    );

    expect((await timeoutRepository.all())[1].errorMessage, '查询超时');
    expect((await connectionRepository.all())[1].errorMessage, '无法连接到服务商');
  });

  test('keeps the last success when a later refresh fails', () async {
    var requestCount = 0;
    final repository = KimiQuotaRepository(
      client: MockClient((_) async {
        requestCount += 1;
        return requestCount == 1
            ? http.Response(jsonEncode(_successPayload), 200)
            : http.Response('{"ignored":"body"}', 500);
      }),
      apiKeyResolver: () async => _testKey,
      clock: () => DateTime.utc(2026, 7, 27, 8),
    );

    final success = (await repository.all())[1];
    final stale = (await repository.all())[1];

    expect(success.status, QuotaStatus.ok);
    expect(stale.status, QuotaStatus.error);
    expect(stale.windows, hasLength(2));
    expect(stale.errorMessage, contains('数据可能已过期'));
    expect(stale.fetchedAt, success.fetchedAt);
  });
}
