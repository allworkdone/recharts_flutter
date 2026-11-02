// Polar axes, grid, Radar and RadialBar, with the expectations of Recharts
// 3.10.1 test/polar/PolarGrid.spec.tsx, PolarAngleAxis/PolarAngleAxis.spec.tsx,
// PolarRadiusAxis.spec.tsx, Radar.animation.spec.tsx, RadialBar/RadialBar.spec.tsx
// and the polar cases of component/Tooltip/Tooltip.payload.spec.tsx. Their
// jsdom layout measures every string as 0x0; none of these numbers depend on text.

import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/recharts_flutter.dart';
import 'package:recharts_flutter/src/core/polar_utils.dart';
import 'package:recharts_flutter/src/engine/pie.dart';
import 'package:recharts_flutter/src/engine/polar_axis.dart';
import 'package:recharts_flutter/src/render/polar_painter.dart' show getAttrsOfPolarLabel;
import 'package:recharts_flutter/src/render/polar_scene_painter.dart';

// test/_data.ts
const exampleRadarData = [
  {'name': 'iPhone 3GS', 'value': 420, 'half': 210},
  {'name': 'iPhone 4', 'value': 460, 'half': 230},
  {'name': 'iPhone 4s', 'value': 999, 'half': 500},
  {'name': 'iPhone 5', 'value': 500, 'half': 250},
  {'name': 'iPhone 5s', 'value': 864, 'half': 432},
  {'name': 'iPhone 6', 'value': 650, 'half': 325},
  {'name': 'iPhone 6s', 'value': 765, 'half': 383},
  {'name': 'iPhone 5se', 'value': 365, 'half': 183},
];
const pageData = [
  {'name': 'Page A', 'uv': 400, 'pv': 2400, 'amt': 2400},
  {'name': 'Page B', 'uv': 300, 'pv': 4567, 'amt': 2400},
  {'name': 'Page C', 'uv': 300, 'pv': 1398, 'amt': 2400},
  {'name': 'Page D', 'uv': 200, 'pv': 9800, 'amt': 2400},
  {'name': 'Page E', 'uv': 278, 'pv': 3908, 'amt': 2400},
  {'name': 'Page F', 'uv': 189, 'pv': 4800, 'amt': 2400},
];

PolarModel radarModel(List<Object?> data, List<RechartsElement> children,
    {Size size = const Size(500, 500), Object cx = '50%', Object cy = '50%', Object outerRadius = '80%'}) =>
    computePolarModel(
      chartName: 'RadarChart',
      size: size,
      data: data,
      children: children,
      layout: PolarLayout.centric,
      options: PolarOptions(cx: cx, cy: cy, outerRadius: outerRadius, startAngle: 90, endAngle: -270),
    );

Matcher near(double v) => closeTo(v, 1e-9);

void main() {
  group('PolarGrid and axes in a RadarChart (exampleRadarData, 500x500)', () {
    final m = radarModel(exampleRadarData, const [
      Radar(dataKey: 'value'),
      PolarRadiusAxis(dataKey: 'value', orientation: PolarRadiusOrientation.middle, label: 'test'),
      PolarAngleAxis(dataKey: 'value'),
      PolarGrid(),
    ]);
    final scene = m.scene!;

    test('the angle axis ticks are the data, spaced around the circle (PolarAngleAxis.spec "should select ticks")', () {
      final ticks = scene.angleAxes[0]!.ticks!;
      expect([for (final t in ticks) t.coordinate], [90, 45, 0, -45, -90, -135, -180, -225]);
      expect([for (final t in ticks) t.value], [420, 460, 999, 500, 864, 650, 765, 365]);
      expect({for (final t in ticks) t.offset}, {45.0});
      expect(scene.angleAxes[0]!.realScaleType, 'band');
    });

    test('the radius axis has nice ticks over [0, 1000] and the radii of PolarGrid (PolarRadiusAxis.spec)', () {
      final axis = scene.radiusAxes[0]!;
      expect(axis.domain, [0, 999]);
      expect(axis.domainWithNiceTicks, [0, 1000]);
      expect(axis.realScaleType, 'linear');
      expect(axis.rangeWithReverse, [0, 196]);
      expect([for (final t in axis.ticks!) t.value], [0, 250, 500, 750, 1000]);
      expect([for (final t in axis.ticks!) t.coordinate], [0, 49, 98, 147, 196]);
    });

    test('grid lines end on the outer radius (PolarGrid.spec "as a child of RadarChart")', () {
      final vb = scene.viewBox;
      expect([vb.cx, vb.cy, vb.innerRadius, vb.outerRadius], [250, 250, 0, 196]);
      final ends = [for (final t in scene.angleAxes[0]!.ticks!) polarToCartesian(vb.cx, vb.cy, vb.outerRadius, t.coordinate)];
      expect(ends[0], const Offset(250, 54));
      expect(ends[1].dx, near(388.5929291125633));
      expect(ends[1].dy, near(111.4070708874367));
      expect(ends[2], const Offset(446, 250));
      expect(ends[4].dy, near(446));
      expect(ends[6].dx, near(54));
    });

    test('tick lines run 8 further out; text anchors follow the tick angle (PolarAngleAxis.spec "should render axis ticks")', () {
      final g = angleAxisTickGeometry(scene, const PolarAngleAxis(dataKey: 'value'));
      expect(g.length, 8);
      expect(g[0].p1, const Offset(250, 54));
      expect(g[0].p2, const Offset(250, 46));
      expect(g[1].p1.dx, near(388.5929291125633));
      expect(g[1].p2.dx, near(394.2497833620557));
      expect(g[1].p2.dy, near(105.7502166379443));
      expect(g[2].p2, const Offset(454, 250));
      expect(g[4].p2, const Offset(250, 454));
      expect(g[6].p2.dx, near(46));
      // getTickTextAnchor / getTickTextVerticalAnchor
      expect(g[2].textAnchor, TextAnchor.start);
      expect(g[6].textAnchor, TextAnchor.end);
      expect(g[0].textAnchor, TextAnchor.middle);
      // The top tick's text sits above its point (baseline at the end), the bottom tick's below.
      expect(g[0].verticalAnchor, TextVerticalAnchor.end);
      expect(g[4].verticalAnchor, TextVerticalAnchor.start);
      expect(g[2].verticalAnchor, TextVerticalAnchor.middle);
    });

    test('orientation inner draws ticks inward and flips the anchors', () {
      final g = angleAxisTickGeometry(scene, const PolarAngleAxis(dataKey: 'value', orientation: PolarAngleOrientation.inner));
      expect(g[2].p2, const Offset(438, 250));
      expect(g[2].textAnchor, TextAnchor.end);
      expect(g[6].textAnchor, TextAnchor.start);
    });

    test('radius ticks sit on the axis angle; the label goes in the middle of the ticks (PolarRadiusAxis.spec)', () {
      final ticks = radiusAxisTickPositions(scene, const PolarRadiusAxis(dataKey: 'value'));
      expect([for (final (_, p) in ticks) p.dx], [250, 299, 348, 397, 446]);
      expect({for (final (_, p) in ticks) p.dy}, {250.0});
      const viewBox = PolarViewBox(cx: 250, cy: 250, innerRadius: 0, outerRadius: 196, startAngle: 0, endAngle: 0);
      final label = getAttrsOfPolarLabel(viewBox, 5, LabelPosition.middle)!;
      expect([label.x, label.y], [348, 250]);
    });
  });
}
