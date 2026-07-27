import '../../models/quota_models.dart';
import '../provider_parsing.dart';

class GlmUsageParser {
  const GlmUsageParser();

  static const int _default5hTokenLimit = 40000000;
  static const double _millisecondThreshold = 1e12;

  List<QuotaWindow> parse(Object? payload) {
    if (payload is! Map<String, dynamic>) {
      throw const FormatException('GLM 响应不是对象');
    }
    final windows = <QuotaWindow>[];
    for (final rawItem in _extractLimits(payload)) {
      if (rawItem is! Map<String, dynamic>) continue;
      final window = _itemToWindow(rawItem);
      if (window != null) windows.add(window);
    }
    return windows;
  }

  List<Object?> _extractLimits(Map<String, dynamic> payload) {
    final data = payload['data'];
    if (data is Map<String, dynamic>) {
      final limits = data['limits'];
      if (limits is List) return limits;
    }
    final limits = payload['limits'];
    return limits is List ? limits : const [];
  }

  QuotaWindow? _itemToWindow(Map<String, dynamic> item) {
    final type = item['type'];
    if (type is! String) return null;
    final unitNumber = providerNumber(item['unit']);
    final unit = unitNumber?.truncate();

    if (_usesPercentageContract(item, type, unit)) {
      return _percentageWindow(item, type, unit);
    }

    var limit = providerNumber(item['usage']);
    var used = providerNumber(item['currentValue']);
    if (limit == null || limit <= 0) {
      if (unit == 3 && used != null) {
        limit = _default5hTokenLimit.toDouble();
      } else {
        return null;
      }
    }
    used ??= 0;

    final percentage = providerNumber(item['percentage']);
    final note = percentage != null && percentage > 100
        ? '已超额（${percentage.toStringAsFixed(0)}%）'
        : null;
    return QuotaWindow(
      label: _unitLabel(unit, type),
      used: used,
      limit: limit,
      unit: type == 'TOKENS_LIMIT' ? 'tokens' : 'calls',
      resetAt: _parseResetTime(item['nextResetTime']),
      note: note,
    );
  }

  bool _usesPercentageContract(
    Map<String, dynamic> item,
    String type,
    int? unit,
  ) {
    if (providerNumber(item['percentage']) == null) return false;
    if (type == 'TOKENS_LIMIT') {
      return item.containsKey('number') ||
          (providerNumber(item['usage']) == null &&
              providerNumber(item['currentValue']) == null);
    }
    if (type == 'TIME_LIMIT') {
      return unit == 5 ||
          item.containsKey('remaining') ||
          item['usageDetails'] is List;
    }
    return false;
  }

  QuotaWindow _percentageWindow(
    Map<String, dynamic> item,
    String type,
    int? unit,
  ) {
    final percentage = providerNumber(item['percentage']);
    if (percentage == null || percentage < 0 || percentage > 100) {
      throw const FormatException('GLM percentage 契约无效');
    }
    return QuotaWindow(
      label: _unitLabel(unit, type),
      used: percentage,
      limit: 100,
      unit: 'percent',
      resetAt: _parseResetTime(item['nextResetTime']),
      note: '按 GLM 服务端已用比例',
    );
  }

  DateTime? _parseResetTime(Object? value) {
    if (value == null) return null;
    final number = providerNumber(value);
    if (number == null) return parseProviderIso(value);
    final seconds = number > _millisecondThreshold ? number / 1000 : number;
    try {
      return DateTime.fromMicrosecondsSinceEpoch(
        (seconds * Duration.microsecondsPerSecond).truncate(),
        isUtc: true,
      );
    } on RangeError {
      return null;
    }
  }

  String _unitLabel(int? unit, String type) {
    if (type == 'TIME_LIMIT' && (unit == null || unit == 0 || unit == 5)) {
      return '月度/MCP 工具窗口';
    }
    return switch (unit) {
      null => type,
      3 => '5 小时窗口',
      6 => '周窗口',
      0 || 5 => '月度/MCP 工具窗口',
      _ => 'unit $unit 窗口',
    };
  }
}
