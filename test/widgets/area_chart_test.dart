// AreaChart rendering: fill and stroke, the AreaRevealShape entrance, data
// change animation without the reveal, labels hidden while animating, active
// dots (Area.spec.tsx / AreaChart.spec.tsx 'two active dots for ranged Area'),
// gradient fills and z order inside ComposedChart.

import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/recharts_flutter.dart';

const data = [
  {'name': 'Page A', 'uv': 400, 'pv': 2400},
  {'name': 'Page B', 'uv': 300, 'pv': 4567},
  {'name': 'Page C', 'uv': 300, 'pv': 1398},
  {'name': 'Page D', 'uv': 200, 'pv': 9800},
];

const red = Color(0xFFFF0000), green = Color(0xFF00FF00), blue = Color(0xFF0000FF);
const clear = Color(0x00000000);

Widget host(Widget chart) => MediaQuery(
      data: const MediaQueryData(),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: DefaultTextStyle(
          style: const TextStyle(fontSize: 12, color: Color(0xFF000000)),
          child: Align(alignment: Alignment.topLeft, child: RepaintBoundary(child: chart)),
        ),
      ),
    );

Future<ui.Image> capture(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
  return (await tester.runAsync(() => boundary.toImage()))!;
}

/// Premultiplied RGBA at [p].
Future<Color> pixel(WidgetTester tester, ui.Image image, Offset p) async {
  final bytes = (await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
  final i = (p.dy.toInt() * image.width + p.dx.toInt()) * 4;
  return Color.fromARGB(bytes.getUint8(i + 3), bytes.getUint8(i), bytes.getUint8(i + 1), bytes.getUint8(i + 2));
}

Future<List<Color>> pixels(WidgetTester tester, List<Offset> ps) async {
  final image = await capture(tester);
  return [for (final p in ps) await pixel(tester, image, p)];
}

// 100x50 without axes: points at x 5, 35, 65, 95; uv 400/300/200 at y 5/15/25; baseline 45.
AreaChart small(List<RechartsElement> children) => AreaChart(width: 100, height: 50, data: data, children: children);

void main() {
  testWidgets('fills down to the baseline with fillOpacity', (tester) async {
    await tester.pumpWidget(host(small(const [
      Area(dataKey: 'uv', stroke: null, fill: red, fillOpacity: 1, isAnimationActive: false),
    ])));
    expect(await pixels(tester, const [Offset(50, 40), Offset(50, 8)]), [red, clear]);

    await tester.pumpWidget(host(small(const [Area(dataKey: 'uv', stroke: null, fill: red, isAnimationActive: false)])));
    final c = (await pixels(tester, const [Offset(50, 40)])).single;
    expect(c.a, closeTo(0.6, 0.01));
  });

  testWidgets('an Area outside AreaChart and ComposedChart draws nothing', (tester) async {
    await tester.pumpWidget(host(const LineChart(width: 100, height: 50, data: data, children: [
      Area(dataKey: 'uv', stroke: null, fill: red, fillOpacity: 1, isAnimationActive: false),
    ])));
    expect(await pixels(tester, const [Offset(50, 40)]), [clear]);
  });

  testWidgets('the entrance reveals the area left to right, then data changes animate unclipped', (tester) async {
    var started = 0, ended = 0;
    Widget chart(String key) => host(small([
          Area(
            dataKey: key,
            stroke: null,
            fill: red,
            fillOpacity: 1,
            animationEasing: 'linear',
            animationDuration: 1000,
            onAnimationStart: () => started++,
            onAnimationEnd: () => ended++,
          ),
        ]));
    await tester.pumpWidget(chart('uv'));
    expect(await pixels(tester, const [Offset(20, 40)]), [clear]);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 500));
    // The clip spans x 5..50.
    expect(await pixels(tester, const [Offset(20, 40), Offset(45, 40), Offset(55, 40), Offset(80, 40)]),
        [red, red, clear, clear]);
    expect(started, 1);
    expect(ended, 0);
    await tester.pump(const Duration(milliseconds: 600));
    expect(await pixels(tester, const [Offset(80, 40)]), [red]);
    expect(ended, 1);

    // pv (domain [0, 10000]) everywhere at once: no reveal clip.
    await tester.pumpWidget(chart('pv'));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 500));
    expect(await pixels(tester, const [Offset(20, 44), Offset(90, 44)]), [red, red]);
    await tester.pumpAndSettle();
    expect(ended, 2);
  });

  testWidgets('labels are hidden while the area animates', (tester) async {
    var labels = 0;
    await tester.pumpWidget(host(small([
      Area(dataKey: 'uv', label: LabelList(content: (_, _) => labels++)),
    ])));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 700));
    expect(labels, 0);
    await tester.pump(const Duration(milliseconds: 900));
    expect(labels, greaterThan(0));
  });

  testWidgets('hover: tooltip row and an active dot in the main color', (tester) async {
    await tester.pumpWidget(host(const AreaChart(width: 400, height: 300, data: data, children: [
      XAxis(dataKey: 'name'),
      Area(dataKey: 'uv', stroke: null, fill: green, isAnimationActive: false),
      Tooltip(isAnimationActive: false),
    ])));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(399, 299));
    await mouse.moveTo(const Offset(140, 100));
    await tester.pump();
    expect(find.text('Page B'), findsOneWidget);
    expect(find.text('uv : 300', findRichText: true), findsOneWidget);
    // Plot 5..395 x 5..265: Page B at (135, 70). Stroke is none, so the dot takes the fill.
    expect(await pixels(tester, const [Offset(135, 70)]), [green]);
  });

  testWidgets('syncId shares the tooltip index with another AreaChart', (tester) async {
    Widget chart() => const AreaChart(width: 400, height: 150, data: data, syncId: 'sync', children: [
          XAxis(dataKey: 'name'),
          Area(dataKey: 'uv', isAnimationActive: false),
          Tooltip(isAnimationActive: false),
        ]);
    await tester.pumpWidget(host(Column(mainAxisSize: MainAxisSize.min, children: [chart(), chart()])));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(399, 299));
    await mouse.moveTo(const Offset(270, 60));
    await tester.pump();
    expect(find.text('uv : 300', findRichText: true), findsNWidgets(2));
  });

  testWidgets('a range area marks the high and the low point', (tester) async {
    const range = [
      {'day': 'a', 't': [100, 300]},
      {'day': 'b', 't': [0, 400]},
      {'day': 'c', 't': [200, 300]},
    ];
    await tester.pumpWidget(host(const AreaChart(width: 400, height: 300, data: range, children: [
      XAxis(dataKey: 'day'),
      Area(dataKey: 't', stroke: null, fill: green, fillOpacity: 0.2, isAnimationActive: false),
      Tooltip(isAnimationActive: false),
    ])));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(399, 299));
    await mouse.moveTo(const Offset(200, 100));
    await tester.pump();
    expect(find.text('t : 0 ~ 400', findRichText: true), findsOneWidget);
    // Domain [0, 400] over y 265..5: high 400 at y 5, low 0 at y 265, at x 200.
    expect(await pixels(tester, const [Offset(200, 6), Offset(200, 264)]), [green, green]);
  });

  testWidgets('gradient fills span the shape bounding box', (tester) async {
    const gradient = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [red, blue]);
    // First bar: x 7.25..25.25, y 5..45 (BarChart.spec.tsx).
    await tester.pumpWidget(host(const BarChart(width: 100, height: 50, data: data, children: [
      Bar(dataKey: 'uv', fill: gradient, isAnimationActive: false),
    ])));
    var [top, bottom] = await pixels(tester, const [Offset(16, 5), Offset(16, 44)]);
    expect(top.r, greaterThan(0.9));
    expect(bottom.b, greaterThan(0.9));

    await tester.pumpWidget(host(small(const [
      Area(dataKey: 'uv', stroke: null, fill: gradient, fillOpacity: 1, isAnimationActive: false),
    ])));
    [top, bottom] = await pixels(tester, const [Offset(6, 6), Offset(50, 44)]);
    expect(top.r, greaterThan(0.9));
    expect(bottom.b, greaterThan(0.9));
  });

  testWidgets('ComposedChart draws areas under bars and lines', (tester) async {
    await tester.pumpWidget(host(const ComposedChart(width: 100, height: 50, data: data, children: [
      Line(dataKey: 'uv', stroke: green, strokeWidth: 3, dot: false, isAnimationActive: false),
      Bar(dataKey: 'uv', fill: blue, isAnimationActive: false),
      Area(dataKey: 'uv', stroke: null, fill: red, fillOpacity: 1, isAnimationActive: false),
    ])));
    // Band scale: first bar x 7.25..25.25; the area spans the plot below the curve.
    expect(await pixels(tester, const [Offset(16, 40), Offset(28, 44)]), [blue, red]);
  });

  testWidgets('a stacked area sits on the one below', (tester) async {
    await tester.pumpWidget(host(small(const [
      Area(dataKey: 'uv', stackId: 's', stroke: null, fill: red, fillOpacity: 1, isAnimationActive: false),
      Area(dataKey: 'uv', stackId: 's', stroke: null, fill: blue, fillOpacity: 1, isAnimationActive: false),
    ])));
    // Domain [0, 800] over y 45..5: Page A uv 400 ends at y 25, the second one at y 5.
    expect(await pixels(tester, const [Offset(6, 40), Offset(6, 10)]), [red, blue]);
  });
}
