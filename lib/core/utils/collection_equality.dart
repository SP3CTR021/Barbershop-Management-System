/// Pure-Dart list equality and hashing helpers used by aggregate domain models
/// without importing `package:flutter/foundation.dart` or `package:collection`.
bool listEquals<T>(List<T>? a, List<T>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

int listHash<T>(List<T>? list) {
  if (list == null) return 0;
  return Object.hashAll(list);
}
