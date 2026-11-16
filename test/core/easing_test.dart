// Checks lib/src/core/easing.dart against Recharts' easing.ts (fixtures from
// tool/fixtures_gen).

import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/src/core/easing.dart';

import 'fixture_utils.dart';

void main() {
  final fixtures = loadFixture('easing.json') as Map<String, dynamic>;
  final ts = dnList(fixtures['ts']);

  void checkSamples(Mismatches m, String label, EasingFunction? f, Object? out) {
    m.check((f == null) == (out == null), () => '$label: got ${f == null ? 'null' : 'a function'}, want $out');
    if (f == null || out == null) return;
    final want = dnList(out);
    for (var i = 0; i < ts.length; i++) {
      final got = f(ts[i]);
      m.check(close(got, want[i]), () => '$label(${ts[i]}) = $got, want ${want[i]}');
    }
  }

  test('createEasingFunction matches Recharts for names and cubic-bezier strings', () {
    final m = Mismatches();
    for (final c in fixtures['named'] as List) {
      checkSamples(m, "createEasingFunction('${c['name']}')", createEasingFunction(c['name'] as String), c['out']);
    }
    m.expectNone();
  });

  test('configBezier matches Recharts', () {
    final m = Mismatches();
    for (final c in fixtures['bezier'] as List) {
      final a = dnList(c['args']);
      checkSamples(m, 'configBezier($a)', configBezier(a[0], a[1], a[2], a[3]), c['out']);
    }
    m.expectNone();
  });

  test('createSpringEasing matches Recharts', () {
    final m = Mismatches();
    for (final c in fixtures['spring'] as List) {
      final cfg = c['config'] as Map<String, dynamic>;
      final f = createSpringEasing(
        stiff: dn(cfg['stiff']) ?? 100,
        damping: dn(cfg['damping']) ?? 8,
        dt: dn(cfg['dt']) ?? 16.67,
      );
      checkSamples(m, 'createSpringEasing($cfg)', f, c['out']);
    }
    m.expectNone();
  });

  test('easing.named.spec.ts: ease-out and ease-in-out match their explicit CSS control points', () {
    for (final (name, p) in [('ease-out', [0.0, 0.0, 0.58, 1.0]), ('ease-in-out', [0.42, 0.0, 0.58, 1.0])]) {
      final named = configBezierNamed(name), explicit = configBezier(p[0], p[1], p[2], p[3]);
      for (final t in [0.1, 0.25, 0.5, 0.75, 0.9]) {
        expect(named(t), closeTo(explicit(t), 1e-8), reason: '$name($t)');
      }
    }
  });

  test('createEasingFunction passes functions through and rejects other input', () {
    double f(double t) => t * t;
    expect(createEasingFunction(f), same(f));
    expect(createEasingFunction(42), isNull);
    expect(const RechartsCurve(_half).transform(0.5), 0.25);
  });
}

double _half(double t) => t / 2;
