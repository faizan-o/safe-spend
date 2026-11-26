import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

/// Small helpers for reading Firestore maps without crashing on missing or
/// wrongly typed fields. Every model's `fromMap` uses these.

int readInt(Map<String, dynamic> map, String key, [int fallback = 0]) {
  final value = map[key];
  return value is num ? value.toInt() : fallback;
}

int? readIntOrNull(Map<String, dynamic> map, String key) {
  final value = map[key];
  return value is num ? value.toInt() : null;
}

String readString(Map<String, dynamic> map, String key, [String fallback = '']) {
  final value = map[key];
  return value is String ? value : fallback;
}

String? readStringOrNull(Map<String, dynamic> map, String key) {
  final value = map[key];
  return value is String ? value : null;
}

bool readBool(Map<String, dynamic> map, String key, [bool fallback = false]) {
  final value = map[key];
  return value is bool ? value : fallback;
}

/// Reads a Firestore Timestamp as a local DateTime. Returns null when the
/// field is missing, or is a server timestamp that has not resolved yet
/// (which happens for a moment after a local write).
DateTime? readDate(Map<String, dynamic> map, String key) {
  final value = map[key];
  return value is Timestamp ? value.toDate() : null;
}

Map<String, int> readIntMap(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! Map) return <String, int>{};
  return {
    for (final entry in value.entries)
      entry.key.toString(): entry.value is num ? (entry.value as num).toInt() : 0,
  };
}

Map<String, dynamic> readMap(Map<String, dynamic> map, String key) {
  final value = map[key];
  return value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
}

List<Map<String, dynamic>> readMapList(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item is Map) Map<String, dynamic>.from(item),
  ];
}

/// Finds the enum value whose `name` matches, or returns [fallback].
T enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}
