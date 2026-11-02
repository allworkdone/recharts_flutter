// RadarChart and RadialBarChart tooltips and keyboard through the widgets,
// following component/Tooltip/Tooltip.payload.spec.tsx (polar cases).

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/recharts_flutter.dart';

import '../widgets/chart_widget_test.dart' show host;
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
}
