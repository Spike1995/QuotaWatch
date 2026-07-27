import '../../models/quota_models.dart';

class CodexRateLimitsParser {
  const CodexRateLimitsParser();

  ProviderQuota parse(
    Object? payload, {
    required DateTime fetchedAt,
  }) {
    if (payload is! Map<String, dynamic>) {
      throw const FormatException('Codex 响应不是对象');
    }
    final snapshot = _selectSnapshot(payload);
    final reached = snapshot['rateLimitReachedType'];
    var note = 'Codex app-server 本机只读数据';
    if (reached is String && reached.isNotEmpty) {
      note += '；已触发额度限制';
    }

    final windows = <QuotaWindow>[];
    for (final entry in const [('primary', 1), ('secondary', 2)]) {
      final rawWindow = snapshot[entry.$1];
      if (rawWindow == null) continue;
      if (rawWindow is! Map<String, dynamic>) {
        throw const FormatException('Codex 窗口契约无效');
      }
      windows.add(_parseWindow(rawWindow, entry.$2, note));
    }
    if (windows.isEmpty) {
      throw const FormatException('Codex 没有额度窗口');
    }

    final rawPlanType = snapshot['planType'];
    final planType = rawPlanType is String ? rawPlanType : null;
    return ProviderQuota(
      provider: Provider.codex,
      planName: _planName(planType),
      planType: planType,
      windows: windows,
      status: QuotaStatus.ok,
      fetchedAt: fetchedAt.toUtc(),
      credits: _parseCredits(snapshot['credits']),
    );
  }

  Map<String, dynamic> _selectSnapshot(Map<String, dynamic> payload) {
    final buckets = payload['rateLimitsByLimitId'];
    if (buckets is Map<String, dynamic>) {
      final direct = buckets['codex'];
      if (direct is Map<String, dynamic>) return direct;
      for (final candidate in buckets.values) {
        if (candidate is Map<String, dynamic> &&
            candidate['limitId'] == 'codex') {
          return candidate;
        }
      }
    }
    final historical = payload['rateLimits'];
    if (historical is! Map<String, dynamic>) {
      throw const FormatException('Codex rateLimits 契约无效');
    }
    return historical;
  }

  QuotaWindow _parseWindow(
    Map<String, dynamic> raw,
    int position,
    String note,
  ) {
    final usedRaw = raw['usedPercent'];
    if (usedRaw is bool || usedRaw is! num || !usedRaw.isFinite) {
      throw const FormatException('Codex usedPercent 契约无效');
    }
    final used = usedRaw.toDouble().clamp(0, 100).toDouble();

    final durationRaw = raw['windowDurationMins'];
    int? duration;
    if (durationRaw != null) {
      if (durationRaw is bool || durationRaw is! num || !durationRaw.isFinite) {
        throw const FormatException('Codex windowDurationMins 契约无效');
      }
      duration = durationRaw.truncate();
      if (duration <= 0) {
        throw const FormatException('Codex windowDurationMins 契约无效');
      }
    }

    return QuotaWindow(
      label: _windowLabel(duration, position),
      used: used,
      limit: 100,
      unit: 'percent',
      resetAt: _parseResetAt(raw['resetsAt']),
      note: note,
    );
  }

  DateTime? _parseResetAt(Object? value) {
    if (value == null) return null;
    if (value is bool || value is! num || !value.isFinite) {
      throw const FormatException('Codex resetsAt 契约无效');
    }
    try {
      return DateTime.fromMillisecondsSinceEpoch(
        value.truncate() * Duration.millisecondsPerSecond,
        isUtc: true,
      );
    } on RangeError {
      throw const FormatException('Codex resetsAt 契约无效');
    }
  }

  QuotaCredits? _parseCredits(Object? raw) {
    if (raw == null) return null;
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Codex credits 契约无效');
    }
    final hasCredits = raw['hasCredits'];
    final unlimited = raw['unlimited'];
    final rawBalance = raw['balance'];
    if (hasCredits is! bool ||
        unlimited is! bool ||
        (rawBalance != null && rawBalance is! String)) {
      throw const FormatException('Codex credits 契约无效');
    }
    final balance = rawBalance is String ? rawBalance.trim() : null;
    if (balance != null && (balance.isEmpty || balance.length > 32)) {
      throw const FormatException('Codex credits 契约无效');
    }
    return QuotaCredits(
      hasCredits: hasCredits,
      unlimited: unlimited,
      balance: balance,
    );
  }
}

String _windowLabel(int? durationMinutes, int position) {
  if (durationMinutes == null) {
    return position == 1 ? '主额度窗口' : '次额度窗口';
  }
  if (durationMinutes % (24 * 60) == 0) {
    return '${durationMinutes ~/ (24 * 60)} 天窗口';
  }
  if (durationMinutes % 60 == 0) {
    return '${durationMinutes ~/ 60} 小时窗口';
  }
  return '$durationMinutes 分钟窗口';
}

String _planName(String? planType) {
  return const {
        'free': 'ChatGPT Free',
        'go': 'ChatGPT Go',
        'plus': 'ChatGPT Plus',
        'pro': 'ChatGPT Pro',
        'prolite': 'ChatGPT Pro Lite',
        'team': 'ChatGPT Team',
        'business': 'ChatGPT Business',
        'self_serve_business_usage_based': 'ChatGPT Business',
        'enterprise': 'ChatGPT Enterprise',
        'enterprise_cbp_usage_based': 'ChatGPT Enterprise',
        'edu': 'ChatGPT Edu',
      }[planType] ??
      'ChatGPT Codex';
}
