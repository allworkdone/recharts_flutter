// Radar and RadialBar behaviors of Recharts 3.10.1: RadialBar.spec.tsx (configured
// axes, RingsWithTypes, mouse handlers), RadialBarChart.spec.tsx (activeShape,
// background path), RadarChart.spec.tsx (dots, labels, onClick), Radar.spec.tsx
// (polygon events) and Tooltip.visibility.spec.tsx (tooltip position). Values are
// the specs' literals.


import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/recharts_flutter.dart';
import 'package:recharts_flutter/src/core/polar_utils.dart';
import 'package:recharts_flutter/src/engine/pie.dart';
import 'package:recharts_flutter/src/engine/polar_axis.dart';
import 'package:recharts_flutter/src/engine/polar_items.dart';
import 'package:recharts_flutter/src/render/polar_scene_painter.dart';
import 'package:recharts_flutter/src/render/sector.dart';

import '../widgets/chart_widget_test.dart' show capture, host, pixel, tooltipBox;
import '../widgets/tooltip_item_test.dart' show Probe, mouseAt;
import 'polar_scene_test.dart' show exampleRadarData, pageData;

Matcher near(num v) => closeTo(v, 1e-9);

PolarModel radialBarModel(List<Object?> data, List<RechartsElement> children, {Size size = const Size(500, 500)}) =>
    computePolarModel(
      chartName: 'RadialBarChart',
      size: size,
      data: data,
      children: children,
      layout: PolarLayout.radial,
      options: const PolarOptions(startAngle: 0, endAngle: 360),
    );

void main() {
  group('RadialBar with configured axes (RadialBar.spec "with configured axes")', () {
    final scene = radialBarModel(pageData, const [
      PolarAngleAxis(dataKey: 'pv', type: AxisDomainType.number, axisLineType: PolarAxisLineType.circle),
      PolarRadiusAxis(dataKey: 'name', orientation: PolarRadiusOrientation.middle, type: AxisDomainType.category, angle: 90),
      RadialBar(isAnimationActive: false, dataKey: 'pv'),
    ]).scene!;

    test('radius axis ticks carry the page names', () {
      final ticks = scene.radiusAxes[0]!.ticks!;
      expect([for (final t in ticks) t.value], ['Page A', 'Page B', 'Page C', 'Page D', 'Page E', 'Page F']);
      expect([for (final t in ticks) t.coordinate], [
        near(16.333333333333332),
        near(49),
        near(81.66666666666666),
        near(114.33333333333333),
        near(147),
        near(179.66666666666666),
      ]);
    });

    test('sectors match the implicit-axes case', () {
      final s = scene.radialBars.single.sectors;
      expect(s[0].innerRadius, near(3.266666666666666));
      expect(s[0].outerRadius, near(29.266666666666666));
      expect(s[0].endAngle, near(88.16326530612244));
      expect(s[1].endAngle, near(167.76734693877552));
      expect(s[2].endAngle, near(51.35510204081632));
      expect(s[0].props['name'], 'Page A');
      expect(s[0].props['uv'], 400);
    });
  });

  group('RingsWithTypes (RadialBar.spec): ringsData, number angle axis, category radius axis', () {
    const rings = [
      {'name': 'Elves', 'rings': 3, 'fill': Color(0xFF008000)},
      {'name': 'Dwarves', 'rings': 7, 'fill': Color(0xFF0000FF)},
      {'name': 'Humans', 'rings': 9, 'fill': Color(0xFFFF0000)},
      {'name': 'Sauron', 'rings': 1, 'fill': Color(0xFF000000)},
    ];
    final scene = radialBarModel(rings, const [
      RadialBar(isAnimationActive: false, dataKey: 'rings'),
      PolarGrid(gridType: PolarGridType.circle),
      PolarAngleAxis(type: AxisDomainType.number),
      PolarRadiusAxis(type: AxisDomainType.category, stroke: Color(0xFF000000)),
    ]).scene!;

    test('scales and ticks', () {
      final angle = scene.angleAxes[0]!, radius = scene.radiusAxes[0]!;
      expect(angle.realScaleType, 'linear');
      expect(angle.scale!.domain, [0, 9]);
      expect(angle.scale!.range, [0, 360]);
      expect(radius.realScaleType, 'band');
      expect(radius.scale!.domain, [0, 1, 2, 3]);
      expect(radius.scale!.bandwidth, 49);
      expect([for (final t in radius.ticks!) t.coordinate], [24.5, 73.5, 122.5, 171.5]);
      expect([for (final t in radius.itemTicks!) t.coordinate], [0, 49, 98, 147]);
      expect({for (final t in radius.itemTicks!) t.offset}, {0.0});
    });

    test('sectors and backgrounds', () {
      const expected = [
        (4.9, 43.9, 120.0),
        (53.9, 92.9, 280.0),
        (102.9, 141.9, 360.0),
        (151.9, 190.9, 40.0),
      ];
      final sectors = scene.radialBars.single.sectors;
      expect(sectors.length, 4);
      for (final (i, s) in sectors.indexed) {
        expect(s.innerRadius, near(expected[i].$1));
        expect(s.outerRadius, near(expected[i].$2));
        expect(s.endAngle, near(expected[i].$3));
        expect(s.startAngle, 0);
        expect(s.value, rings[i]['rings']);
        expect(s.fill, rings[i]['fill']);
        expect([s.background!.innerRadius, s.background!.outerRadius, s.background!.endAngle],
            [near(expected[i].$1), near(expected[i].$2), 360]);
      }
    });
  });

  group('RadialBarChart.spec: background and activeShape', () {
    test('the background sector is drawn exactly where the foreground is (startAngle 180, endAngle 0, cx 47%)', () {
      final m = computePolarModel(
        chartName: 'RadialBarChart',
        size: const Size(340, 280),
        data: const [{'value': 42, 'fill': Color(0xFF241084)}],
        children: const [RadialBar(background: SectorStyle(fill: Color(0xFFD8BDF3)), dataKey: 'value', isAnimationActive: false)],
        layout: PolarLayout.radial,
        options: const PolarOptions(cx: '47%', startAngle: 180, endAngle: 0),
      );
      final bar = m.scene!.radialBars.single;
      final fg = sectorPathData(radialBarGeometry(bar.settings, bar.sectors.single));
      final bg = sectorPathData(bar.sectors.single.background!);
      expect(fg, isNotNull);
      expect(bg, fg);
    });

    // 500x300, cx 150, cy 150, innerRadius 20, outerRadius 140, barSize 10.
    const data = [
      {'name': '18-24', 'uv': 31.47, 'pv': 2400, 'fill': Color(0xFF8884D8)},
      {'name': '25-29', 'uv': 26.69, 'pv': 4567, 'fill': Color(0xFF83A6ED)},
      {'name': '30-34', 'uv': 15.69, 'pv': 1398, 'fill': Color(0xFF8DD1E1)},
      {'name': '35-39', 'uv': 8.22, 'pv': 9800, 'fill': Color(0xFF82CA9D)},
    ];

    /// A point inside the bar at [index], around angle 45 degrees.
    Offset onBar(int index, [double dr = 0]) {
      final m = computePolarModel(
        chartName: 'RadialBarChart',
        size: const Size(500, 300),
        data: data,
        children: const [RadialBar(dataKey: 'uv', barSize: 10)],
        layout: PolarLayout.radial,
        options: const PolarOptions(cx: 150, cy: 150, innerRadius: 20, outerRadius: 140, startAngle: 0, endAngle: 360),
        barSize: 10,
      );
      final s = m.scene!.radialBars.single.sectors[index];
      return polarToOffset(150, 150, (s.innerRadius + s.outerRadius) / 2 + dr, 45);
    }

    Widget chart(Object? activeShape) => host(RadialBarChart(
            width: 500,
            height: 300,
            cx: 150,
            cy: 150,
            innerRadius: 20,
            outerRadius: 140,
            barSize: 10,
            data: data,
            children: [
              RadialBar(background: true, dataKey: 'uv', isAnimationActive: false, activeShape: activeShape),
              Tooltip(isAnimationActive: false),
            ]));

    testWidgets('an activeShape painter is called for exactly one sector, and for none after mouse out', (tester) async {
      final calls = <int>[];
      await tester.pumpWidget(chart((Canvas c, RadialBarShapeProps p) => calls.add(p.index)));
      expect(calls, isEmpty);
      final mouse = await mouseAt(tester, onBar(0));
      await tester.pump();
      expect(calls, [0]);
      calls.clear();
      await mouse.moveTo(onBar(1));
      await tester.pump();
      expect(calls, [1]);
      calls.clear();
      await mouse.moveTo(const Offset(480, 290));
      await tester.pump();
      expect(calls, isEmpty);
      await mouse.removePointer();
    });

    testWidgets('an object activeShape recolors only the hovered sector; false does nothing', (tester) async {
      const red = Color(0xFFFF0000);
      await tester.pumpWidget(chart(const SectorStyle(fill: red)));
      final mouse = await mouseAt(tester, onBar(0));
      await tester.pump();
      var image = await capture(tester);
      expect(await pixel(tester, image, onBar(0, 3)), red);
      expect(await pixel(tester, image, onBar(1, 3)), isNot(red));
      await mouse.moveTo(const Offset(480, 290));
      await tester.pump();
      image = await capture(tester);
      expect(await pixel(tester, image, onBar(0, 3)), isNot(red));
      await mouse.removePointer();

      await tester.pumpWidget(chart(false));
      final m2 = await mouseAt(tester, onBar(0));
      await tester.pump();
      image = await capture(tester);
      expect(await pixel(tester, image, onBar(0, 3)), const Color(0xFF8884D8));
      await m2.removePointer();
    });
  });

  testWidgets('RadialBar mouse handlers receive the sector, its index and the event (RadialBar.spec)', (tester) async {
    final enter = <(RadialBarSector, int)>[], leave = <(RadialBarSector, int)>[], click = <(RadialBarSector, int)>[];
    await tester.pumpWidget(host(RadialBarChart(width: 500, height: 500, data: pageData, children: [
      RadialBar(
        isAnimationActive: false,
        dataKey: 'amt',
        onMouseEnter: (s, i, e) => enter.add((s, i)),
        onMouseLeave: (s, i, e) => leave.add((s, i)),
        onClick: (s, i, e) => click.add((s, i)),
      ),
    ])));
    final mouse = await mouseAt(tester, const Offset(250 + 11.3, 250 - 11.3));
    await tester.pump();
    expect(enter.length, 1);
    final (s, i) = enter.single;
    expect(i, 0);
    expect(s.props['name'], 'Page A');
    expect([s.props['uv'], s.props['pv'], s.props['amt']], [400, 2400, 2400]);
    expect(s.innerRadius, near(3.266666666666666));
    expect(s.outerRadius, near(29.266666666666666));
    expect([s.startAngle, s.endAngle, s.value, s.cx, s.cy], [0, 360, 2400, 250, 250]);
    expect([s.background!.innerRadius, s.background!.endAngle], [near(3.266666666666666), 360]);
    await mouse.down(const Offset(250 + 11.3, 250 - 11.3));
    await mouse.up();
    await tester.pump();
    expect(click.length, 1);
    await mouse.moveTo(const Offset(5, 5));
    await tester.pump();
    expect(leave.length, 1);
    expect(leave.single.$2, 0);
    await mouse.removePointer();
  });

  group('RadarChart.spec: dots, labels, onClick (cx 300, cy 250, outerRadius 150, 600x500)', () {
    Widget chart(Radar radar) => host(RadarChart(
        width: 600, height: 500, cx: 300, cy: 250, outerRadius: 150, data: exampleRadarData, children: [radar]));

    testWidgets('8 dots when dot is true', (tester) async {
      var dots = 0;
      await tester.pumpWidget(chart(Radar(isAnimationActive: false, dot: (Canvas c, DotProps p) => dots++, dataKey: 'value')));
      expect(dots, 8);
    });

    testWidgets('8 labels when label is true', (tester) async {
      var labels = 0;
      await tester.pumpWidget(chart(Radar(isAnimationActive: false, label: (Canvas c, LabelProps p) => labels++, dataKey: 'value')));
      expect(labels, 8);
    });

    testWidgets('clicking the polygon invokes onClick', (tester) async {
      var clicks = 0;
      await tester.pumpWidget(chart(Radar(dataKey: 'value', isAnimationActive: false, onClick: (e) => clicks++)));
      await tester.tapAt(const Offset(300, 250));
      await tester.pump();
      expect(clicks, 1);
    });
  });

  group('Radar polygon events (Radar.spec "events", exampleRadarData, 500x500)', () {
    testWidgets('onMouseEnter and onMouseLeave get the Radar props with its points', (tester) async {
      final enter = <RadarEventProps>[], leave = <RadarEventProps>[];
      await tester.pumpWidget(host(RadarChart(width: 500, height: 500, data: exampleRadarData, children: [
        Radar(
          dataKey: 'value',
          isAnimationActive: false,
          onMouseEnter: (p, e) => enter.add(p),
          onMouseLeave: (p, e) => leave.add(p),
        ),
      ])));
      final mouse = await mouseAt(tester, const Offset(250, 250));
      await tester.pump();
      expect(enter.length, 1);
      final p = enter.single;
      expect(p.radar.dataKey, 'value');
      expect(p.isRange, isFalse);
      expect(p.baseLinePoints, isEmpty);
      expect(p.points.length, 8);
      expect([p.points[0].x, p.points[0].y, p.points[0].radius, p.points[0].angle], [250, near(167.68), near(82.32), 90]);
      expect(p.points[0].value, 420);
      expect(p.points[0].name, 0);
      expect([p.points[0].cx, p.points[0].cy], [250, 250]);
      expect(p.points[1].x, near(313.75274739177917));
      expect(p.points[1].y, near(186.2472526082209));
      expect(p.points[1].radius, near(90.16000000000001));
      expect(p.points[1].angle, 45);
      await mouse.moveTo(const Offset(5, 5));
      await tester.pump();
      expect(leave.length, 1);
      await mouse.removePointer();
    });
  });

  group('Tooltip.visibility.spec: where the tooltip box goes (600x600, a 10x10 tooltip, pointer at 201,201)', () {
    testWidgets('RadarChart', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(host(RadarChart(width: 600, height: 600, data: pageData, children: [
        const PolarGrid(),
        const PolarAngleAxis(dataKey: 'name'),
        const PolarRadiusAxis(),
        const Radar(name: 'Mike', dataKey: 'uv', stroke: Color(0xFF8884D8), fill: Color(0xFF8884D8), fillOpacity: 0.6, id: 'my-item-id'),
        Tooltip(isAnimationActive: false, content: probe.build),
      ])));
      final mouse = await mouseAt(tester, const Offset(200, 200));
      // selectActiveCoordinate at the first hover.
      expect(probe.props!.coordinate!.dx, near(177.5255128608411));
      expect(probe.props!.coordinate!.dy, near(229.28932188134524));
      await mouse.moveTo(const Offset(201, 201));
      await tester.pump();
      final t = tooltipBox(tester).targetTranslate!;
      expect(t.dx, near(188.75025773223268));
      expect(t.dy, near(239.9964286625318));
      await mouse.removePointer();
    });

    testWidgets('RadialBarChart', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(host(RadialBarChart(width: 600, height: 600, data: pageData, children: [
        const PolarGrid(),
        const PolarAngleAxis(),
        const PolarRadiusAxis(dataKey: 'name'),
        const RadialBar(
            name: 'Mike', dataKey: 'uv', stroke: Color(0xFF8884D8), fill: Color(0xFF8884D8), fillOpacity: 0.6, id: 'my-item-id'),
        Tooltip(isAnimationActive: false, content: probe.build),
      ])));
      final mouse = await mouseAt(tester, const Offset(200, 200));
      await mouse.moveTo(const Offset(201, 201));
      await tester.pump();
      final t = tooltipBox(tester).targetTranslate!;
      expect(t.dx, near(212.65496645665198));
      expect(t.dy, near(212.65496645665195));
      await mouse.removePointer();
    });
  });

  group('custom tick, label and shape painters (PolarRadiusAxis.spec, Radar.spec)', () {
    testWidgets('a tick painter is called per tick and a label painter once', (tester) async {
      final ticks = <TickProps>[];
      var labels = 0;
      await tester.pumpWidget(host(RadarChart(width: 500, height: 500, data: exampleRadarData, children: [
        const Radar(dataKey: 'value', isAnimationActive: false),
        PolarRadiusAxis(
            dataKey: 'value',
            tick: (Canvas c, TickProps p) => ticks.add(p),
            label: (Canvas c, LabelProps p) => labels++),
      ])));
      expect([for (final t in ticks) t.text], ['0', '250', '500', '750', '1000']);
      expect([for (final t in ticks) t.x], [250, 299, 348, 397, 446]);
      expect(ticks.first.angle, 90);
      expect(labels, 1);
    });
  });

  testWidgets('a custom radial label gets the polar view box and no computed position (Label.tsx)', (tester) async {
    final seen = <LabelProps>[];
    await tester.pumpWidget(host(RadialBarChart(width: 500, height: 500, data: pageData, children: [
      RadialBar(
          isAnimationActive: false,
          dataKey: 'pv',
          label: LabelList(position: LabelPosition.insideStart, content: (Canvas c, LabelProps p) => seen.add(p))),
    ])));
    expect(seen.length, 6);
    expect(seen.first.x.isNaN, isTrue);
    expect(seen.first.polarViewBox!.cx, 250);
    expect(seen.first.polarViewBox!.endAngle, near(88.16326530612244));
  });
}

Offset polarToOffset(double cx, double cy, double r, double angle) => polarToCartesian(cx, cy, r, angle);
