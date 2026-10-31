// Checks lib/src/core/scale.dart against d3-scale wrapped by Recharts'
// rechartsScaleFactory (fixtures from tool/fixtures_gen).

import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/src/core/scale.dart';

import 'fixture_utils.dart';

void main() {
  final fixtures = loadFixture('scales.json') as Map<String, dynamic>;

  /// Fixture map inputs: numbers, null (undefined) or the 'NaN' string.
  Object? input(Object? v) => v is String && v != 'NaN' ? v : (v == null ? null : dn(v));

  void checkWrapper(Mismatches m, RechartsScale s, Map c, String label) {
    m.check(closeList(s.range, dnList(c['rechartsRange'])), () => '$label range ${s.range}, want ${c['rechartsRange']}');
    m.check(s.rangeMin == s.range[0] && s.rangeMax == s.range[1], () => '$label rangeMin/rangeMax');
    for (final p in c['isInRange'] as List) {
      final v = dn(p[0])!;
      m.check(s.isInRange(v) == p[1], () => '$label isInRange($v) = ${s.isInRange(v)}, want ${p[1]}');
    }
  }

  void runContinuous(String kind, RechartsScale Function(Map c) build) {
    final m = Mismatches();
    for (final c in fixtures[kind] as List) {
      final s = build(c);
      final label = '$kind(domain: ${c['domain']}, range: ${c['range']}, clamp: ${c['clamp']}'
          '${c['base'] != null ? ', base: ${c['base']}' : ''}${c['exponent'] != null ? ', exponent: ${c['exponent']}' : ''})';
      checkWrapper(m, s, c, label);
      for (final p in c['map'] as List) {
        final got = s.map(input(p[0]));
        m.check(close(got, dn(p[1])), () => '$label map(${p[0]}) = $got, want ${p[1]}');
      }
      for (final p in c['invert'] as List) {
        final y = dn(p[0])!;
        final got = switch (s) {
          LinearScale s => s.invert(y),
          LogScale s => s.invert(y),
          PowScale s => s.invert(y),
          _ => throw StateError('no invert'),
        };
        m.check(close(got, dn(p[1])), () => '$label invert($y) = $got, want ${p[1]}');
      }
      for (final p in c['ticks'] as List) {
        final got = s.ticks(p[0] as int?);
        m.check(closeList(got, dnList(p[1])), () => '$label ticks(${p[0]}) = $got, want ${p[1]}');
      }
      for (final p in c['nice'] as List) {
        final count = p[0] as int?;
        final RechartsScale niced = switch (s) {
          LinearScale s => count == null ? s.nice() : s.nice(count),
          LogScale s => s.nice(),
          PowScale s => count == null ? s.nice() : s.nice(count),
          _ => throw StateError('no nice'),
        };
        final got = niced.domain.cast<num>();
        m.check(closeList(got, dnList(p[1])), () => '$label nice($count) = $got, want ${p[1]}');
      }
    }
    m.expectNone();
  }

  test('LinearScale matches d3 scaleLinear', () {
    runContinuous('linear', (c) => LinearScale(domain: dnList(c['domain']), range: dnList(c['range']), clamp: c['clamp'] as bool));
  });

  test('LogScale matches d3 scaleLog', () {
    runContinuous(
      'log',
      (c) => LogScale(domain: dnList(c['domain']), range: dnList(c['range']), base: dn(c['base'])!, clamp: c['clamp'] as bool),
    );
  });

  test('PowScale matches d3 scalePow / scaleSqrt', () {
    runContinuous(
      'pow',
      (c) => PowScale(domain: dnList(c['domain']), range: dnList(c['range']), exponent: dn(c['exponent'])!, clamp: c['clamp'] as bool),
    );
  });

  void runBanded(String kind, RechartsScale Function(Map c) build, double Function(RechartsScale) step) {
    final m = Mismatches();
    for (final c in fixtures[kind] as List) {
      final s = build(c);
      final label = '$kind(${c['domain']}, range: ${c['range']}, inner: ${c['paddingInner']}, outer: ${c['paddingOuter']}, '
          'padding: ${c['padding']}, align: ${c['align']}, round: ${c['round']})';
      checkWrapper(m, s, c, label);
      m.check(close(step(s), dn(c['step'])), () => '$label step ${step(s)}, want ${c['step']}');
      m.check(close(s.bandwidth, dn(c['bandwidth'])), () => '$label bandwidth ${s.bandwidth}, want ${c['bandwidth']}');
      m.check(s.ticks() == null, () => '$label ticks should be null');
      m.check(_listEquals(s.domain, c['outDomain'] as List), () => '$label domain ${s.domain}, want ${c['outDomain']}');
      for (final p in c['map'] as List) {
        final position = p[1] == null ? null : BandPosition.values.byName(p[1] as String);
        final got = s.map(p[0], position: position);
        m.check(close(got, dn(p[2])), () => '$label map(${p[0]}, $position) = $got, want ${p[2]}');
      }
    }
    m.expectNone();
  }

  test('BandScale matches d3 scaleBand', () {
    runBanded(
      'band',
      (c) => BandScale(
        domain: c['domain'] as List,
        range: dnList(c['range']),
        paddingInner: dn(c['paddingInner'])!,
        paddingOuter: dn(c['paddingOuter'])!,
        align: dn(c['align'])!,
        round: c['round'] as bool,
      ),
      (s) => (s as BandScale).step,
    );
  });

  test('PointScale matches d3 scalePoint', () {
    runBanded(
      'point',
      (c) => PointScale(
        domain: c['domain'] as List,
        range: dnList(c['range']),
        padding: dn(c['padding'])!,
        align: dn(c['align'])!,
        round: c['round'] as bool,
      ),
      (s) => (s as PointScale).step,
    );
  });

  test('rawRange keeps a reversed range', () {
    expect(LinearScale(domain: [0, 1], range: [300, 0]).rawRange, [300, 0]);
    expect(BandScale(domain: ['a'], range: [300, 0]).rawRange, [300, 0]);
  });
}

bool _listEquals(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
