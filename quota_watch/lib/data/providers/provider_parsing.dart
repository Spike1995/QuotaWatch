/// Shared tolerant number conversion used by the migrated Provider parsers.
///
/// It accepts finite numbers and numeric strings, while explicitly rejecting
/// booleans, null, NaN and infinity.
double? providerNumber(Object? value) {
  if (value == null || value is bool) return null;
  final number = switch (value) {
    num() => value.toDouble(),
    String() => double.tryParse(value),
    _ => null,
  };
  if (number == null || !number.isFinite) return null;
  return number;
}

int? providerInt(Object? value) => providerNumber(value)?.truncate();

/// Parses ISO 8601 while truncating Provider nanoseconds to Dart microseconds.
///
/// Naive values are treated as UTC to match the Python baseline.
DateTime? parseProviderIso(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  var text = value.trim();
  text = text.replaceFirstMapped(
    RegExp(r'\.(\d{7,})(Z|[+-]\d{2}:?\d{2})?$'),
    (match) => '.${match.group(1)!.substring(0, 6)}${match.group(2) ?? ''}',
  );
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;
  final hasTimezone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(text);
  if (hasTimezone || parsed.isUtc) return parsed;
  return DateTime.utc(
    parsed.year,
    parsed.month,
    parsed.day,
    parsed.hour,
    parsed.minute,
    parsed.second,
    parsed.millisecond,
    parsed.microsecond,
  );
}
