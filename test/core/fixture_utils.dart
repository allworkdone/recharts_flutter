// Loads the JSON fixtures written by tool/fixtures_gen and compares numbers
// the way the core tests need (1e-9 tolerance, NaN == NaN, null = undefined).

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

dynamic loadFixture(String name) => jsonDecode(File('test/core/fixtures/$name').readAsStringSync());

/// Decodes a fixture number: JSON numbers, or 'NaN' / 'Infinity' / '-Infinity'.
double? dn(Object? v) => switch (v) {
      null => null,
      num n => n.toDouble(),
      'NaN' => double.nan,
      'Infinity' => double.infinity,
      '-Infinity' => double.negativeInfinity,
      _ => throw ArgumentError('not a fixture number: $v'),
    };

List<double> dnList(Object? v) => [for (final x in v as List) dn(x)!];

/// |a - b| <= max(tol, 1e-15 * |b|): absolute 1e-9, widened to a few ulps for
/// huge magnitudes. NaN matches NaN; infinities must be equal.
bool close(double? a, double? b, [double tol = 1e-9]) {
  if (a == null || b == null) return a == b;
  if (a.isNaN || b.isNaN) return a.isNaN && b.isNaN;
  if (a.isInfinite || b.isInfinite) return a == b;
  return (a - b).abs() <= math.max(tol, b.abs() * 1e-15);
}

bool closeList(List<num?>? actual, List<double?>? expected) {
  if (actual == null || expected == null) return actual == expected;
  if (actual.length != expected.length) return false;
  for (var i = 0; i < actual.length; i++) {
    if (!close(actual[i]?.toDouble(), expected[i])) return false;
  }
  return true;
}

/// Collects mismatches across a fixture table and fails once with the first few.
class Mismatches {
  final List<String> _items = [];
  int checked = 0;

  void check(bool ok, String Function() describe) {
    checked++;
    if (!ok) _items.add(describe());
  }

  void expectNone() {
    expect(checked, greaterThan(0), reason: 'no fixture cases ran');
    expect(_items, isEmpty, reason: '${_items.length} of $checked mismatched:\n${_items.take(15).join('\n')}');
  }
}
