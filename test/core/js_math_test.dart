// Checks lib/src/core/js_math.dart against V8 bit for bit (fixtures from
// tool/fixtures_gen), plus the dart:math calls tick math relies on.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/src/core/js_math.dart';

import 'fixture_utils.dart';

void main() {
  final fixtures = loadFixture('js_math.json') as Map<String, dynamic>;

  bool same(double a, double b) => a == b || (a.isNaN && b.isNaN);

  // V8 compiles the same fdlibm code with fused multiply-adds on some CPUs
  // (arm64), which moves ~0.1% of results by one ulp. Tick math only depends
  // on floor() and on exact powers of ten, so those must match exactly.
  bool withinUlp(double a, double b) =>
      same(a, b) || (a - b).abs() <= (b.abs() * 2.3e-16).clamp(double.minPositive, double.infinity);

  void runTable(String key, double Function(double) fn, {bool exact = false}) {
    final m = Mismatches();
    for (final c in fixtures[key] as List) {
      final x = dn(c[0])!, want = dn(c[1])!;
      final got = fn(x);
      final ok = exact || want == want.roundToDouble()
          ? same(got, want)
          : withinUlp(got, want) && (!want.isFinite || got.floor() == want.floor());
      m.check(ok, () => '$key($x) = $got, V8 gives $want');
    }
    m.expectNone();
  }

  test('jsLog matches V8 Math.log', () => runTable('log', jsLog));
  test('jsLog10 matches V8 Math.log10', () => runTable('log10', jsLog10));
  test('math.pow(10, k) matches V8 Math.pow(10, k)', () => runTable('pow10', (k) => math.pow(10, k).toDouble(), exact: true));

  test('jsRound rounds halves up', () {
    expect(jsRound(2.5), 3);
    expect(jsRound(-2.5), -2);
    expect(jsRound(0.49999999999999994), 0);
    expect(jsRound(-0.5), 0);
  });

  test('jsParseFloat takes the numeric prefix', () {
    expect(jsParseFloat(' 0.4px'), 0.4);
    expect(jsParseFloat('1.'), 1);
    expect(jsParseFloat('.5e1x'), 5);
    expect(jsParseFloat('1e'), 1);
    expect(jsParseFloat('-Infinity'), double.negativeInfinity);
    expect(jsParseFloat('abc').isNaN, isTrue);
  });
}
