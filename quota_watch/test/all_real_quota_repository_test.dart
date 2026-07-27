import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:quota_watch/data/models/quota_models.dart';
import 'package:quota_watch/data/repositories/all_real_quota_repository.dart';

void main() {
  test('starts all providers concurrently and returns stable order', () async {
    final started = <Provider>[];
    final gates = {
      for (final provider in Provider.values) provider: Completer<void>(),
    };
    Future<ProviderQuota> fetch(Provider provider) async {
      started.add(provider);
      await gates[provider]!.future;
      return _quota(provider);
    }

    final repository = AllRealQuotaRepository(
      fetchCodex: () => fetch(Provider.codex),
      fetchKimi: () => fetch(Provider.kimi),
      fetchGlm: () => fetch(Provider.glm),
    );
    final pending = repository.all();
    await Future<void>.delayed(Duration.zero);

    expect(started.toSet(), Provider.values.toSet());
    gates[Provider.glm]!.complete();
    gates[Provider.codex]!.complete();
    gates[Provider.kimi]!.complete();

    final results = await pending;
    expect(results.map((quota) => quota.provider), Provider.values);
  });

  test('isolates an unexpected provider orchestration failure', () async {
    final repository = AllRealQuotaRepository(
      fetchCodex: () async => _quota(Provider.codex),
      fetchKimi: () async => throw StateError('raw private detail'),
      fetchGlm: () async => _quota(Provider.glm),
    );

    final results = await repository.all();

    expect(results[0].status, QuotaStatus.ok);
    expect(results[1].status, QuotaStatus.error);
    expect(results[1].errorMessage, '本地综合查询失败');
    expect(results[1].errorMessage, isNot(contains('private')));
    expect(results[2].status, QuotaStatus.ok);
  });

  test('attaches only explicitly manual Codex reset metadata', () async {
    final expiresAt = DateTime.utc(2026, 8, 1);
    final repository = AllRealQuotaRepository(
      fetchCodex: () async => _quota(Provider.codex),
      fetchKimi: () async => _quota(Provider.kimi),
      fetchGlm: () async => _quota(Provider.glm),
      resolveCodexResetAllowance: () async => ResetAllowance(
        count: 3,
        expiresAt: expiresAt,
        source: ResetAllowanceSource.manual,
      ),
    );

    final results = await repository.all();

    expect(results[0].resetAllowance?.count, 3);
    expect(results[0].resetAllowance?.expiresAt, expiresAt);
    expect(
      results[0].resetAllowance?.source,
      ResetAllowanceSource.manual,
    );
    expect(results[1].resetAllowance, isNull);
    expect(results[2].resetAllowance, isNull);
  });
}

ProviderQuota _quota(Provider provider) {
  return ProviderQuota(
    provider: provider,
    planName: provider.displayName,
    windows: const [],
  );
}
