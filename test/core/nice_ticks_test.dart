// Checks lib/src/core/nice_ticks.dart against Recharts' getNiceTickValues.ts
// (fixtures from tool/fixtures_gen).

import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/src/core/nice_ticks.dart';

import 'fixture_utils.dart';

void main() {
  final fixtures = loadFixture('nice_ticks.json') as Map<String, dynamic>;

  void runTable(String key, List<num> Function(List<num> domain, int tickCount, bool allowDecimals, NiceTicksAlgorithm mode) fn) {
    final m = Mismatches();
    for (final c in fixtures[key] as List) {
      final domain = dnList(c['domain']);
      final tickCount = c['tickCount'] as int;
      final allowDecimals = c['allowDecimals'] as bool;
      final mode = NiceTicksAlgorithm.values.byName(c['mode'] as String);
      String label() => '$key($domain, tickCount: $tickCount, allowDecimals: $allowDecimals, ${mode.name})';
      if (c.containsKey('throws')) {
        Object? error;
        try {
          fn(domain, tickCount, allowDecimals, mode);
        } catch (e) {
          error = e;
        }
        m.check(error != null, () => '${label()} should throw like JS (${c['throws']})');
        continue;
      }
      final expected = dnList(c['out']);
      List<num>? actual;
      Object? error;
      try {
        actual = fn(domain, tickCount, allowDecimals, mode);
      } catch (e) {
        error = e;
      }
      m.check(error == null && closeList(actual, expected), () => '${label()}: got ${error ?? actual}, want $expected');
    }
    m.expectNone();
  }

  test('getNiceTickValues matches Recharts', () {
    runTable('nice', (d, n, a, mode) => getNiceTickValues(d, tickCount: n, allowDecimals: a, niceTicksMode: mode));
  });

  test('getTickValuesFixedDomain matches Recharts', () {
    runTable('fixed', (d, n, a, mode) => getTickValuesFixedDomain(d, tickCount: n, allowDecimals: a, niceTicksMode: mode));
  });

  test('float-unfriendly domains give exact decimal ticks', () {
    expect(getNiceTickValues([0, 0.3], tickCount: 5), [0, 0.075, 0.15, 0.225, 0.3]);
    expect(getNiceTickValues([0.1, 0.7], tickCount: 7), [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7]);
  });
}
