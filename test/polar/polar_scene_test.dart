// Polar axes, grid, Radar and RadialBar, with the expectations of Recharts
// 3.10.1 test/polar/PolarGrid.spec.tsx, PolarAngleAxis/PolarAngleAxis.spec.tsx,
// PolarRadiusAxis.spec.tsx, Radar.animation.spec.tsx, RadialBar/RadialBar.spec.tsx
// and the polar cases of component/Tooltip/Tooltip.payload.spec.tsx. Their
// jsdom layout measures every string as 0x0; none of these numbers depend on text.

import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/recharts_flutter.dart';
import 'package:recharts_flutter/src/animation.dart';
import 'package:recharts_flutter/src/core/polar_utils.dart';
import 'package:recharts_flutter/src/engine/pie.dart';
import 'package:recharts_flutter/src/engine/polar_axis.dart';
import 'package:recharts_flutter/src/engine/polar_items.dart';
import 'package:recharts_flutter/src/engine/polar_scene.dart';
import 'package:recharts_flutter/src/render/polar_painter.dart' show getAttrsOfPolarLabel;
import 'package:recharts_flutter/src/render/polar_scene_painter.dart';
import 'package:recharts_flutter/src/render/sector.dart' show sectorPathData;
import 'package:recharts_flutter/src/util.dart';

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

PolarModel radialBarModel(List<Object?> data, List<RechartsElement> children, {Size size = const Size(500, 500)}) =>
    computePolarModel(
      chartName: 'RadialBarChart',
      size: size,
      data: data,
      children: children,
      layout: PolarLayout.radial,
      options: const PolarOptions(startAngle: 0, endAngle: 360),
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

  group('Radar (Radar.animation.spec: 100x100, cx 50, cy 50, outerRadius 40, PageData.slice(0, 3))', () {
    PolarModel model(String dataKey) => radarModel(pageData.sublist(0, 3), [
          const PolarGrid(),
          const PolarAngleAxis(dataKey: 'name'),
          const PolarRadiusAxis(),
          Radar(dataKey: dataKey, dot: true),
        ], size: const Size(100, 100), cx: 50, cy: 50, outerRadius: 40);

    test('points without animation', () {
      final points = model('pv').scene!.radars.single.points!;
      expect([for (final p in points) p.x], [near(50), near(76.36758679389021), near(41.92864323672903)]);
      expect([for (final p in points) p.y], [near(34), near(65.22333333333333), near(54.66)]);
      expect([for (final p in points) p.radius.toStringAsFixed(2)], ['16.00', '30.45', '9.32']);
    });

    test('points grow from the center with the ease curve', () {
      final points = model('amt').scene!.radars.single.points!;
      final items = matchAnimationItems<RadarPoint>(null, points, MatchBy.byIndex);
      final ease = createEasingFunction('ease')!;
      // expectAnimatedRadarDots: progress 0.1 + 0.18 * n
      const expected = [
        [(50.0, 31.0857), (66.3803, 59.4572), (33.6197, 59.4572)],
        [(50.0, 19.6171), (76.3123, 65.1914), (23.6877, 65.1914)],
        [(50.0, 13.5884), (81.5333, 68.2058), (18.4667, 68.2058)],
        [(50.0, 10.7784), (83.9669, 69.6108), (16.0331, 69.6108)],
      ];
      for (final (i, progress) in [0.28, 0.46, 0.64, 0.82].indexed) {
        final step = interpolateRadarPoints(items, ease(round4(progress)));
        expect([for (final p in step) (round4(p.x), round4(p.y))], expected[i], reason: 'progress $progress');
      }
      final done = interpolateRadarPoints(items, 1);
      expect(done[0].y, near(10));
      expect(done[1].x, near(84.64101615137756));
      expect(done[2].x, near(15.35898384862245));
    });
  });

  // Radar.spec.tsx 'in a chart rotating ...'
  for (final (direction, startAngle, endAngle, angles, polygon) in [
    (
      'clockwise',
      90.0,
      -270.0,
      [90, 45, 0, -45, -90, -135, -180, -225],
      'M250,167.68L313.7527,186.2473L445.804,250L319.2965,319.2965L250,419.344L159.9146,340.0854L100.06,250L199.4136,199.4136',
    ),
    (
      'counter-clockwise',
      -270.0,
      90.0,
      [-315, -270, -225, -180, -135, -90, -45, 0],
      'M308.209,191.791L250,159.84L111.5457,111.5457L152,250L130.2557,369.7443L250,377.4L356.0236,356.0236L321.54,250',
    ),
  ]) {
    group('Radar in a chart rotating $direction', () {
      final m = computePolarModel(
        chartName: 'RadarChart',
        size: const Size(500, 500),
        data: exampleRadarData,
        children: const [PolarAngleAxis(dataKey: 'name'), Radar(dataKey: 'value')],
        layout: PolarLayout.centric,
        options: PolarOptions(startAngle: startAngle, endAngle: endAngle),
      );
      final expected = [for (final (i, e) in exampleRadarData.indexed) (e['name'], angles[i])];

      test('every point sits on the angle axis tick of its category', () {
        expect([for (final t in m.scene!.angleAxes[0]!.ticks!) (t.value, t.coordinate)], expected);
        expect([for (final p in m.scene!.radars.single.points!) (p.name, p.angle)], expected);
      });

      test('the polygon', () {
        final d = [
          for (final (i, p) in m.scene!.radars.single.points!.indexed) '${i == 0 ? 'M' : 'L'}${jsString(round4(p.x))},${jsString(round4(p.y))}',
        ].join();
        expect(d, polygon);
      });
    });
  }

  group('Radar null values (Radar.spec: 400x400, PolarRadiusAxis domain [0, 100])', () {
    const data = [
      {'subject': 'Math', 'score': 80, 'range': [20, 80]},
      {'subject': 'Physics', 'score': 60, 'range': [30, 60]},
      {'subject': 'History', 'score': null, 'range': [null, 50]},
      {'subject': 'Art', 'score': 70, 'range': [40, 70]},
    ];
    RadarComposed composed(String dataKey) => computePolarModel(
          chartName: 'RadarChart',
          size: const Size(400, 400),
          data: data,
          children: [
            const PolarAngleAxis(dataKey: 'subject'),
            const PolarRadiusAxis(domain: [0, 100]),
            Radar(dataKey: dataKey),
          ],
          layout: PolarLayout.centric,
          options: const PolarOptions(startAngle: 90, endAngle: -270),
        ).scene!.radars.single.composed!;
    List<(double, double)?> xy(List<RadarPoint> points) =>
        [for (final p in points) p.x.isNaN && p.y.isNaN ? null : (round4(p.x), round4(p.y))];

    test('a null value has no position instead of sitting at the center', () {
      // 'M200,75.2L293.6,200M90.8,200L200,75.2'
      expect(xy(composed('score').points), [(200, 75.2), (293.6, 200), null, (90.8, 200)]);
    });

    test('a null low value of a range leaves a gap in the base line', () {
      // 'M200,75.2L293.6,200L200,278L90.8,200L200,75.2L137.6,200M246.8,200L200,168.8L137.6,200'
      final c = composed('range');
      expect(xy(c.points), [(200, 75.2), (293.6, 200), (200, 278), (90.8, 200)]);
      expect(xy(c.baseLinePoints), [(200, 168.8), (246.8, 200), null, (137.6, 200)]);
    });
  });

  group('RadialBar with implicit axes (RadialBar.spec, 500x500, PageData, dataKey pv)', () {
    final m = radialBarModel(pageData, const [RadialBar(dataKey: 'pv', isAnimationActive: false)]);
    final scene = m.scene!;

    test('radius axis ticks are the categories, with a half band offset', () {
      final ticks = scene.radiusAxes[0]!.ticks!;
      expect([for (final t in ticks) t.coordinate], [
        near(16.333333333333332),
        near(49),
        near(81.66666666666666),
        near(114.33333333333333),
        near(147),
        near(179.66666666666666),
      ]);
      expect({for (final t in ticks) t.offset}, {16.333333333333332});
      expect([for (final t in ticks) t.value], [0, 1, 2, 3, 4, 5]);
      expect(scene.radiusAxes[0]!.scale!.bandwidth, 32.666666666666664);
    });

    test('sectors and their backgrounds', () {
      final sectors = scene.radialBars.single.sectors;
      const expected = [
        (3.266666666666666, 29.266666666666666, 88.16326530612244),
        (35.93333333333333, 61.93333333333333, 167.76734693877552),
        (68.6, 94.6, 51.35510204081632),
        (101.26666666666667, 127.26666666666667, 360.0),
        (133.93333333333334, 159.93333333333334, 143.5591836734694),
        (166.6, 192.6, 176.32653061224488),
      ];
      expect(sectors.length, 6);
      for (final (i, s) in sectors.indexed) {
        expect(s.innerRadius, near(expected[i].$1));
        expect(s.outerRadius, near(expected[i].$2));
        expect(s.endAngle, near(expected[i].$3));
        expect([s.cx, s.cy, s.startAngle], [250, 250, 0]);
        expect(s.value, pageData[i]['pv']);
        final bg = s.background!;
        expect([bg.cx, bg.cy, bg.startAngle, bg.endAngle], [250, 250, 0, 360]);
        expect(bg.innerRadius, near(expected[i].$1));
        expect(bg.outerRadius, near(expected[i].$2));
      }
    });
  });

  group('axis tooltip (Tooltip.payload.spec: 600x600, PageData, hover at 200,200)', () {
    test('RadarChart: the pointer maps to the nearest spoke; the label is the tick value', () {
      final children = <RechartsElement>[
        const Radar(dataKey: 'uv'),
        const Radar(dataKey: 'pv', name: 'My custom name'),
        const Radar(dataKey: 'amt'),
      ];
      final m = radarModel(pageData, children, size: const Size(600, 600));
      final props = polarActivePropsFromPointer(m.scene!, const Offset(200, 200))!;
      expect(props.activeIndex, 5);
      expect(polarActiveLabel(m.scene!, 5), 5);
      final payload = polarTooltipPayload(m.scene!, pageData, 5);
      expect([for (final e in payload) '${e.name} : ${e.value}'], ['uv : 189', 'My custom name : 4800', 'amt : 2400']);

      final withAxis = radarModel(pageData, [...children, const PolarAngleAxis(dataKey: 'name')], size: const Size(600, 600));
      final p2 = polarActivePropsFromPointer(withAxis.scene!, const Offset(200, 200))!;
      expect(polarActiveLabel(withAxis.scene!, p2.activeIndex), 'Page F');
      expect(p2.coordinate.angle, near(-210));
    });

    test('RadarChart: outside the polar view box there is no active index', () {
      final m = radarModel(pageData, [const Radar(dataKey: 'uv')], size: const Size(600, 600));
      expect(polarActivePropsFromPointer(m.scene!, const Offset(5, 5)), isNull);
      expect(polarActivePropsFromPointer(m.scene!, const Offset(300, 300)), isNull);
    });

    test('RadialBarChart: the pointer radius picks the category; the label is its index', () {
      final m = radialBarModel(pageData, const [
        RadialBar(dataKey: 'uv'),
        RadialBar(dataKey: 'pv', name: 'My custom name'),
        RadialBar(dataKey: 'amt'),
      ], size: const Size(600, 600));
      final props = polarActivePropsFromPointer(m.scene!, const Offset(200, 200))!;
      expect(props.activeIndex, 3);
      expect(polarActiveLabel(m.scene!, 3), 3);
      final payload = polarTooltipPayload(m.scene!, pageData, 3);
      expect([for (final e in payload) '${e.name} : ${e.value}'], ['uv : 200', 'My custom name : 9800', 'amt : 2400']);
    });
  });

  group('RadialBar sector paths (RadialBar.animation.spec: 400x400, pageDataWithFillColor.slice(0, 2), dataKey uv)', () {
    const data = [
      {'name': '18-24', 'uv': 31.47, 'pv': 2400, 'amt': 1400},
      {'name': '25-29', 'uv': 26.69, 'pv': 4567, 'amt': 720},
    ];
    final model = radialBarModel(data, const [RadialBar(dataKey: 'uv')], size: const Size(400, 400));
    final bar = model.scene!.radialBars.single;

    List<String?> paths(List<RadialBarSector> sectors) =>
        [for (final s in sectors) sectorPathData(radialBarGeometry(bar.settings, s))];

    test('without animation', () {
      expect(paths(bar.sectors), [
        'M 269.8,200 A 69.8,69.8,0, 1,0, 269.8,200.0012 L 207.8,200.0001 A 7.8,7.8,0, 1,1, 207.8,200 Z',
        'M 347.8,200 A 147.8,147.8,0, 1,0, 285.4481,320.5963 L 249.6038,270.0079 A 85.8,85.8,0, 1,1, 285.8,200 Z',
      ]);
    });

    test('entrance sweep: new sectors grow from their start angle', () {
      final items = matchAnimationItems<RadialBarSector>(null, bar.sectors, MatchBy.append);
      final ease = createEasingFunction('ease')!;
      const expected = [
        [
          'M 269.8,200 A 69.8,69.8,0, 0,0, 131.2126,188.154 L 192.3132,198.6762 A 7.8,7.8,0, 0,1, 207.8,200 Z',
          'M 347.8,200 A 147.8,147.8,0, 0,0, 79.8649,113.9048 L 130.2598,150.0205 A 85.8,85.8,0, 0,1, 285.8,200 Z',
        ],
        [
          'M 269.8,200 A 69.8,69.8,0, 1,0, 204.1953,269.6738 L 200.4688,207.7859 A 7.8,7.8,0, 1,1, 207.8,200 Z',
          'M 347.8,200 A 147.8,147.8,0, 1,0, 108.8263,316.3279 L 147.0723,267.53 A 85.8,85.8,0, 1,1, 285.8,200 Z',
        ],
        [
          'M 269.8,200 A 69.8,69.8,0, 1,0, 259.0019,237.2936 L 206.5933,204.1675 A 7.8,7.8,0, 1,1, 207.8,200 Z',
          'M 347.8,200 A 147.8,147.8,0, 1,0, 220.3881,346.387 L 211.8356,284.9798 A 85.8,85.8,0, 1,1, 285.8,200 Z',
        ],
        [
          'M 269.8,200 A 69.8,69.8,0, 1,0, 269.2789,208.5131 L 207.7418,200.9513 A 7.8,7.8,0, 1,1, 207.8,200 Z',
          'M 347.8,200 A 147.8,147.8,0, 1,0, 272.5059,328.7934 L 242.0907,274.7664 A 85.8,85.8,0, 1,1, 285.8,200 Z',
        ],
      ];
      for (final (i, progress) in [0.28, 0.46, 0.64, 0.82].indexed) {
        expect(paths(interpolateRadialBarSectors(items, ease(round4(progress)))), expected[i], reason: 'progress $progress');
      }
      expect(paths(interpolateRadialBarSectors(items, 1)), paths(bar.sectors));
    });
  });

  group('RadialBar data entry colors in the Legend and Tooltip (RadialBar.theme.spec, no theme)', () {
    const gold = Color(0xFFFFD700), lime = Color(0xFF00FF00), c123456 = Color(0xFF123456);
    List<Color?> legend(List<Object?> data, RadialBar bar) => [
          for (final p in radialBarLegendPayload(radialBarModel(data, [bar]).scene!.radialBars.single.settings, data))
            p.color,
        ];
    Color? tooltipColor(List<Object?> data, RadialBar bar) =>
        polarTooltipPayload(radialBarModel(data, [bar]).scene!, data, 0).single.color;

    test('the Legend shows the Cell fill, then the RadialBar fill', () {
      expect(
          legend(const [
            {'name': 'A', 'value': 1},
            {'name': 'B', 'value': 2},
          ], const RadialBar(dataKey: 'value', fill: gold, children: [Cell(fill: c123456)])),
          [c123456, gold]);
    });

    test('the Legend shows the RadialBar fill when the entry only has a stroke', () {
      expect(legend(const [{'name': 'A', 'value': 1, 'stroke': 'lime'}], const RadialBar(dataKey: 'value', fill: c123456)),
          [c123456]);
    });

    test('the Legend shows each sector color: entry fill, else entry stroke', () {
      expect(
          legend(const [
            {'name': 'A', 'value': 1, 'fill': 'gold'},
            {'name': 'B', 'value': 2, 'stroke': 'lime'},
            {'name': 'C', 'value': 3},
          ], const RadialBar(dataKey: 'value')),
          [gold, lime, null]);
    });

    test('the Tooltip shows the RadialBar fill when the entry only has a stroke', () {
      expect(tooltipColor(const [{'name': 'A', 'value': 1, 'stroke': 'lime'}], const RadialBar(dataKey: 'value', fill: c123456)),
          c123456);
    });

    test('the Tooltip shows the Cell fill', () {
      expect(
          tooltipColor(const [{'name': 'A', 'value': 1}],
              const RadialBar(dataKey: 'value', fill: gold, children: [Cell(fill: c123456)])),
          c123456);
    });

    test('the Tooltip shows the entry fill over the RadialBar fill', () {
      expect(tooltipColor(const [{'name': 'A', 'value': 1, 'fill': 'gold'}], const RadialBar(dataKey: 'value', fill: c123456)),
          gold);
    });
  });

  group('RadialBar minAngle (RadialBar.spec: 500x500)', () {
    const data = [
      {'name': 'A', 'pv': 100},
      {'name': 'B', 'pv': 5},
      {'name': 'C', 'pv': 0},
    ];
    List<(double, double)> anglesOf(RadialBarModel b) => [for (final s in b.sectors) (s.startAngle, s.endAngle)];

    for (final minAngle in [30.0, -30.0]) {
      test('minAngle $minAngle widens a small bar, leaves a zero bar at 0 and a large one alone', () {
        final m = radialBarModel(data, [RadialBar(dataKey: 'pv', minAngle: minAngle)]);
        expect(anglesOf(m.scene!.radialBars.single), [(0, 360), (0, 30), (0, 0)]);
      });
    }

    test('can overlap stacked bars, like minPointSize', () {
      final m = radialBarModel(const [
        {'name': 'A', 'a': 1, 'b': 99},
      ], const [
        RadialBar(dataKey: 'a', stackId: 's', minAngle: 30),
        RadialBar(dataKey: 'b', stackId: 's', minAngle: 30),
      ]);
      final [a, b] = m.scene!.radialBars;
      expect(anglesOf(a), [(0, 30)]);
      expect(b.sectors.single.startAngle, closeTo(360 / 99, 1e-5));
      expect(b.sectors.single.endAngle, 360);
    });
  });

  group('RadialBar with a null value (RadialBar.spec: 400x400, innerRadius 20, outerRadius 180)', () {
    const dataWithNull = [
      {'name': 'A', 'value': 50},
      {'name': 'Missing', 'value': null},
      {'name': 'B', 'value': 25},
    ];
    RadialBarModel bar(double minPointSize) => computePolarModel(
          chartName: 'RadialBarChart',
          size: const Size(400, 400),
          data: dataWithNull,
          children: [
            const PolarAngleAxis(type: AxisDomainType.number, domain: [0, 100]),
            RadialBar(dataKey: 'value', minPointSize: minPointSize),
          ],
          layout: PolarLayout.radial,
          options: const PolarOptions(innerRadius: 20, outerRadius: 180, startAngle: 0, endAngle: 360),
        ).scene!.radialBars.single;

    for (final minPointSize in [0.0, 5.0]) {
      test('an empty sector for a null value with minPointSize $minPointSize', () {
        expect([for (final s in bar(minPointSize).sectors) (s.startAngle, s.endAngle)], [(0, 180), (0, 0), (0, 90)]);
      });
    }

    test('no sector is drawn for the null value', () {
      final b = bar(0);
      expect([for (final s in b.sectors) radialBarPath(b.settings, s, null)].nonNulls, hasLength(2));
    });
  });

  group('Brush range synced from another chart', () {
    test('RadialBar sectors and the tooltip data follow it; Radar points and axes ignore it', () {
      final children = <RechartsElement>[
        const RadialBar(dataKey: 'pv'),
        const Radar(dataKey: 'pv'),
      ];
      final m = computePolarModel(
        chartName: 'RadialBarChart',
        size: const Size(500, 500),
        data: pageData,
        children: children,
        layout: PolarLayout.radial,
        options: const PolarOptions(startAngle: 0, endAngle: 360),
        dataStartIndex: 1,
        dataEndIndex: 3,
      );
      final scene = m.scene!;
      expect(scene.radialBars.single.sectors.length, 3);
      expect(scene.radialBars.single.sectors.first.value, 4567);
      expect(scene.radars.single.points!.length, 6);
      expect(scene.radiusAxes[0]!.ticks!.length, 6);
    });
  });
}
