// SunburstChart, ported from Recharts 3.10.1 test/chart/SunburstChart.spec.tsx
// (exampleSunburstData from test/_data.ts): sector fills in order, hover and
// click callbacks with the node and its tooltipIndex, the item tooltip state
// (hover at {x: 583.33.., y: 250} on a 1000x500 chart; click state surviving
// mouseleave), plus the geometry drawArcs produces.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/recharts_flutter.dart';
import 'package:recharts_flutter/src/sunburst.dart';

import 'chart_widget_test.dart' show host;
import 'tooltip_item_test.dart' show Probe, click, mouseAt;

Map<String, Object?> exampleSunburstData() => {
      'name': 'Root',
      'value': 100,
      'children': [
        {
          'name': 'Child1',
          'fill': const Color(0xFF264653),
          'value': 30,
          'children': [
            {'name': 'third child', 'value': 10},
          ],
        },
        {
          'name': 'Child2',
          'fill': const Color(0xFF2A9D8F),
          'value': 20,
          'children': [
            {'name': 'another child', 'value': 10},
          ],
        },
        {'name': 'Child3', 'fill': const Color(0xFFE9C46A), 'value': 20},
      ],
    };

SunburstLayout layout(double w, double h) => computeSunburst(
      data: exampleSunburstData(),
      width: w,
      height: h,
      dataKey: 'value',
      padding: 2,
      ringPadding: 2,
      innerRadius: 50,
      startAngle: 0,
      endAngle: 360,
      fill: const Color(0xFF333333),
    );

void main() {
  test('renders each sector in order under the correct category', () {
    final fills = [for (final s in layout(500, 500).sectors) s.fill.toARGB32()];
    expect(fills.take(5), [0xFF264653, 0xFF264653, 0xFF2A9D8F, 0xFF2A9D8F, 0xFFE9C46A]);
  });

  test('geometry: depth counts the root, rings are separated by ringPadding', () {
    final l = layout(1000, 500);
    // (250 - 50) / 3 levels
    expect(l.thickness, closeTo(200 / 3, 1e-9));
    final child1 = l.sectors[0], third = l.sectors[1];
    expect([child1.startAngle, child1.endAngle], [0, 108]);
    expect(child1.innerRadius, 50);
    expect(third.innerRadius, closeTo(50 + 200 / 3 + 2, 1e-9));
    expect([third.startAngle, third.endAngle], [0, 36]);
    expect(l.positions['Child1']!.dx, closeTo(583.3333333333334, 1e-9));
    expect(l.positions['Child1']!.dy, closeTo(250, 1e-9));
  });

  testWidgets('fires callbacks upon hover and click events', (tester) async {
    final entered = <Map<String, Object?>>[], left = <Map<String, Object?>>[], clicked = <Map<String, Object?>>[];
    await tester.pumpWidget(host(SunburstChart(
      width: 500,
      height: 500,
      data: exampleSunburstData(),
      onMouseEnter: (n, e) => entered.add(n),
      onMouseLeave: (n, e) => left.add(n),
      onClick: clicked.add,
    )));
    final expected = {
      'name': 'Child1',
      'fill': const Color(0xFF264653),
      'value': 30,
      'children': [
        {'name': 'third child', 'value': 10},
      ],
      'tooltipIndex': '[0]',
    };
    // Child1 sits at 54 degrees, radius 50 + 100 / 3 / 2 of 3 levels.
    final p = const Offset(250, 250) + Offset.fromDirection(-54 * 3.141592653589793 / 180, 50 + 200 / 3 / 2);
    final mouse = await mouseAt(tester, const Offset(2, 2));
    await mouse.moveTo(p);
    await tester.pump();
    expect(entered, [expected]);
    await click(tester, mouse, p);
    expect(clicked, [expected]);
    await mouse.moveTo(const Offset(2, 2));
    await tester.pump();
    expect(left, [expected]);
  });

  group('tooltip state', () {
    testWidgets('hover activates the item, click survives mouseleave', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(host(SunburstChart(
        width: 1000,
        height: 500,
        data: exampleSunburstData(),
        children: [Tooltip(isAnimationActive: false, content: probe.build, trigger: TooltipTrigger.click)],
      )));
      expect(probe.visible, isFalse);
      final p = const Offset(500, 250) + Offset.fromDirection(-54 * 3.141592653589793 / 180, 50 + 200 / 3 / 2);
      final mouse = await mouseAt(tester, const Offset(2, 2));
      await mouse.moveTo(p);
      await tester.pump();
      // trigger "click": hovering alone shows nothing
      expect(probe.visible, isFalse);
      await click(tester, mouse, p);
      expect(probe.visible, isTrue);
      expect(probe.rows, ['Child1 : 30']);
      expect(probe.props!.coordinate!.dx, closeTo(583.3333333333334, 1e-9));
      expect(probe.props!.coordinate!.dy, closeTo(250, 1e-9));
      await mouse.moveTo(const Offset(2, 2));
      await tester.pump();
      expect(probe.visible, isTrue);
    });

    testWidgets('hover tooltip follows the hovered sector and hides on leave', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(host(SunburstChart(
        width: 1000,
        height: 500,
        data: exampleSunburstData(),
        children: [Tooltip(isAnimationActive: false, content: probe.build)],
      )));
      final inner = const Offset(500, 250) + Offset.fromDirection(-54 * 3.141592653589793 / 180, 50 + 200 / 3 / 2);
      final mouse = await mouseAt(tester, const Offset(2, 2));
      await mouse.moveTo(inner);
      await tester.pump();
      expect(probe.rows, ['Child1 : 30']);
      // 'third child' is the second ring, 0..36 degrees
      final outer = const Offset(500, 250) + Offset.fromDirection(-18 * 3.141592653589793 / 180, 50 + 200 / 3 * 1.5 + 2);
      await mouse.moveTo(outer);
      await tester.pump();
      expect(probe.rows, ['third child : 10']);
      await mouse.moveTo(const Offset(2, 2));
      await tester.pump();
      expect(probe.visible, isFalse);
    });
  });
}
