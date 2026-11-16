// Data entry styles on the dots of Line, Area and Radar, ported from Recharts
// test/component/Tooltip/Tooltip.dataPointColors.spec.tsx (canary.9): each dot
// takes the SVG props of its data entry, the active dot its fill, and the
// tooltip keeps the series color. Dot and activeDot painters record the props
// the attributes are rendered from.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/recharts_flutter.dart';

import 'chart_widget_test.dart' show capture, host, pixel;
import 'tooltip_item_test.dart' show Probe;

const data = [
  {'name': 'A', 'uv': 400, 'fill': '#ff0000', 'stroke': '#0000ff'},
  {'name': 'B', 'uv': 300},
];

const seriesColor = Color(0xFF8884D8);
const red = Color(0xFFFF0000), blue = Color(0xFF0000FF), green = Color(0xFF00FF00), magenta = Color(0xFFFF00FF);

class Dots {
  final dots = <int, DotProps>{};
  DotProps? active;
  void dot(Canvas _, DotProps p) => dots[p.index] = p;
  void activeDot(Canvas _, DotProps p) => active = p;
}

void main() {
  Future<(Dots, Probe)> render(WidgetTester tester, Widget Function(Dots d, Probe p) chart) async {
    final d = Dots(), probe = Probe();
    await tester.pumpWidget(host(chart(d, probe)));
    return (d, probe);
  }

  void expectEntryColors(Dots d, Probe probe) {
    expect(d.dots[0]!.fill, red);
    expect(d.dots[0]!.stroke, blue);
    // a data entry without colors keeps the colors of the series
    expect(d.dots[1]!.stroke, seriesColor);
    expect(d.active!.fill, red);
    expect(probe.props!.payload.single.color, seriesColor);
  }

  testWidgets('Line dots and the active dot take the data entry colors, the tooltip the series color', (tester) async {
    final (d, probe) = await render(
        tester,
        (d, p) => LineChart(width: 400, height: 300, data: data, children: [
              Line(dataKey: 'uv', stroke: seriesColor, dot: d.dot, activeDot: d.activeDot, isAnimationActive: false),
              Tooltip(defaultIndex: 0, isAnimationActive: false, content: p.build),
            ]));
    expectEntryColors(d, probe);
  });

  testWidgets('Area dots and the active dot take the data entry colors, the tooltip the series color', (tester) async {
    final (d, probe) = await render(
        tester,
        (d, p) => AreaChart(width: 400, height: 300, data: data, children: [
              Area(
                  dataKey: 'uv',
                  stroke: seriesColor,
                  fill: const Color(0xFF82CA9D),
                  dot: d.dot,
                  activeDot: d.activeDot,
                  isAnimationActive: false),
              Tooltip(defaultIndex: 0, isAnimationActive: false, content: p.build),
            ]));
    expectEntryColors(d, probe);
  });

  testWidgets('Radar dots and the active dot take the data entry colors, the tooltip the series color', (tester) async {
    final (d, probe) = await render(
        tester,
        (d, p) => RadarChart(width: 400, height: 300, data: data, children: [
              const PolarAngleAxis(dataKey: 'name'),
              Radar(
                  dataKey: 'uv',
                  stroke: seriesColor,
                  fill: const Color(0xFF82CA9D),
                  dot: d.dot,
                  activeDot: d.activeDot,
                  isAnimationActive: false),
              Tooltip(defaultIndex: 0, isAnimationActive: false, content: p.build),
            ]));
    expectEntryColors(d, probe);
  });

  testWidgets('the active dot keeps the series color if the data entry has no fill', (tester) async {
    final (d, probe) = await render(
        tester,
        (d, p) => LineChart(width: 400, height: 300, data: const [
              {'name': 'A', 'uv': 400, 'stroke': '#0000ff'},
              {'name': 'B', 'uv': 300},
            ], children: [
              Line(dataKey: 'uv', stroke: seriesColor, dot: d.dot, activeDot: d.activeDot, isAnimationActive: false),
              Tooltip(defaultIndex: 0, isAnimationActive: false, content: p.build),
            ]));
    expect(d.dots[0]!.stroke, blue);
    expect(d.active!.fill, seriesColor);
    expect(probe.props!.payload.single.color, seriesColor);
  });

  testWidgets('the data entry wins over the dot option, and the activeDot option over the data entry', (tester) async {
    // 100x100 without axes: dots at (5, 5) and (95, 27.5).
    Widget chart({int? defaultIndex}) => host(LineChart(width: 100, height: 100, data: data, children: [
          const Line(
              dataKey: 'uv',
              stroke: seriesColor,
              dot: SvgStyle(fill: green, stroke: magenta, strokeWidth: 2),
              activeDot: SvgStyle(fill: green, stroke: magenta),
              isAnimationActive: false),
          if (defaultIndex != null)
            Tooltip(defaultIndex: defaultIndex, isAnimationActive: false, content: (_) => const SizedBox()),
        ]));
    await tester.pumpWidget(chart());
    var image = await capture(tester);
    expect(await pixel(tester, image, const Offset(5, 5)), red);
    // what the data entry does not define still comes from the dot option: stroke-width 2 spans r 2..4
    expect(await pixel(tester, image, const Offset(5, 7)), blue);
    expect(await pixel(tester, image, const Offset(95, 27)), green);

    await tester.pumpWidget(chart(defaultIndex: 0));
    image = await capture(tester);
    expect(await pixel(tester, image, const Offset(5, 5)), green);
  });

  testWidgets('the entry strokeWidth, fillOpacity and r reach the dot', (tester) async {
    final (d, _) = await render(
        tester,
        (d, p) => LineChart(width: 400, height: 300, data: const [
              {'name': 'A', 'uv': 400, 'strokeWidth': 7, 'r': 9},
              {'name': 'B', 'uv': 300},
            ], children: [
              Line(dataKey: 'uv', dot: d.dot, isAnimationActive: false),
            ]));
    expect(d.dots[0]!.strokeWidth, 7);
    expect(d.dots[0]!.r, 9);
    expect(d.dots[1]!.strokeWidth, 1);
    expect(d.dots[1]!.r, 3);
  });

  testWidgets('without entry colors the active dot and the tooltip keep the series colors', (tester) async {
    final (d, probe) = await render(
        tester,
        (d, p) => LineChart(width: 400, height: 300, data: data, children: [
              Line(dataKey: 'uv', stroke: seriesColor, activeDot: d.activeDot, isAnimationActive: false),
              Tooltip(defaultIndex: 1, isAnimationActive: false, content: p.build),
            ]));
    expect(d.active!.fill, seriesColor);
    expect(probe.props!.payload.single.color, seriesColor);
  });
}
