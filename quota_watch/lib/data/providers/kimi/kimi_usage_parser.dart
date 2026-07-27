import '../../models/quota_models.dart';
import '../provider_parsing.dart';

/// Pure Dart parser for Kimi Code `/coding/v1/usages`.
///
/// It deliberately has no HTTP, credential, storage, or UI dependency. The
/// accepted aliases and fallback rules mirror the existing Python parser while
/// the live provider path is migrated incrementally.
class KimiUsageParser {
  const KimiUsageParser({DateTime Function()? clock}) : _clock = clock;

  final DateTime Function()? _clock;

  List<QuotaWindow> parse(Object? payload) {
    if (payload is! Map<String, dynamic>) {
      throw const FormatException('Kimi 响应不是对象');
    }

    final windows = <QuotaWindow>[];
    final usage = payload['usage'];
    if (usage is Map<String, dynamic>) {
      final window = _rowToWindow(
        usage,
        item: null,
        defaultLabel: 'Weekly limit',
        index: 0,
      );
      if (window != null) windows.add(window);
    }

    final limits = payload['limits'];
    if (limits is List) {
      for (var index = 0; index < limits.length; index++) {
        final rawItem = limits[index];
        if (rawItem is! Map<String, dynamic>) continue;
        final detail = rawItem['detail'];
        final row = detail is Map<String, dynamic> ? detail : rawItem;
        final window = _rowToWindow(
          row,
          item: rawItem,
          defaultLabel: 'Weekly limit',
          index: index,
        );
        if (window != null) windows.add(window);
      }
    }

    return windows;
  }

  QuotaWindow? _rowToWindow(
    Map<String, dynamic> data, {
    required Map<String, dynamic>? item,
    required String defaultLabel,
    required int index,
  }) {
    final limitValue = providerInt(data['limit']);
    var usedValue = providerInt(data['used']);
    if (usedValue == null) {
      final remaining = providerInt(data['remaining']);
      if (remaining != null && limitValue != null) {
        usedValue = limitValue - remaining;
        if (usedValue < 0) usedValue = 0;
      }
    }
    if (usedValue == null && limitValue == null) return null;

    final limit = limitValue ?? 0;
    var used = usedValue ?? 0;
    if (limit > 0 && used > limit) used = limit;

    return QuotaWindow(
      label: _label(data, item, defaultLabel, index),
      used: used.toDouble(),
      limit: limit.toDouble(),
      unit: 'tokens',
      resetAt: _resetValue(data),
    );
  }

  String _label(
    Map<String, dynamic> data,
    Map<String, dynamic>? item,
    String defaultLabel,
    int index,
  ) {
    final keys = item == null
        ? const ['name', 'title']
        : const ['name', 'title', 'scope'];
    for (final source in [item, data]) {
      if (source == null) continue;
      for (final key in keys) {
        final value = source[key];
        if (value is String && value.trim().isNotEmpty) {
          return value.trim();
        }
      }
    }

    if (item != null) {
      final rawWindow = item['window'];
      if (rawWindow is Map<String, dynamic>) {
        final duration = providerInt(
          _pythonOr(rawWindow['duration'], item['duration']),
        );
        final unit = _pythonOr(rawWindow['timeUnit'], item['timeUnit']);
        if (duration != null && unit is String) {
          return _windowLabel(duration, unit);
        }
      }
    }
    return item == null ? defaultLabel : 'Limit #${index + 1}';
  }

  DateTime? _resetValue(Map<String, dynamic> data) {
    final iso = _firstPresent(
      data,
      const ['reset_at', 'resetAt', 'reset_time', 'resetTime'],
    );
    final parsed = parseProviderIso(iso);
    if (parsed != null) return parsed;

    final seconds = providerInt(
      _firstPresent(data, const ['reset_in', 'resetIn', 'ttl', 'window']),
    );
    if (seconds == null || seconds <= 0) return null;
    final now = (_clock?.call() ?? DateTime.now()).toUtc();
    final wholeSecond = DateTime.utc(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
      now.second,
    );
    return wholeSecond.add(Duration(seconds: seconds));
  }
}

Object? _firstPresent(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    if (data.containsKey(key)) return data[key];
  }
  return null;
}

Object? _pythonOr(Object? first, Object? second) {
  final isFalsy = first == null ||
      first == false ||
      first == 0 ||
      first == '' ||
      (first is Iterable && first.isEmpty) ||
      (first is Map && first.isEmpty);
  return isFalsy ? second : first;
}

String _windowLabel(int duration, String unit) {
  final normalized = unit.toUpperCase();
  if (normalized.contains('MINUTE')) {
    return duration % 60 == 0
        ? '${duration ~/ 60}h limit'
        : '${duration}m limit';
  }
  if (normalized.contains('HOUR')) return '${duration}h limit';
  if (normalized.contains('DAY')) return '${duration}d limit';
  return '${duration}s limit';
}
