import 'dart:convert';

/// Encodes a small map into a query-string value so a GoRoute survives a
/// browser refresh (GoRouter `extra` is lost on a full page load).
String encodeRoutePayload(Map<String, dynamic> payload) =>
    Uri.encodeComponent(jsonEncode(payload));

/// Decodes a payload written by [encodeRoutePayload].
/// Returns null for missing/legacy/malformed values so callers can fall back.
Map<String, dynamic>? decodeRoutePayload(String? encoded) {
  if (encoded == null || encoded.isEmpty) return null;
  try {
    final decoded = jsonDecode(Uri.decodeComponent(encoded));
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (_) {
    // Ignore malformed deep links; callers show a friendly fallback.
  }
  return null;
}
