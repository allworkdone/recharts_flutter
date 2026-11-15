import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/recharts_flutter.dart';
import 'package:recharts_flutter/src/widgets/tooltip.dart' show RenderTooltipBoundingBox, TooltipBoundingBox;

const data = [
  {'name': 'Page A', 'uv': 400, 'pv': 2400},
  {'name': 'Page B', 'uv': 300, 'pv': 4567},
  {'name': 'Page C', 'uv': 300, 'pv': 1398},
  {'name': 'Page D', 'uv': 200, 'pv': 9800},
];

Widget host(Widget chart, {bool disableAnimations = false}) => MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: DefaultTextStyle(
          style: const TextStyle(fontSize: 12, color: Color(0xFF000000)),
          child: Align(alignment: Alignment.topLeft, child: RepaintBoundary(child: chart)),
        ),
      ),
    );

RenderTooltipBoundingBox tooltipBox(WidgetTester tester) =>
    tester.renderObject<RenderTooltipBoundingBox>(find.byType(TooltipBoundingBox));

Future<ui.Image> capture(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
  return (await tester.runAsync(() => boundary.toImage()))!;
}

Future<Color> pixel(WidgetTester tester, ui.Image image, Offset p) async {
  final bytes = (await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
  final i = (p.dy.toInt() * image.width + p.dx.toInt()) * 4;
  return Color.fromARGB(bytes.getUint8(i + 3), bytes.getUint8(i), bytes.getUint8(i + 1), bytes.getUint8(i + 2));
}

void main() {
  testWidgets('BarChart paints its bars (pixel smoke check)', (tester) async {
    await tester.pumpWidget(host(const BarChart(width: 100, height: 50, data: data, children: [
      Bar(dataKey: 'uv', fill: Color(0xFF8884D8), isAnimationActive: false),
    ])));
    final image = await capture(tester);
    // First bar is x 7.25..25.25, y 5..45 (BarChart.spec.tsx).
    expect(await pixel(tester, image, const Offset(16, 30)), const Color(0xFF8884D8));
    expect(await pixel(tester, image, const Offset(2, 30)), const Color(0x00000000));
  });

  testWidgets('LineChart paints its line and dots', (tester) async {
    await tester.pumpWidget(host(const LineChart(width: 100, height: 100, data: data, children: [
      Line(dataKey: 'uv', stroke: Color(0xFFFF0000), strokeWidth: 3, dot: false, isAnimationActive: false),
    ])));
    final image = await capture(tester);
    // uv: 400, 300, 300, 200 over [0, 400] -> points (5,5), (35,27.5), (65,27.5), (95,50).
    expect(await pixel(tester, image, const Offset(50, 27.5)), const Color(0xFFFF0000));
  });

  testWidgets('mouse hover shows tooltip, cursor follows, leaving hides it', (tester) async {
    await tester.pumpWidget(host(const LineChart(width: 400, height: 300, data: data, children: [
      XAxis(dataKey: 'name'),
      Line(dataKey: 'uv'),
      Tooltip(),
    ])));
    expect(find.text('Page C'), findsNothing);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(399, 299));
    await mouse.moveTo(const Offset(270, 100));
    await tester.pump();
    expect(find.text('Page C'), findsOneWidget);
    // Points sit at x = 5, 135, 265, 395; tooltip goes right of the cursor.
    expect(tooltipBox(tester).targetTranslate!.dx, 275);
    await tester.pump(const Duration(milliseconds: 500));
    await mouse.moveTo(const Offset(399, 299));
    await tester.pump();
    expect(find.text('Page C'), findsNothing);
  });

  testWidgets('tooltip transitions with 400ms ease from its last position', (tester) async {
    await tester.pumpWidget(host(const LineChart(width: 400, height: 300, data: data, children: [
      Line(dataKey: 'uv'),
      Tooltip(),
    ])));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(399, 299));
    await mouse.moveTo(const Offset(10, 100));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    final box = tooltipBox(tester);
    expect(box.currentTranslate, box.targetTranslate);
    final start = box.currentTranslate;
    await mouse.moveTo(const Offset(140, 100));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final mid = box.currentTranslate;
    expect(mid.dx, greaterThan(start.dx));
    expect(mid.dx, lessThan(box.targetTranslate!.dx));
    await tester.pump(const Duration(milliseconds: 250));
    expect(box.currentTranslate, box.targetTranslate);
  });

  testWidgets('touch: finger down shows, drag scrubs, lift keeps the tooltip', (tester) async {
    await tester.pumpWidget(host(const LineChart(width: 400, height: 300, data: data, children: [
      XAxis(dataKey: 'name'),
      Line(dataKey: 'uv'),
      Tooltip(),
    ])));
    final finger = await tester.startGesture(const Offset(10, 100), kind: PointerDeviceKind.touch);
    await tester.pump();
    expect(find.text('Page A'), findsOneWidget);
    await finger.moveTo(const Offset(390, 100));
    await tester.pump();
    expect(find.text('Page D'), findsOneWidget);
    await finger.up();
    await tester.pump();
    expect(find.text('Page D'), findsOneWidget);
  });

  testWidgets('onClick reports Recharts event payload fields', (tester) async {
    ChartEventState? state;
    await tester.pumpWidget(host(LineChart(
      width: 400,
      height: 300,
      data: data,
      onClick: (s, _) => state = s,
      children: const [XAxis(dataKey: 'name'), Line(dataKey: 'uv'), Tooltip()],
    )));
    await tester.tapAt(const Offset(140, 100), kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(state!.activeIndex, 1);
    expect(state!.activeTooltipIndex, 1);
    expect(state!.activeLabel, 'Page B');
    expect(state!.activeCoordinate!.dx, 135);
  });

  testWidgets('a chart in a vertical scroll view still scrolls', (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: ListView(controller: controller, children: [
        const LineChart(width: 400, height: 300, data: data, children: [Line(dataKey: 'uv'), Tooltip()]),
        const SizedBox(height: 2000),
      ]),
    ));
    await tester.drag(find.byType(LineChart), const Offset(0, -200));
    await tester.pump();
    expect(controller.offset, greaterThan(100));
  });

  testWidgets('isAnimationActive auto follows MediaQuery.disableAnimations', (tester) async {
    await tester.pumpWidget(host(const BarChart(width: 100, height: 50, data: data, children: [
      Bar(dataKey: 'uv', fill: Color(0xFF8884D8)),
    ]), disableAnimations: true));
    final image = await capture(tester);
    expect(await pixel(tester, image, const Offset(16, 30)), const Color(0xFF8884D8));
  });

  testWidgets('bars grow from the base over 400ms', (tester) async {
    await tester.pumpWidget(host(const BarChart(width: 100, height: 50, data: data, children: [
      Bar(dataKey: 'uv', fill: Color(0xFF8884D8)),
    ])));
    await tester.pump(const Duration(milliseconds: 1));
    final early = await capture(tester);
    expect(await pixel(tester, early, const Offset(16, 30)), const Color(0x00000000));
    await tester.pump(const Duration(milliseconds: 400));
    final done = await capture(tester);
    expect(await pixel(tester, done, const Offset(16, 30)), const Color(0xFF8884D8));
  });

  group('Bar.rerenderStability.spec.tsx: with Cell children', () {
    var starts = 0;
    Widget chart(List<String> fills) => host(BarChart(width: 100, height: 50, data: data.sublist(0, 2), children: [
          Bar(dataKey: 'pv', onAnimationStart: () => starts++, children: [for (final f in fills) Cell.css(fill: f)]),
        ]));
    setUp(() => starts = 0);

    testWidgets('rebuilding the same Cells does not restart the animation', (tester) async {
      await tester.pumpWidget(chart(['green', 'blue']));
      await tester.pumpAndSettle();
      expect(starts, 1);
      await tester.pumpWidget(chart(['green', 'blue']));
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      expect(starts, 1);
    });

    testWidgets('new Cell props still apply when they actually change', (tester) async {
      await tester.pumpWidget(chart(['green', 'blue']));
      await tester.pumpAndSettle();
      await tester.pumpWidget(chart(['orange', 'purple']));
      await tester.pumpAndSettle();
      // Bars at x 9.5 and 54.5, 36 wide, down to y 45.
      final image = await capture(tester);
      expect(await pixel(tester, image, const Offset(16, 44)), const Color(0xFFFFA500));
      expect(await pixel(tester, image, const Offset(70, 44)), const Color(0xFF800080));
    });
  });

  testWidgets('ResponsiveContainer resolves percent sizes and aspect', (tester) async {
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 400,
          height: 300,
          child: ResponsiveContainer(
            width: '50%',
            aspect: 2,
            child: const LineChart(data: data, children: [Line(dataKey: 'uv')]),
          ),
        ),
      ),
    ));
    expect(tester.getSize(find.byType(LineChart)), const Size(200, 100));
  });

  testWidgets('chart without size fills its constraints', (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 320, height: 180, child: BarChart(data: data, children: [Bar(dataKey: 'uv')])),
      ),
    ));
    expect(tester.getSize(find.byType(BarChart)), const Size(320, 180));
  });
}
