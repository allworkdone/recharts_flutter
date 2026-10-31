// Expectations ported from Recharts 3.10.1 Funnel.spec.tsx, Funnel.animation.spec.tsx and
// FunnelChart.spec.tsx. The chart specs read SVG attributes in jsdom (no text is measured
// by a funnel, so nothing needs mocking); paths are compared as `getTrapezoidPath` strings.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/recharts_flutter.dart';
import 'package:recharts_flutter/src/animation.dart';
import 'package:recharts_flutter/src/engine/funnel.dart';
import 'package:recharts_flutter/src/engine/model.dart';

const pageData = [
  {'name': 'Page A', 'uv': 400, 'pv': 2400, 'amt': 2400},
  {'name': 'Page B', 'uv': 300, 'pv': 4567, 'amt': 2400},
  {'name': 'Page C', 'uv': 300, 'pv': 1398, 'amt': 2400},
  {'name': 'Page D', 'uv': 200, 'pv': 9800, 'amt': 2400},
  {'name': 'Page E', 'uv': 278, 'pv': 3908, 'amt': 2400},
  {'name': 'Page F', 'uv': 189, 'pv': 4800, 'amt': 2400},
];

const funnelData = [
  {'value': 100, 'name': 'a'},
  {'value': 80, 'name': 'b'},
  {'value': 50, 'name': 'c'},
  {'value': 40, 'name': 'd'},
  {'value': 26, 'name': 'e'},
];

String num(double v) => v == v.truncateToDouble() ? v.toInt().toString() : v.toString();

String pathOf(FunnelTrapezoid t) {
  final p = trapezoidPoints(t.x, t.y, t.upperWidth, t.lowerWidth, t.height);
  return 'M ${p.map((o) => '${num(o.dx)},${num(o.dy)}').join('L ')} Z';
}

List<FunnelTrapezoid> trapezoids(Funnel f, {double w = 500, double h = 300, List<Object?> data = const []}) {
  final m = computeCartesianModel(
      chartName: 'FunnelChart', size: Size(w, h), data: data, children: [f], measureFor: (_) => (_) => Size.zero);
  return m.funnels.single.trapezoids;
}

void main() {
  group('computeFunnelTrapezoids', () {
    test('simple funnel paths (Funnel.animation.spec: isAnimationActive=false)', () {
      final t = trapezoids(Funnel(dataKey: 'uv', data: pageData.sublist(0, 2)));
      expect(t.map(pathOf), [
        'M 5,5L 495,5L 433.75,150L 66.25,150L 5,5 Z',
        'M 66.25,150L 433.75,150L 250,295L 250,295L 66.25,150 Z',
      ]);
    });

    test('reversed moves the first trapezoid to the bottom (Funnel.spec)', () {
      final t = trapezoids(Funnel(dataKey: 'value', data: funnelData), h: 300);
      expect([t[0].x, t[0].y], [5, 5]);
      final r = trapezoids(Funnel(dataKey: 'value', data: funnelData, reversed: true), h: 300);
      expect([r[0].x, r[0].y], [54, 237]);
    });

    test('no NaN when all values are 0 (Funnel.spec)', () {
      final zero = [for (final n in 'ABC'.split('')) {'value': 0, 'name': n}];
      final m = computeCartesianModel(
          chartName: 'FunnelChart',
          size: const Size(420, 330),
          data: const [],
          children: [Funnel(dataKey: 'value', data: zero)],
          margin: const Margin(left: 10, top: 20, right: 10, bottom: 10),
          measureFor: (_) => (_) => Size.zero);
      for (final t in m.funnels.single.trapezoids) {
        expect(t.x, 10);
        expect([t.upperWidth, t.lowerWidth], [0, 0]);
        expect([t.y, t.height].every((v) => v.isFinite), isTrue);
      }
    });

    test('empty data and hide render nothing', () {
      expect(trapezoids(const Funnel(dataKey: 'value', data: [])), isEmpty);
      expect(trapezoids(Funnel(dataKey: 'value', data: funnelData, hide: true)), isEmpty);
    });

    test('lastShapeType rectangle keeps the last width; width percent narrows the funnel', () {
      final t = trapezoids(
          Funnel(dataKey: 'value', data: funnelData, lastShapeType: LastShapeType.rectangle, width: '80%'));
      expect(t.last.lowerWidth, t.last.upperWidth);
      expect(t.first.upperWidth, 490 * 0.8);
    });

    test('Cell fills and tooltip entry', () {
      final f = Funnel(dataKey: 'value', data: funnelData, children: const [Cell(fill: Color(0xFFFF0000))]);
      final t = trapezoids(f);
      expect(t[0].fill, const Color(0xFFFF0000));
      expect(t[1].fill, const Color(0xFF808080));
      final m = computeCartesianModel(
          chartName: 'FunnelChart', size: const Size(500, 300), data: const [], children: [f], measureFor: (_) => (_) => Size.zero);
      final e = funnelTooltipEntry(m.funnels.single, const [], 2)!;
      expect([e.name, e.value, e.dataKey, e.color, e.unit], ['c', 50, 'value', const Color(0xFF808080), '']);
    });
  });

  group('animation (Funnel.animation.spec)', () {
    final ease = createEasingFunction('ease')!;
    // setAnimationProgress(0.1) then steps of (1 - 0.1) / 5; the last one is the end.
    final progress = [0.28, 0.46, 0.64, 0.82, 1.0];

    List<List<String>> frames(List<FunnelTrapezoid>? prev, List<FunnelTrapezoid> next) => [
          for (final p in progress)
            interpolateFunnelTrapezoids(matchAnimationItems(prev, next, MatchBy.append), p == 1 ? 1 : ease(p))
                .map(pathOf)
                .toList(),
        ];

    final two = trapezoids(Funnel(dataKey: 'uv', data: pageData.sublist(0, 2)));

    test('entrance grows every trapezoid from its center', () {
      final f = frames(null, two);
      expect(f[0], [
        'M 134.1499,43.2178L 365.8502,43.2178L 336.8877,111.7822L 163.1125,111.7822L 134.1499,43.2178 Z',
        'M 163.1124,188.2178L 336.8876,188.2178L 250,256.7822L 250,256.7822L 163.1124,188.2178 Z',
      ]);
      expect(f[2], [
        'M 26.9792,11.504L 473.0208,11.504L 417.2656,143.4959L 82.7344,143.4959L 26.9792,11.504 Z',
        'M 82.7344,156.504L 417.2656,156.504L 250,288.4959L 250,288.4959L 82.7344,156.504 Z',
      ]);
      expect(f[4], ['M 5,5L 495,5L 433.75,150L 66.25,150L 5,5 Z', 'M 66.25,150L 433.75,150L 250,295L 250,295L 66.25,150 Z']);
    });

    test('dataKey change interpolates from the previous trapezoids', () {
      final pv = trapezoids(Funnel(dataKey: 'pv', data: pageData.sublist(0, 2)));
      final f = frames(two, pv);
      expect(f[0], [
        'M 59.9698,5L 440.0301,5L 462.7125,150L 37.2874,150L 59.9698,5 Z',
        'M 37.2875,150L 462.7126,150L 250.0001,295L 250.0001,295L 37.2875,150 Z',
      ]);
      expect(f[4], ['M 121.2503,5L 378.7497,5L 495,150L 5,150L 121.2503,5 Z', 'M 5,150L 495,150L 250,295L 250,295L 5,150 Z']);
    });

    test('2 to 3 trapezoids: the added one enters from its center (matchAppend)', () {
      final three = trapezoids(Funnel(dataKey: 'uv', data: pageData.sublist(3, 6)));
      final f = frames(two, three);
      expect(f[0], [
        'M 37.5047,5L 462.4953,5L 462.7126,127.1452L 37.2874,127.1452L 37.5047,5 Z',
        'M 37.2875,127.1452L 462.7126,127.1452L 328.7615,249.2904L 171.2387,249.2904L 37.2875,127.1452 Z',
        'M 171.2386,223.8119L 328.7614,223.8119L 250,269.5215L 250,269.5215L 171.2386,223.8119 Z',
      ]);
      expect(f[4].last, 'M 83.4353,198.3333L 416.5647,198.3333L 250,295L 250,295L 83.4353,198.3333 Z');
    });
  });
}
