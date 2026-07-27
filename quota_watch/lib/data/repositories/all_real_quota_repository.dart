import 'dart:async';

import '../models/quota_models.dart';
import 'quota_repository.dart';

typedef ProviderQuotaFetcher = Future<ProviderQuota> Function();
typedef ResetAllowanceResolver = Future<ResetAllowance?> Function();

class AllRealQuotaRepository implements QuotaRepository {
  const AllRealQuotaRepository({
    required this.fetchCodex,
    required this.fetchKimi,
    required this.fetchGlm,
    this.resolveCodexResetAllowance,
  });

  final ProviderQuotaFetcher fetchCodex;
  final ProviderQuotaFetcher fetchKimi;
  final ProviderQuotaFetcher fetchGlm;
  final ResetAllowanceResolver? resolveCodexResetAllowance;

  @override
  Future<List<ProviderQuota>> all() async {
    final results = await Future.wait([
      _safeFetch(Provider.codex, fetchCodex),
      _safeFetch(Provider.kimi, fetchKimi),
      _safeFetch(Provider.glm, fetchGlm),
    ]);
    final allowanceResolver = resolveCodexResetAllowance;
    if (allowanceResolver != null) {
      try {
        final allowance = await allowanceResolver();
        if (allowance != null) {
          results[0] = _withResetAllowance(results[0], allowance);
        }
      } on Object {
        // Non-secret manual metadata must never break provider quota results.
      }
    }
    return results;
  }
}

Future<ProviderQuota> _safeFetch(
  Provider provider,
  ProviderQuotaFetcher fetch,
) async {
  try {
    return await fetch();
  } on Object {
    return ProviderQuota(
      provider: provider,
      planName: '未知套餐',
      windows: const [],
      status: QuotaStatus.error,
      errorMessage: '本地综合查询失败',
    );
  }
}

ProviderQuota _withResetAllowance(
  ProviderQuota quota,
  ResetAllowance allowance,
) {
  return ProviderQuota(
    provider: quota.provider,
    planName: quota.planName,
    planType: quota.planType,
    expiresAt: quota.expiresAt,
    windows: quota.windows,
    status: quota.status,
    errorMessage: quota.errorMessage,
    fetchedAt: quota.fetchedAt,
    credits: quota.credits,
    resetAllowance: allowance,
  );
}
