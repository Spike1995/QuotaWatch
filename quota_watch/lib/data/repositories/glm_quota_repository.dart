import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/quota_models.dart';
import '../providers/glm/glm_usage_parser.dart';
import 'kimi_quota_repository.dart' show ApiKeyResolver;
import 'quota_repository.dart';

class GlmQuotaRepository implements QuotaRepository {
  GlmQuotaRepository({
    required this.client,
    required this.apiKeyResolver,
    this.timeout = const Duration(seconds: 8),
    DateTime Function()? clock,
    GlmUsageParser parser = const GlmUsageParser(),
  })  : _clock = clock ?? DateTime.now,
        _parser = parser;

  static final Uri usageEndpoint = Uri.parse(
    'https://open.bigmodel.cn/api/monitor/usage/quota/limit',
  );
  static const int maxResponseBytes = 1024 * 1024;

  final http.Client client;
  final ApiKeyResolver apiKeyResolver;
  final Duration timeout;
  final DateTime Function() _clock;
  final GlmUsageParser _parser;

  ProviderQuota? _lastSuccess;

  @override
  Future<List<ProviderQuota>> all() async {
    final result = await fetchOne();
    return [
      _notQueried(Provider.codex),
      _notQueried(Provider.kimi),
      result,
    ];
  }

  Future<ProviderQuota> fetchOne() async {
    try {
      final quota = await _fetch().timeout(timeout);
      _lastSuccess = quota;
      return quota;
    } on _GlmProviderException catch (error) {
      return _errorResult(error.message);
    } on TimeoutException {
      return _errorResult('查询超时');
    } on http.ClientException {
      return _errorResult('无法连接到服务商');
    } on Object {
      return _errorResult('无法连接到服务商');
    }
  }

  Future<ProviderQuota> _fetch() async {
    final key = (await apiKeyResolver())?.trim() ?? '';
    if (!_isValidKey(key)) {
      throw const _GlmProviderException('需要重新登录或检查凭据');
    }

    final request = http.Request('GET', usageEndpoint)
      ..followRedirects = false
      ..maxRedirects = 0
      ..headers.addAll({
        'Authorization': key,
        'Accept-Language': 'en-US,en',
        'Content-Type': 'application/json',
      });
    final response = await client.send(request);
    _checkStatus(response.statusCode);

    final bytes = <int>[];
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > maxResponseBytes) {
        throw const _GlmProviderException('服务商接口可能已变化');
      }
      bytes.addAll(chunk);
    }

    final Object? payload;
    try {
      payload = jsonDecode(utf8.decode(bytes));
    } on Object {
      throw const _GlmProviderException('服务商接口可能已变化');
    }
    if (payload is! Map<String, dynamic>) {
      throw const _GlmProviderException('服务商接口可能已变化');
    }

    final List<QuotaWindow> parsed;
    try {
      parsed = _parser.parse(payload);
    } on FormatException {
      throw const _GlmProviderException('服务商接口可能已变化');
    }
    if (parsed.isEmpty) {
      throw const _GlmProviderException('服务商接口可能已变化');
    }

    const sourceNote = 'GLM 官方插件契约，本机实验性只读数据';
    return ProviderQuota(
      provider: Provider.glm,
      planName: 'GLM Coding Plan',
      windows: [
        for (final window in parsed)
          window.copyWith(
            note:
                window.note == null ? sourceNote : '${window.note}；$sourceNote',
          ),
      ],
      status: QuotaStatus.ok,
      fetchedAt: _clock().toUtc(),
    );
  }

  ProviderQuota _errorResult(String message) {
    final cached = _lastSuccess;
    if (cached == null) {
      return ProviderQuota(
        provider: Provider.glm,
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

bool _isValidKey(String value) {
  return value.isNotEmpty &&
      value.length <= 8192 &&
      !value.contains('\r') &&
      !value.contains('\n');
}

void _checkStatus(int statusCode) {
  if (statusCode >= 200 && statusCode < 300) return;
  if (statusCode == 401 || statusCode == 402 || statusCode == 403) {
    throw const _GlmProviderException('需要重新登录或检查凭据');
  }
  if (statusCode == 429) {
    throw const _GlmProviderException('查询过于频繁，请稍后重试');
  }
  if (statusCode == 400 ||
      statusCode == 404 ||
      (statusCode >= 300 && statusCode < 400)) {
    throw const _GlmProviderException('服务商接口可能已变化');
  }
  throw const _GlmProviderException('无法连接到服务商');
}

ProviderQuota _notQueried(Provider provider) {
  return ProviderQuota(
    provider: provider,
    planName: '当前场景未查询',
    windows: const [],
    status: QuotaStatus.unknown,
  );
}

class _GlmProviderException implements Exception {
  const _GlmProviderException(this.message);

  final String message;
}
