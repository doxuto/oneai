/// Tolerant readers for callable responses.
///
/// flutter-firebase-contract lists these as the three recurring traps:
///   - `as double` on a JSON number that arrived as int
///   - `cast<String>()` on a List<dynamic>
///   - a strict enum decode that throws on a value a newer server added
/// `strict-casts: true` in analysis_options turns the unsafe spellings into
/// compile errors; these helpers are the safe ones.
library;

String? readString(Map<String, dynamic> json, String key) {
  final v = json[key];
  return v is String ? v : null;
}

String readRequiredString(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v is String) return v;
  throw FormatException('Expected String at "$key", got ${v.runtimeType}');
}

int? readInt(Map<String, dynamic> json, String key) {
  final v = json[key];
  return v is num ? v.toInt() : null;
}

double? readDouble(Map<String, dynamic> json, String key) {
  final v = json[key];
  return v is num ? v.toDouble() : null;
}

bool readBool(Map<String, dynamic> json, String key, {bool orElse = false}) {
  final v = json[key];
  return v is bool ? v : orElse;
}

/// The server sends ISO-8601 with fractional seconds and Z. v1's
/// `{_seconds, _nanoseconds}` shape is gone — see docs/05 §1.
DateTime? readDateTime(Map<String, dynamic> json, String key) {
  final v = json[key];
  return v is String ? DateTime.tryParse(v) : null;
}

List<Map<String, dynamic>> readObjectList(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v is! List) return const [];
  return v.whereType<Map<Object?, Object?>>().map(Map<String, dynamic>.from).toList();
}

List<String> readStringList(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v is! List) return const [];
  return v.whereType<String>().toList();
}

Map<String, dynamic>? readObject(Map<String, dynamic> json, String key) {
  final v = json[key];
  return v is Map ? Map<String, dynamic>.from(v) : null;
}

/// Decode an enum leniently: an unrecognised value falls back rather than
/// throwing, so a newer server cannot crash an older client.
T readEnum<T>(
  Map<String, dynamic> json,
  String key,
  Map<String, T> byName,
  T fallback,
) {
  final v = json[key];
  if (v is! String) return fallback;
  return byName[v] ?? fallback;
}
