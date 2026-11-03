// PolarGrid cases of Recharts 3.10.1 test/polar/PolarGrid.spec.tsx for a
// RadialBarChart: explicit axes (lines, polygons, circles, radialLines) and
// several axes with ids. Values are the spec's literals.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/recharts_flutter.dart';
import 'package:recharts_flutter/src/core/polar_utils.dart';
import 'package:recharts_flutter/src/engine/pie.dart';
import 'package:recharts_flutter/src/engine/polar_axis.dart';
import 'package:recharts_flutter/src/render/polar_scene_painter.dart';

// storybook/stories/data/Page.ts
const pageData = [
  {'name': 'Page A', 'uv': 590, 'pv': 800, 'amt': 1400},
  {'name': 'Page B', 'uv': 590, 'pv': 800, 'amt': 1400},
  {'name': 'Page C', 'uv': 868, 'pv': 967, 'amt': 1506},
  {'name': 'Page D', 'uv': 1397, 'pv': 1098, 'amt': 989},
  {'name': 'Page E', 'uv': 1480, 'pv': 1200, 'amt': 1228},
  {'name': 'Page F', 'uv': 1520, 'pv': 1108, 'amt': 1100},
  {'name': 'Page G', 'uv': 1400, 'pv': 680, 'amt': 1700},
];

PolarModel model(List<RechartsElement> children, double size) => computePolarModel(
      chartName: 'RadialBarChart',
      size: Size(size, size),
      data: pageData,
      children: children,
      layout: PolarLayout.radial,
      options: const PolarOptions(startAngle: 0, endAngle: 360),
    );

/// The numbers of an SVG path `d`, as pairs.
List<Offset> points(String d) {
  final n = RegExp(r'-?\d+(\.\d+)?(e-?\d+)?').allMatches(d).map((m) => double.parse(m[0]!)).toList();
  return [for (var i = 0; i < n.length; i += 2) Offset(n[i], n[i + 1])];
}

Matcher near(double v) => closeTo(v, 1e-9);

void main() {
  group('as a child of RadialBarChart with explicit axes (500x500)', () {
    List<RechartsElement> chart(PolarGrid grid) => [
          const RadialBar(dataKey: 'uv'),
          const PolarAngleAxis(type: AxisDomainType.number, dataKey: 'uv'),
          const PolarRadiusAxis(type: AxisDomainType.category, dataKey: 'name'),
          grid,
        ];
    const lineEnds = [
      (446.0, 250.0),
      (382.7471880386453, 105.79811350806622),
      (233.81444828742286, 54.669439370692714),
      (95.32846015830688, 129.61430831282507),
      (56.673184533066404, 282.2605396950238),
      (142.79816100800434, 414.08462973945564),
      (298.1151554795966, 440.0024521241088),
      (422.3768552364718, 343.28568903526656),
    ];

    test('lines run from the center to the outer radius, one per angle tick', () {
      final m = model(chart(const PolarGrid()), 500);
      final g = polarGridGeometry(m.scene!, m.scene!.grids.single)!;
      expect(g.lines.length, 8);
      for (final (i, (a, b)) in g.lines.indexed) {
        expect(a, const Offset(250, 250));
        expect(b.dx, near(lineEnds[i].$1));
        expect(b.dy, near(lineEnds[i].$2));
      }
    });

    test('polygons are drawn at the category radii 14, 42, ... 182', () {
      final m = model(chart(const PolarGrid()), 500);
      final g = polarGridGeometry(m.scene!, m.scene!.grids.single)!;
      expect(g.radii.length, 7);
      for (final (i, r) in g.radii.indexed) {
        expect(r, near(14.0 + 28 * i));
      }
      // The first polygon's d: 'M264,250L259.4819420027604,239.69986525057615L248.88...'
      final first = points('M264,250L259.4819420027604,239.69986525057615L248.84388916338736,236.04781709790663');
      for (final (i, p) in first.indexed) {
        final e = polarToCartesian(250, 250, g.radii[0], g.angles[i]);
        expect(e.dx, near(p.dx));
        expect(e.dy, near(p.dy));
      }
      // The last: 'M432,250L373.2652460358849,116.09824825749004L234.97055912403553,68.62162227278608'
      final last = points('M432,250L373.2652460358849,116.09824825749004L234.97055912403553,68.62162227278608');
      for (final (i, p) in last.indexed) {
        final e = polarToCartesian(250, 250, g.radii[6], g.angles[i]);
        expect(e.dx, near(p.dx));
        expect(e.dy, near(p.dy));
      }
    });

    test('radialLines: false draws no lines but keeps the rings', () {
      final m = model(chart(const PolarGrid(radialLines: false)), 500);
      final g = polarGridGeometry(m.scene!, m.scene!.grids.single)!;
      expect(g.lines, isEmpty);
      expect(g.radii.length, 7);
    });
  });

  group('with multiple axes (300x300)', () {
    List<RechartsElement> chart(PolarGrid grid) => [
          const RadialBar(angleAxisId: 'axis-pv', radiusAxisId: 'axis-name', dataKey: 'pv'),
          const PolarAngleAxis(angleAxisId: 'axis-uv', dataKey: 'uv', type: AxisDomainType.number),
          const PolarAngleAxis(angleAxisId: 'axis-pv', dataKey: 'pv', type: AxisDomainType.number, tickCount: 3),
          const PolarRadiusAxis(radiusAxisId: 'axis-name', dataKey: 'name', type: AxisDomainType.category),
          const PolarRadiusAxis(radiusAxisId: 'axis-amt', dataKey: 'amt', type: AxisDomainType.number, angle: 180),
          grid,
        ];

    test('angleAxisId undefined (0) renders nothing', () {
      final m = model(chart(const PolarGrid()), 300);
      final g = polarGridGeometry(m.scene!, m.scene!.grids.single);
      // No lines, no polygons, no circles: the default angle axis has no ticks, so PolarGrid returns null.
      expect(g, isNull);
    });

    test('axis-pv: lines point to the ticks [0, 180, 360]', () {
      final m = model(chart(const PolarGrid(angleAxisId: 'axis-pv')), 300);
      final ticks = m.scene!.angleAxes['axis-pv']!.ticks!;
      expect([for (final t in ticks) t.coordinate], [0, 180, 360]);
      expect([for (final t in ticks) t.value], [0, 600, 1200]);
      expect({for (final t in ticks) t.offset}, {0.0});
      final g = polarGridGeometry(m.scene!, m.scene!.grids.single)!;
      expect(g.angles, [0, 180, 360]);
      expect([for (final (_, b) in g.lines) b.dx], [near(266), near(34), near(266)]);
      expect(g.lines.first.$2.dy, 150);
    });

    test('axis-uv: domain [0, 1520] over 0..360 with ticks every 200', () {
      final m = model(chart(const PolarGrid(angleAxisId: 'axis-uv')), 300);
      final axis = m.scene!.angleAxes['axis-uv']!;
      expect(axis.niceTicks, isNull);
      expect(axis.scale!.domain, [0, 1520]);
      expect([for (final t in axis.ticks!) t.value], [0, 200, 400, 600, 800, 1000, 1200, 1400]);
      expect([for (final t in axis.ticks!) t.coordinate], [
        0,
        near(47.368421052631575),
        near(94.73684210526315),
        near(142.10526315789474),
        near(189.4736842105263),
        near(236.84210526315792),
        near(284.2105263157895),
        near(331.57894736842104),
      ]);
    });

    test('radiusAxisId undefined: the default radius axis is the 7 categories', () {
      final m = model(chart(const PolarGrid(angleAxisId: 'axis-pv')), 300);
      final g = polarGridGeometry(m.scene!, m.scene!.grids.single)!;
      const expected = [8.285714285714286, 24.857142857142858, 41.42857142857143, 58.0, 74.57142857142857, 91.14285714285714, 107.71428571428571];
      expect(g.radii.length, 7);
      for (final (i, r) in g.radii.indexed) {
        expect(r, closeTo(expected[i], 1e-6));
      }
      // 'M 158.28571428571428,150L 141.71428571428572,150L 158.28571428571428,150Z'
      final p = points('M 158.28571428571428,150L 141.71428571428572,150L 158.28571428571428,150Z');
      for (final (i, a) in g.angles.indexed) {
        final e = polarToCartesian(150, 150, g.radii[0], a);
        expect(e.dx, near(p[i].dx));
      }
    });

    test('radiusAxisId axis-name: scale, ticks and radii', () {
      final m = model(chart(const PolarGrid(angleAxisId: 'axis-pv', radiusAxisId: 'axis-name')), 300);
      final axis = m.scene!.radiusAxes['axis-name']!;
      expect(axis.niceTicks, isNull);
      expect(axis.scale!.domain, ['Page A', 'Page B', 'Page C', 'Page D', 'Page E', 'Page F', 'Page G']);
      expect(axis.scale!.range, [0, 116]);
      const coords = [8.28571428571428, 24.857142857142854, 41.42857142857142, 58.0, 74.57142857142857, 91.14285714285715, 107.71428571428574];
      expect([for (final t in axis.ticks!) t.coordinate], [for (final c in coords) closeTo(c, 1e-9)]);
      expect({for (final t in axis.ticks!) t.offset}.single, closeTo(8.285714285714286, 1e-12));
      final g = polarGridGeometry(m.scene!, m.scene!.grids.single)!;
      expect(g.radii, [for (final c in coords) closeTo(c, 1e-9)]);
    });
  });
}
