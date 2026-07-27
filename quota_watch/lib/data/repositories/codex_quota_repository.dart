import '../models/quota_models.dart';
import '../providers/codex/codex_app_server_client.dart';
import '../providers/codex/codex_rate_limits_parser.dart';
import 'quota_repository.dart';

class CodexQuotaRepository implements QuotaRepository {
  CodexQuotaRepository({
    CodexRateLimitsClient? client,
    DateTime Function()? clock,
    CodexRateLimitsParser parser = const CodexRateLimitsParser(),
  })  : _client = client ?? CodexAppServerClient(),
        _clock = clock ?? DateTime.now,
        _parser = parser;

  final CodexRateLimitsClient _client;
  final DateTime Function() _clock;
  final CodexRateLimitsParser _parser;

  ProviderQuota? _lastSuccess;

  @override
  Future<List<ProviderQuota>> all() async {
    final result = await fetchOne();
    return [
      result,
      _notQueried(Provider.kimi),
      _notQueried(Provider.glm),
    ];
  }

  Future<ProviderQuota> fetchOne() async {
    try {
      final payload = await _client.readRateLimits();
      final quota = _parser.parse(payload, fetchedAt: _clock());
      _lastSuccess = quota;
      return quota;
    } on CodexClientException catch (error) {
      return _errorResult(error.userMessage);
    } on FormatException {
      return _errorResult('服务商接口可能已变化');
    } on Object {
      return _errorResult('无法连接到服务商');
    }
  }

  ProviderQuota _errorResult(String message) {
    final cached = _lastSuccess;
    if (cached == null) {
      return ProviderQuota(
        provider: Provider.codex,
        planName: '未知套餐',
        windows: const [],
        status: QuotaStatus.error,
        errorMessage: message,
      );
    }
    final fetchedAt = cached.fetchedAt?.toUtc().toIso8601String();
    final staleMessage =
        fetchedAt == null ? '数据可能已过期' : '数据可能已过期（最近成功于 $fetchedAt）';
    return ProviderQuota(
      provider: cached.provider,
      planName: cached.planName,
      planType: cached.planType,
      expiresAt: cached.expiresAt,
      windows: List<QuotaWindow>.of(cached.windows),
      status: QuotaStatus.error,
      errorMessage: '$message；$staleMessage',
      fetchedAt: cached.fetchedAt,
      credits: cached.credits,
      resetAllowance: cached.resetAllowance,
    );
  }
}

ProviderQuota _notQueried(Provider provider) {
  return ProviderQuota(
    provider: provider,
    planName: '当前场景未查询',
    windows: const [],
    status: QuotaStatus.unknown,
  );
}
