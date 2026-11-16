// Ports of src/util/DataUtils.ts, src/util/round.ts, src/util/isWellBehavedNumber.ts
// and getValueByDataKey from src/util/ChartUtils.ts. JS `undefined` and `null`
// both map to Dart `null`.

import 'dart:math' as math;

import 'core/js_math.dart' as js;

/// `isNan`: a number that is NaN.
bool isNan(Object? v) => v is num && v.isNaN;

/// `isNumber`: a number that is not NaN.
bool isNumber(Object? v) => v is num && !v.isNaN;

bool isNumOrStr(Object? v) => isNumber(v) || v is String;

/// `isWellBehavedNumber`: finite number.
bool isWellBehavedNumber(Object? v) => v is num && v.isFinite;

bool isPositiveNumber(Object? v) => isWellBehavedNumber(v) && (v as num) > 0;

int mathSign(num v) => v == 0 ? 0 : (v > 0 ? 1 : -1);

/// `round(num, 4)` from src/util/round.ts.
double round4(num v, [int precision = 4]) {
  final factor = math.pow(10, precision).toDouble();
  final r = jsRound(v * factor) / factor;
  return r == 0 ? 0.0 : r; // also turns -0 into 0
}

/// JS `Math.round` (halves round towards +Infinity, unlike Dart's `round`).
double jsRound(num v) => js.jsRound(v.toDouble());

/// `interpolate(start, end, t)` from DataUtils.ts.
double? interpolate(num? start, num? end, double t) {
  if (isNumber(start) && isNumber(end)) {
    return round4(start! + t * (end! - start));
  }
  return end?.toDouble();
}

/// JS `String(value)` for the values charts deal with.
String jsString(Object? v) {
  if (v == null) return '';
  if (v is num) {
    if (v.isNaN) return 'NaN';
    if (v.isInfinite) return v > 0 ? 'Infinity' : '-Infinity';
    if (v == v.truncateToDouble() && v.abs() < 1e21) {
      return v.toInt().toString();
    }
    return v.toString();
  }
  if (v is List) return v.map(jsString).join(',');
  return v.toString();
}

/// JS `Number(value)` for strings, numbers, dates and booleans.
double jsNumber(Object? v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  if (v is bool) return v ? 1 : 0;
  if (v is DateTime) return v.millisecondsSinceEpoch.toDouble();
  if (v is String) {
    final s = v.trim();
    if (s.isEmpty) return 0;
    if (s == 'Infinity' || s == '+Infinity') return double.infinity;
    if (s == '-Infinity') return double.negativeInfinity;
    if (s.startsWith('0x') || s.startsWith('0X')) {
      return int.tryParse(s.substring(2), radix: 16)?.toDouble() ?? double.nan;
    }
    return double.tryParse(s) ?? double.nan;
  }
  return double.nan;
}

/// `isPercent` from DataUtils.ts.
bool isPercent(Object? v) => v is String && v.length > 1 && v.indexOf('%') == v.length - 1;

/// `getPercentValue(percent, totalValue, defaultValue, validate)`.
double getPercentValue(Object? percent, num? totalValue, [double defaultValue = 0, bool validate = false]) {
  if (!isNumber(percent) && percent is! String) return defaultValue;
  double value;
  if (isPercent(percent)) {
    if (totalValue == null) return defaultValue;
    final s = percent as String;
    value = totalValue * (double.tryParse(s.substring(0, s.indexOf('%'))) ?? double.nan) / 100;
  } else {
    value = jsNumber(percent);
  }
  if (value.isNaN) value = defaultValue;
  if (validate && totalValue != null && value > totalValue) value = totalValue.toDouble();
  return value;
}

/// `hasDuplicate`: compares by `String(x)` like the JS version.
bool hasDuplicate(List<Object?> ary) {
  final seen = <String>{};
  for (final v in ary) {
    if (!seen.add(jsString(v))) return true;
  }
  return false;
}

/// `getValueByDataKey(obj, dataKey, defaultValue)`.
///
/// [dataKey] is a String/int path (lodash `get`, so `'a.b'` and `'a[0]'` work on
/// Maps and Lists) or a function from the entry to its value.
Object? getValueByDataKey(Object? obj, Object? dataKey, [Object? defaultValue]) {
  if (obj == null || dataKey == null) return defaultValue;
  if (dataKey is Function) return (dataKey as dynamic)(obj) ?? defaultValue;
  if (dataKey is String || dataKey is num) {
    final v = _lodashGet(obj, dataKey);
    return v ?? defaultValue;
  }
  return defaultValue;
}

Object? _lodashGet(Object? obj, Object key) {
  if (obj is Map) {
    if (obj.containsKey(key)) return obj[key];
    if (key is num && obj.containsKey(jsString(key))) return obj[jsString(key)];
  }
  if (key is num) {
    if (obj is List && key >= 0 && key < obj.length) return obj[key.toInt()];
    return null;
  }
  final path = (key as String).replaceAllMapped(RegExp(r'\[(\w+)\]'), (m) => '.${m[1]}').split('.');
  if (path.length == 1) {
    if (obj is List) {
      final i = int.tryParse(key);
      return i != null && i >= 0 && i < obj.length ? obj[i] : null;
    }
    return null;
  }
  Object? cur = obj;
  for (final p in path) {
    if (p.isEmpty) continue;
    if (cur is Map) {
      cur = cur[p];
    } else if (cur is List) {
      final i = int.tryParse(p);
      cur = i != null && i >= 0 && i < cur.length ? cur[i] : null;
    } else {
      return null;
    }
  }
  return cur;
}

/// lodash `sortBy` comparison (`compareAscending`) for one key: stable,
/// null last, numbers numerically, strings by UTF-16 code units.
int compareAscending(Object? a, Object? b) {
  if (identical(a, b) || a == b) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  if (isNan(a)) return isNan(b) ? 0 : 1;
  if (isNan(b)) return -1;
  if (a is num && b is num) return a.compareTo(b);
  if (a is String && b is String) return a.compareTo(b);
  // Mixed types: JS relational comparison coerces both to numbers.
  final an = jsNumber(a), bn = jsNumber(b);
  if (an.isNaN || bn.isNaN) return 0;
  return an.compareTo(bn);
}

/// Stable sort by key, like lodash `sortBy`.
List<T> sortByKey<T>(Iterable<T> items, Object? Function(T) key) {
  final indexed = items.toList().asMap().entries.toList();
  indexed.sort((x, y) {
    final c = compareAscending(key(x.value), key(y.value));
    return c != 0 ? c : x.key.compareTo(y.key);
  });
  return [for (final e in indexed) e.value];
}

/// JS `Array.prototype.slice(start, end)`.
List<T> jsSlice<T>(List<T> a, int start, [int? end]) {
  final len = a.length;
  int norm(int i) => i < 0 ? math.max(len + i, 0) : math.min(i, len);
  final s = norm(start), e = norm(end ?? len);
  return s < e ? a.sublist(s, e) : <T>[];
}

/// `getSliced` (src/util/getSliced.ts): `[0, 0]` means "everything".
List<T> getSliced<T>(List<T> arr, int startIndex, int endIndex) =>
    startIndex + endIndex != 0 ? jsSlice(arr, startIndex, endIndex + 1) : arr;

/// The index a `defaultIndex` activates, as `parseInt` reads it in the payload
/// lookup: null when [desired] is not finite (Recharts keeps the string and
/// finds nothing).
int? defaultPayloadIndex(double? desired) =>
    desired == null || !desired.isFinite ? null : desired.clamp(-1e9, 1e9).truncate();

/// `combineActiveTooltipIndex` clamps without flooring: true when the clamped
/// [desired] index of a [length]-row chart is not a whole number, so ticks,
/// labels, cursor and active shapes (which need an exact index) find nothing.
bool defaultIndexIsFractional(double? desired, int length) {
  if (desired == null || !desired.isFinite) return false;
  final c = math.max(0.0, math.min(desired, length > 0 ? length - 1.0 : double.infinity));
  return c != c.truncateToDouble();
}

/// lodash `get(data, path)` for the paths Recharts' tooltip searchers use:
/// keys split on `.`, `[` and `]` ('1.children[0]', '[0]children[1]', 'children[0]');
/// lists are indexed by canonical integer keys, maps by string key.
Object? lodashGet(Object? data, String path) {
  final keys = [for (final k in path.split(RegExp(r'[.\[\]]'))) if (k.isNotEmpty) k.replaceAll(RegExp('^["\']|["\']\$'), '')];
  if (keys.isEmpty) return null;
  Object? cur = data;
  for (final k in keys) {
    if (cur is List) {
      final i = int.tryParse(k);
      cur = i != null && '$i' == k && i >= 0 && i < cur.length ? cur[i] : null;
    } else if (cur is Map) {
      cur = cur[k];
    } else {
      return null;
    }
    if (cur == null) return null;
  }
  return cur;
}
