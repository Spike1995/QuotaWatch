import 'package:flutter_test/flutter_test.dart';

import 'package:quota_watch/data/models/quota_models.dart';
import 'package:quota_watch/data/providers/codex/codex_app_server_client.dart';
import 'package:quota_watch/data/repositories/codex_quota_repository.dart';

void main() {
  test('maps app-server output and returns stable provider order', () async {
    final repository = CodexQuotaRepository(
      client: _StubClient([_snapshot()]),
      clock: () => DateTime.utc(2026, 7, 27, 10),
    );

    final quotas = await repository.all();

    expect(quotas.map((quota) => quota.provider), Provider.values);
    expect(quotas[0].status, QuotaStatus.ok);
    expect(quotas[0].planName, 'ChatGPT Plus');
    expect(quotas[1].status, QuotaStatus.unknown);
    expect(quotas[2].status, QuotaStatus.unknown);
  });

  test('normalizes client failures and keeps the last success', () async {
    final repository = CodexQuotaRepository(
      client: _StubClient([
        _snapshot(),
        const CodexClientException(CodexClientFailure.authentication),
      ]),
      clock: () => DateTime.utc(2026, 7, 27, 10),
    );

    final success = await repository.fetchOne();
    final stale = await repository.fetchOne();

    expect(success.status, QuotaStatus.ok);
    expect(stale.status, QuotaStatus.error);
    expect(stale.windows, hasLength(2));
    expect(stale.errorMessage, contains('需要重新登录'));
    expect(stale.errorMessage, contains('数据可能已过期'));
  });

  test('normalizes parser drift without exposing payload details', () async {
    final repository = CodexQuotaRepository(
      client: _StubClient([
        {
          'private': 'must not surface',
        },
      ]),
    );

    final result = await repository.fetchOne();

    expect(result.status, QuotaStatus.error);
    expect(result.errorMessage, '服务商接口可能已变化');
    expect(result.errorMessage, isNot(contains('private')));
  });
}

Map<String, dynamic> _snapshot() {
  return {
    'rateLimits': {
      'planType': 'plus',
      'primary': {
        'usedPercent': 25,
        'windowDurationMins': 300,
        'resetsAt': 1760000000,
      },
      'secondary': {
        'usedPercent': 80,
        'windowDurationMins': 10080,
        'resetsAt': 1760500000,
      },
    },
  };
}

class _StubClient implements CodexRateLimitsClient {
  _StubClient(this.results);

  final List<Object> results;
  var index = 0;

  @override
  Future<Map<String, dynamic>> readRateLimits() async {
    final result = results[index++];
    if (result is CodexClientException) throw result;
    return result as Map<String, dynamic>;
  }
}
