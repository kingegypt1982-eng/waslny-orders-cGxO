/// Coercion helpers for values that come from the API.
///
/// Prisma `Decimal` columns (price, commission, balance, distance, radius…)
/// are serialized as JSON **strings**, so a plain `value as num` throws at
/// runtime with `"39.44": type 'String' is not a subtype of type 'num?'`.
/// Every number read from an API payload should go through these helpers.
library;

/// Parses [value] as a `double`, accepting `num`, numeric `String`, or `null`.
/// Returns `null` when the value is missing or not a finite number.
double? asDoubleOrNull(Object? value) {
  if (value == null) return null;
  if (value is num) {
    final number = value.toDouble();
    return number.isFinite ? number : null;
  }
  if (value is String) {
    final number = double.tryParse(value.trim());
    return number != null && number.isFinite ? number : null;
  }
  return null;
}

/// [asDoubleOrNull] with a default, for money and distance fields.
double asDouble(Object? value, {double fallback = 0}) =>
    asDoubleOrNull(value) ?? fallback;

/// Parses [value] as an `int`, accepting `num`, `String`, or `null`.
/// Decimal strings are truncated (`"3.4"` -> `3`).
int? asIntOrNull(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.isFinite ? value.toInt() : null;
  if (value is String) {
    final text = value.trim();
    return int.tryParse(text) ?? double.tryParse(text)?.toInt();
  }
  return null;
}

/// [asIntOrNull] with a default, for counts and counters.
int asInt(Object? value, {int fallback = 0}) => asIntOrNull(value) ?? fallback;

/// `value.toString()` when present, otherwise [fallback].
String asString(Object? value, {String fallback = ''}) =>
    value == null ? fallback : value.toString();

/// Parses flags that may arrive as `bool`, `"true"`, `1`, etc.
bool asBool(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    switch (value.trim().toLowerCase()) {
      case 'true':
      case '1':
        return true;
      case 'false':
      case '0':
        return false;
    }
  }
  return fallback;
}
