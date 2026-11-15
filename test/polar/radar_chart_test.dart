// RadarChart and RadialBarChart tooltips and syncId through the widgets,
// following component/Tooltip/Tooltip.payload.spec.tsx (polar cases) and
// Tooltip.sync.spec.tsx (index sync between different chart types).

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/recharts_flutter.dart';
import 'package:recharts_flutter/src/engine/pie.dart' show computePolarModel;
import 'package:recharts_flutter/src/engine/polar_axis.dart';

import '../widgets/chart_widget_test.dart' show capture, host, pixel, tooltipBox;
import '../widgets/tooltip_item_test.dart' show Probe, mouseAt;
import 'polar_scene_test.dart' show pageData;

void main() {
  testWidgets('RadarChart: hovering shows every Radar at the nearest spoke, with the angle axis label', (tester) async {
    final probe = Probe();
    await tester.pumpWidget(host(RadarChart(width: 600, height: 600, data: pageData, children: [
      const Radar(dataKey: 'uv', isAnimationActive: false),
      const Radar(dataKey: 'pv', name: 'My custom name', isAnimationActive: false),
      const Radar(dataKey: 'amt', isAnimationActive: false),
      const PolarAngleAxis(dataKey: 'name'),
      Tooltip(isAnimationActive: false, content: probe.build),
    ])));
    expect(probe.visible, isFalse);
    final mouse = await mouseAt(tester, const Offset(200, 200));
    expect(probe.visible, isTrue);
    expect(probe.props!.label, 'Page F');
    expect(probe.rows, ['uv : 189', 'My custom name : 4800', 'amt : 2400']);
    expect(probe.props!.activeIndex, 5);

    // The tooltip hides when the pointer leaves the polar view box but stays in the chart.
    await mouse.moveTo(const Offset(8, 8));
    await tester.pump();
    expect(probe.visible, isFalse);
    await mouse.removePointer();
  });

  testWidgets('RadialBarChart: the axis tooltip is labelled by the category index', (tester) async {
    final probe = Probe();
    await tester.pumpWidget(host(RadialBarChart(width: 600, height: 600, data: pageData, children: [
      const RadialBar(dataKey: 'uv', isAnimationActive: false),
      const RadialBar(dataKey: 'pv', name: 'My custom name', isAnimationActive: false),
      Tooltip(isAnimationActive: false, content: probe.build),
    ])));
    final mouse = await mouseAt(tester, const Offset(200, 200));
    expect(probe.props!.label, 3);
    expect(probe.rows, ['uv : 200', 'My custom name : 9800']);
    await mouse.removePointer();
  });

  testWidgets('RadarChart ignores shared: false and keeps the axis tooltip', (tester) async {
    final probe = Probe();
    await tester.pumpWidget(host(RadarChart(width: 600, height: 600, data: pageData, children: [
      const Radar(dataKey: 'uv', isAnimationActive: false),
      Tooltip(isAnimationActive: false, shared: false, content: probe.build),
    ])));
    final mouse = await mouseAt(tester, const Offset(200, 200));
    expect(probe.rows, ['uv : 189']);
    await mouse.removePointer();
  });

  testWidgets('a RadialBarChart tooltip with shared: false follows the hovered sector', (tester) async {
    final probe = Probe();
    await tester.pumpWidget(host(RadialBarChart(width: 600, height: 600, data: pageData, children: [
      const RadialBar(dataKey: 'uv', isAnimationActive: false),
      Tooltip(isAnimationActive: false, shared: false, content: probe.build),
    ])));
    // Page A's sector runs from 0 to uv 400/400 * 360 at the first ring: radius ~16 around (300, 300).
    final mouse = await mouseAt(tester, const Offset(300 + 15, 300 - 1));
    expect(probe.props!.active, isTrue);
    expect(probe.props!.activeIndex, 0);
    // RadialBar sectors carry no tooltipPosition, so the box has no coordinate to sit at.
    expect(probe.props!.coordinate, isNull);
    // translate.ts hides the transform but the box stays visible at the wrapper's (0, 0).
    expect(tooltipBox(tester).currentTranslate, Offset.zero);
    expect(tooltipBox(tester).isVisible, isTrue);
    await mouse.removePointer();
  });

  testWidgets('RadarChart: focus shows the tooltip at index 0 and the arrow keys move it along the angle axis', (tester) async {
    final probe = Probe();
    await tester.pumpWidget(host(RadarChart(width: 600, height: 600, data: pageData, children: [
      const Radar(dataKey: 'uv', isAnimationActive: false),
      const PolarAngleAxis(dataKey: 'name'),
      Tooltip(isAnimationActive: false, content: probe.build),
    ])));
    await tester.tapAt(const Offset(8, 8));
    await tester.pump();
    expect(probe.props!.label, 'Page A');
    expect(probe.rows, ['uv : 400']);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(probe.props!.label, 'Page B');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(probe.props!.label, 'Page A');
  });

  // Label.spec.tsx 'should render position=center in the center of the polar chart when cy is set'
  testWidgets('a centered PolarRadiusAxis label sits at the polar center', (tester) async {
    Offset? at;
    await tester.pumpWidget(host(RadialBarChart(width: 500, height: 500, data: pageData, cy: '70%', startAngle: 180, endAngle: 0, children: [
      const RadialBar(dataKey: 'uv', isAnimationActive: false),
      PolarRadiusAxis(
          tick: false,
          axisLine: false,
          label: Label(position: LabelPosition.center, value: 'center label', content: (_, p) => at = Offset(p.x, p.y))),
    ])));
    expect(at, const Offset(250, 350));
  });

  // RadialBar.theme.spec.tsx 'does not apply the entry styles to the background'
  testWidgets('a RadialBar background does not take the stroke of the data entry', (tester) async {
    const data = [
      {'name': 'A', 'value': 1, 'stroke': 'lime', 'strokeWidth': 5},
      {'name': 'B', 'value': 2},
    ];
    await tester.pumpWidget(host(const RadialBarChart(width: 400, height: 400, data: data, children: [
      RadialBar(dataKey: 'value', background: true, isAnimationActive: false),
    ])));
    // Sector A covers the upper half of its ring; below the center only its background shows.
    final a = computePolarModel(
      chartName: 'RadialBarChart',
      size: const Size(400, 400),
      data: data,
      children: const [RadialBar(dataKey: 'value')],
      layout: PolarLayout.radial,
      options: const PolarOptions(startAngle: 0, endAngle: 360),
    ).scene!.radialBars.single.sectors.first;
    final image = await capture(tester);
    expect(await pixel(tester, image, Offset(200, 200 + (a.innerRadius + a.outerRadius) / 2)), const Color(0xFFEEEEEE));
    expect((await pixel(tester, image, Offset(200, 200 + a.outerRadius + 1.5))).a, 0);
  });

  // AccessibilityLayer.spec.tsx 'When chart receives focus, arrow keys navigate its tooltip around the polar axis'
  testWidgets('RadarChart: the keyboard tooltip sits on the outer radius and draws the cursor', (tester) async {
    final probe = Probe();
    const radarKeyboardData = [
      {'name': 'North', 'uv': 400},
      {'name': 'East', 'uv': 300},
      {'name': 'South', 'uv': 200},
      {'name': 'West', 'uv': 100},
    ];
    await tester.pumpWidget(host(RadarChart(width: 400, height: 400, cx: 200, cy: 200, outerRadius: 100, data: radarKeyboardData, children: [
      const PolarAngleAxis(dataKey: 'name'),
      const Radar(dataKey: 'uv', isAnimationActive: false),
      Tooltip(isAnimationActive: false, content: probe.build),
    ])));
    void expectAt(String label, Offset p) {
      expect(probe.props!.label, label);
      expect(probe.props!.coordinate!.dx, closeTo(p.dx, 1e-9));
      expect(probe.props!.coordinate!.dy, closeTo(p.dy, 1e-9));
    }

    await tester.tapAt(const Offset(8, 8));
    await tester.pump();
    expect(probe.rows, ['uv : 400']);
    expectAt('North', const Offset(200, 100));
    // East's point is at radius 75: past it, only the cursor line M200,200L300,200 is drawn.
    expect((await pixel(tester, await capture(tester), const Offset(290, 200))).a, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(probe.rows, ['uv : 300']);
    expectAt('East', const Offset(300, 200));
    expect((await pixel(tester, await capture(tester), const Offset(290, 200))).a, greaterThan(0));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expectAt('North', const Offset(200, 100));
  });

  // combineCoordinateForDefaultIndex.spec.ts 'returns a PolarCoordinate for radial layout'
  testWidgets('RadialBarChart: defaultIndex draws the cursor and puts the tooltip at the middle angle', (tester) async {
    final probe = Probe();
    await tester.pumpWidget(host(RadialBarChart(width: 400, height: 400, data: pageData, children: [
      const RadialBar(dataKey: 'uv', fill: Color(0xFFFF0000), isAnimationActive: false),
      Tooltip(isAnimationActive: false, defaultIndex: 0, content: probe.build),
    ])));
    // cx 200, cy 200, outerRadius 156, angles 0..360: the middle angle 180 on the outer radius.
    expect(probe.props!.coordinate!.dx, closeTo(44, 1e-9));
    expect(probe.props!.coordinate!.dy, closeTo(200, 1e-9));
    // The cursor ring at the first category's radius, 13, crosses Page A's red bar.
    final c = await pixel(tester, await capture(tester), const Offset(187, 200));
    expect(c.g, greaterThan(0));
  });

  testWidgets('syncId shares the tooltip index between a LineChart and a RadarChart', (tester) async {
    final probe = Probe(), lineProbe = Probe();
    const data = [
      {'name': 'a', 'uv': 1},
      {'name': 'b', 'uv': 3},
      {'name': 'c', 'uv': 2},
    ];
    await tester.pumpWidget(host(Column(children: [
      SizedBox(
          width: 400,
          height: 200,
          child: LineChart(width: 400, height: 200, data: data, syncId: 's', children: [
            const XAxis(dataKey: 'name'),
            const Line(dataKey: 'uv', isAnimationActive: false),
            Tooltip(isAnimationActive: false, content: lineProbe.build),
          ])),
      SizedBox(
          width: 400,
          height: 400,
          child: RadarChart(width: 400, height: 400, data: data, syncId: 's', children: [
            const PolarAngleAxis(dataKey: 'name'),
            const Radar(dataKey: 'uv', isAnimationActive: false),
            Tooltip(isAnimationActive: false, content: probe.build),
          ])),
    ])));
    final mouse = await mouseAt(tester, const Offset(200, 100));
    expect(probe.props!.active, isTrue);
    expect(probe.props!.activeIndex, 1);
    expect(probe.props!.label, 'b');
    expect(probe.rows, ['uv : 3']);
    // And the other way: the radar's active spoke drives the line chart.
    await mouse.moveTo(const Offset(200, 300));
    await tester.pump();
    expect(lineProbe.props!.active, isTrue);
    expect(lineProbe.props!.activeIndex, 0);
    expect(lineProbe.props!.label, 'a');
    await mouse.removePointer();
  });

  testWidgets('a Radar without fill or stroke has no tooltip color; its active dot is a hollow ring', (tester) async {
    final probe = Probe();
    await tester.pumpWidget(host(RadarChart(width: 600, height: 600, data: pageData, children: [
      const Radar(dataKey: 'uv', isAnimationActive: false),
      Tooltip(isAnimationActive: false, content: probe.build),
    ])));
    final mouse = await mouseAt(tester, const Offset(200, 200));
    expect(probe.props!.payload.single.color, isNull);
    expect(probe.props!.payload.single.fill, isNull);
    await mouse.removePointer();
  });

  testWidgets('equal const children are separate items', (tester) async {
    final probe = Probe();
    await tester.pumpWidget(host(RadialBarChart(width: 600, height: 600, data: pageData, children: [
      const RadialBar(dataKey: 'uv', isAnimationActive: false),
      const RadialBar(dataKey: 'uv', isAnimationActive: false),
      Tooltip(isAnimationActive: false, shared: false, content: probe.build),
    ])));
    // Both bars share a band; the later one is on top.
    final mouse = await mouseAt(tester, const Offset(300 + 15, 300 - 1));
    expect(probe.rows.length, 1);
    await mouse.removePointer();
  });

  testWidgets('a polar chart synced from another polar chart draws the cursor', (tester) async {
    const clear = Color(0x00000000);
    Widget radar(Object? syncId) => RadarChart(width: 300, height: 300, data: pageData, syncId: 's', children: [
          const Radar(dataKey: 'uv', fill: clear, isAnimationActive: false),
          const PolarAngleAxis(dataKey: 'name'),
          Tooltip(isAnimationActive: false),
        ]);
    await tester.pumpWidget(host(Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(width: 300, height: 300, child: radar(1)),
      SizedBox(width: 300, height: 300, child: RadarChart(width: 300, height: 300, data: pageData, syncId: 's', children: [
        const Radar(dataKey: 'uv', fill: clear, isAnimationActive: false),
        Tooltip(isAnimationActive: false),
      ])),
    ])));
    final mouse = await mouseAt(tester, const Offset(150, 100));
    await tester.pump();
    // The second chart's spoke for index 0 runs straight up from its center (450, 150).
    final image = await capture(tester);
    final c = await pixel(tester, image, const Offset(449.5, 100));
    expect(c.a, greaterThan(0.1));
    await mouse.removePointer();
  });
}
