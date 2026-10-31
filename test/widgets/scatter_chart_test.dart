// ScatterChart interaction, ported from Recharts 3.10.1 test/chart/ScatterChart.spec.tsx
// ("Tooltip integration", "customized active shape") and test/cartesian/Scatter.spec.tsx
// ("Multiple Scatter components tooltip filtering"), with Recharts' 10x10 mocked
// tooltip box, plus pixel checks of the cross cursor, ErrorBar and its animation.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/recharts_flutter.dart';
import 'package:recharts_flutter/src/engine/model.dart';

import 'chart_widget_test.dart' show capture, host, pixel, tooltipBox;
import 'tooltip_item_test.dart' show Probe, mouseAt, pageData, red;

void main() {
  group('Tooltip integration (100x100, XAxis uv, YAxis pv)', () {
    Widget chart(Probe probe, {int? defaultIndex}) => host(ScatterChart(width: 100, height: 100, data: pageData, children: [
          const Scatter(isAnimationActive: false, id: 'my-scatter'),
          const XAxis(dataKey: 'uv'),
          const YAxis(dataKey: 'pv'),
          Tooltip(isAnimationActive: false, defaultIndex: defaultIndex, content: probe.build),
        ]));

    testWidgets('no tooltip before interaction; hovering a point shows its x and y', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(chart(probe));
      expect(probe.visible, isFalse);
      final mouse = await mouseAt(tester, const Offset(99, 99));
      // The first point sits at (67.5, 50.6).
      await mouse.moveTo(const Offset(68, 51));
      await tester.pump();
      expect(probe.rows, ['uv : 400', 'pv : 2400']);
      expect(probe.props!.label, isNull);
      expect(probe.props!.coordinate, const Offset(67.5, 50.6));
      expect(tooltipBox(tester).targetTranslate!.dx, 77.5);
      expect(tooltipBox(tester).targetTranslate!.dy, closeTo(30.6, 1e-9));
      // Between points: the item's mouseleave hides it.
      await mouse.moveTo(const Offset(66, 30));
      await tester.pump();
      expect(probe.visible, isFalse);
    });

    testWidgets('defaultIndex=1 shows the second point before interaction', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(chart(probe, defaultIndex: 1));
      expect(probe.rows, ['uv : 300', 'pv : 4567']);
      expect(tooltipBox(tester).targetTranslate!.dx, 82.5);
      expect(tooltipBox(tester).targetTranslate!.dy, closeTo(47.598, 1e-9));
    });
  });

  testWidgets('only the hovered Scatter shows in the tooltip', (tester) async {
    const data01 = [
      {'x': 10, 'y': 20, 'z': 30},
      {'x': 20, 'y': 30, 'z': 40},
    ];
    const data02 = [
      {'x': 15, 'y': 25, 'z': 35},
      {'x': 25, 'y': 35, 'z': 45},
    ];
    final probe = Probe();
    final children = [
      const XAxis(dataKey: 'x', type: AxisDomainType.number, allowDecimals: false),
      const YAxis(dataKey: 'y', type: AxisDomainType.number, allowDecimals: false),
      const ZAxis(dataKey: 'z', range: [64, 144]),
      Tooltip(cursor: false, isAnimationActive: false, content: probe.build),
      const Scatter(name: 'A school', data: data01, fill: Color(0xFF8884D8), isAnimationActive: false),
      const Scatter(name: 'B school', data: data02, fill: Color(0xFF82CA9D), isAnimationActive: false),
    ];
    await tester.pumpWidget(host(ScatterChart(width: 400, height: 400, children: children)));
    final m = computeCartesianModel(
        chartName: 'ScatterChart', size: const Size(400, 400), data: const [], children: children, measureFor: (_) => (_) => Size.zero);
    Offset at(int series) => m.series[series].scatterPoints![0].tooltipPosition!;
    final mouse = await mouseAt(tester, const Offset(399, 399));
    await mouse.moveTo(at(0));
    await tester.pump();
    expect(probe.props!.payload.map((e) => e.payload).toSet(), {data01[0]});
    expect(probe.rows, ['x : 10', 'y : 20', 'z : 30']);
    await mouse.moveTo(at(1));
    await tester.pump();
    expect(probe.props!.payload.map((e) => e.payload).toSet(), {data02[0]});
  });

  group('customized active shape', () {
    const data = [
      {'x': 100, 'y': 200, 'z': 200},
      {'x': 120, 'y': 100, 'z': 260},
      {'x': 170, 'y': 300, 'z': 400},
    ];
    Widget chart(Object? activeShape) => host(ScatterChart(width: 400, height: 400, children: [
          const XAxis(dataKey: 'x', type: AxisDomainType.number),
          const YAxis(dataKey: 'y', type: AxisDomainType.number),
          Scatter(
              data: data,
              fill: const Color(0xFFFF7300),
              shape: SymbolType.square,
              activeShape: activeShape,
              isAnimationActive: false),
          const Tooltip(isAnimationActive: false, cursor: false),
        ]));
    // x [0, 180] over [65, 395], y [0, 300] over [365, 5]: point 1 at (285, 245).
    const point1 = Offset(285, 245), orange = Color(0xFFFF7300);

    testWidgets('an SvgStyle activeShape draws the hovered point as a circle with its props', (tester) async {
      await tester.pumpWidget(chart(const SvgStyle(fill: red)));
      // The square's corner is outside the active circle.
      const corner = Offset(285 + 3.5, 245 - 3.5);
      var image = await capture(tester);
      expect(await pixel(tester, image, point1), orange);
      expect(await pixel(tester, image, corner), orange);
      final mouse = await mouseAt(tester, const Offset(399, 0));
      await mouse.moveTo(point1);
      await tester.pump();
      image = await capture(tester);
      expect(await pixel(tester, image, point1), red);
      expect(await pixel(tester, image, corner), isNot(orange));
      await mouse.moveTo(const Offset(399, 0));
      await tester.pump();
      image = await capture(tester);
      expect(await pixel(tester, image, point1), orange);
    });

    testWidgets('activeShape=false keeps the point', (tester) async {
      await tester.pumpWidget(chart(false));
      final mouse = await mouseAt(tester, const Offset(399, 0));
      await mouse.moveTo(point1);
      await tester.pump();
      expect(await pixel(tester, await capture(tester), point1), orange);
    });
  });

  testWidgets('the cursor is a cross through the hovered point', (tester) async {
    await tester.pumpWidget(host(const ScatterChart(width: 400, height: 400, children: [
      XAxis(dataKey: 'x', type: AxisDomainType.number),
      YAxis(dataKey: 'y', type: AxisDomainType.number),
      Scatter(data: [
        {'x': 50, 'y': 50},
        {'x': 100, 'y': 100},
      ], fill: Color(0xFF0000FF), isAnimationActive: false),
      Tooltip(isAnimationActive: false, cursor: SvgStyle(stroke: red, strokeWidth: 3)),
    ])));
    // x [0, 100] over [65, 395], y [0, 100] over [365, 5]: point 0 at (230, 185).
    final mouse = await mouseAt(tester, const Offset(399, 0));
    await mouse.moveTo(const Offset(230, 185));
    await tester.pump();
    final image = await capture(tester);
    expect(await pixel(tester, image, const Offset(230, 30)), red);
    expect(await pixel(tester, image, const Offset(100, 185)), red);
    expect(await pixel(tester, image, const Offset(100, 30)), const Color(0x00000000));
  });

  testWidgets('ErrorBar scales in over 400ms and is drawn above the bar', (tester) async {
    await tester.pumpWidget(host(const BarChart(width: 100, height: 100, data: [
      {'v': 50, 'e': 20},
    ], children: [
      YAxis(hide: true, domain: [0, 100]),
      Bar(dataKey: 'v', fill: Color(0xFF00FF00), isAnimationActive: false, children: [
        ErrorBar(dataKey: 'e', stroke: red, strokeWidth: 3, animationEasing: 'linear'),
      ]),
    ])));
    // The bar spans x 14..86 from y 50; the whisker at x 50 spans y 32 (v + e) to
    // 68 (v - e) and scales around the bar's top-left corner moved by half its
    // width, (50, 86).
    const transparent = Color(0x00000000), green = Color(0xFF00FF00);
    expect(await pixel(tester, await capture(tester), const Offset(50, 33)), transparent);
    await tester.pump(); // the transition starts a frame late
    await tester.pump(const Duration(milliseconds: 200));
    var image = await capture(tester);
    // Half way it spans y 59..77.
    expect(await pixel(tester, image, const Offset(50, 60)), red);
    expect(await pixel(tester, image, const Offset(50, 45)), transparent);
    await tester.pump(const Duration(milliseconds: 250));
    image = await capture(tester);
    expect(await pixel(tester, image, const Offset(50, 33)), red);
    expect(await pixel(tester, image, const Offset(50, 67)), red);
    expect(await pixel(tester, image, const Offset(50, 72)), green);
  });
}
