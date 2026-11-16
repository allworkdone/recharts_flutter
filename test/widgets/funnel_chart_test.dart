// FunnelChart tooltip (event type 'item', funnelChartMouseHoverTooltipSelector in Recharts'
// tests) and activeShape, ported from Funnel.spec.tsx.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/recharts_flutter.dart';

import 'chart_widget_test.dart' show capture, host, pixel;
import 'tooltip_item_test.dart' show Probe, mouseAt;

const data = [
  {'value': 100, 'name': 'a'},
  {'value': 80, 'name': 'b'},
  {'value': 50, 'name': 'c'},
  {'value': 40, 'name': 'd'},
  {'value': 26, 'name': 'e'},
];

void main() {
  Widget chart(Probe probe, {Object? activeShape, Object? defaultIndex}) =>
      host(FunnelChart(width: 500, height: 500, children: [
        Funnel(dataKey: 'value', data: data, isAnimationActive: false, activeShape: activeShape),
        Tooltip(isAnimationActive: false, content: probe.build, defaultIndex: defaultIndex),
      ]));

  testWidgets('hovering a trapezoid shows its row; leaving hides it', (tester) async {
    final probe = Probe();
    await tester.pumpWidget(chart(probe));
    expect(probe.visible, isFalse);
    // Row height 98; the third trapezoid spans y 201..299.
    final mouse = await mouseAt(tester, const Offset(499, 499));
    await mouse.moveTo(const Offset(250, 250));
    await tester.pump();
    expect(probe.visible, isTrue);
    expect(probe.rows, ['c : 50']);
    expect(probe.props!.activeIndex, 2);
    expect(probe.props!.label, isNull);
    // tooltipPosition: x + upperWidth / 2, y + rowHeight / 2.
    expect(probe.props!.coordinate, const Offset(250, 250));
    await mouse.moveTo(const Offset(2, 250));
    await tester.pump();
    expect(probe.visible, isFalse);
  });

  testWidgets('activeShape paints over the hovered trapezoid only', (tester) async {
    final probe = Probe();
    await tester.pumpWidget(chart(probe, activeShape: const SvgStyle(fill: Color(0xFFFF0000))));
    var image = await capture(tester);
    expect(await pixel(tester, image, const Offset(250, 250)), const Color(0xFF808080));
    final mouse = await mouseAt(tester, const Offset(499, 499));
    await mouse.moveTo(const Offset(250, 250));
    await tester.pump();
    image = await capture(tester);
    expect(await pixel(tester, image, const Offset(250, 250)), const Color(0xFFFF0000));
    expect(await pixel(tester, image, const Offset(250, 150)), const Color(0xFF808080));
  });

  // Funnel.spec.tsx 'should render active shape for the Tooltip defaultIndex'
  testWidgets('Tooltip defaultIndex draws the activeShape over that trapezoid', (tester) async {
    final probe = Probe();
    await tester.pumpWidget(chart(probe, activeShape: const SvgStyle(fill: Color(0xFFFF0000)), defaultIndex: 1));
    expect(probe.rows, ['b : 80']);
    final image = await capture(tester);
    expect(await pixel(tester, image, const Offset(250, 150)), const Color(0xFFFF0000));
    expect(await pixel(tester, image, const Offset(250, 250)), const Color(0xFF808080));
  });
}
