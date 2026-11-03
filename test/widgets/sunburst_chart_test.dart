// SunburstChart, ported from Recharts 3.10.1 test/chart/SunburstChart.spec.tsx
// (exampleSunburstData from test/_data.ts): sector fills in order, hover and
// click callbacks with the node and its tooltipIndex, the item tooltip state
// (hover at {x: 583.33.., y: 250} on a 1000x500 chart; click state surviving
// mouseleave), plus the geometry drawArcs produces.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/recharts_flutter.dart';
import 'package:recharts_flutter/src/sunburst.dart';

import 'chart_widget_test.dart' show host, tooltipBox;
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

  testWidgets('a root without a value renders without throwing', (tester) async {
    await tester.pumpWidget(host(SunburstChart(width: 500, height: 500, data: {
      'name': 'Root',
      'children': [
        {'name': 'a', 'value': 1}
      ]
    })));
    expect(tester.takeException(), isNull);
  });

  testWidgets("defaultIndex is a lodash path into data.children; the coordinate is positions[String(index)], so the box sits at (0,0)", (tester) async {
    Future<Probe> show(Object index) async {
      final probe = Probe();
      await tester.pumpWidget(host(SunburstChart(
          width: 500,
          height: 500,
          data: exampleSunburstData(),
          children: [Tooltip(isAnimationActive: false, defaultIndex: index, content: probe.build)])));
      return probe;
    }

    var probe = await show('[0]');
    expect(probe.rows, ['Child1 : 30']);
    expect(probe.props!.activeIndex, '[0]');
    expect(probe.props!.coordinate, isNull);
    probe = await show('[0]children[0]');
    expect(probe.rows, ['third child : 10']);
    // payloadSearcher is lodash get(data.children, index): '0' is the first child.
    probe = await show(0);
    expect(probe.rows, ['Child1 : 30']);
    expect(probe.props!.coordinate, isNull);
    probe = await show('1.children[0]');
    expect(probe.rows, ['another child : 10']);
    probe = await show(7);
    expect(probe.props!.active, isTrue);
    expect(probe.props!.payload, isEmpty);
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
    // Inside Child1's sector: 54 degrees at radius 83.3 around (250, 250).
    const p = Offset(299, 183);
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
      const p = Offset(549, 183);
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
      const inner = Offset(549, 183);
      final mouse = await mouseAt(tester, const Offset(2, 2));
      await mouse.moveTo(inner);
      await tester.pump();
      expect(probe.rows, ['Child1 : 30']);
      // 'third child' is the second ring, 0..36 degrees
      const outer = Offset(645, 203);
      await mouse.moveTo(outer);
      await tester.pump();
      expect(probe.rows, ['third child : 10']);
      await mouse.moveTo(const Offset(2, 2));
      await tester.pump();
      expect(probe.visible, isFalse);
    });
  });

  group('Tooltip.visibility / Tooltip.payload specs for SunburstChart', () {
    Widget chart(Probe probe, {bool? active}) => host(SunburstChart(
          width: 400,
          height: 400,
          data: exampleSunburstData(),
          children: [Tooltip(isAnimationActive: false, content: probe.build, active: active)],
        ));
    // 400x400: Child1 at 54 degrees, radius 75 around (200, 200).
    const child1 = Offset(244, 139), child1Moved = Offset(260, 160), away = Offset(2, 2);

    testWidgets('the box sits at coordinate (275, 200) plus offset 10 and does not move with the mouse', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(chart(probe));
      final mouse = await mouseAt(tester, away);
      await mouse.moveTo(child1);
      await tester.pump();
      expect(probe.props!.coordinate, const Offset(275, 200));
      expect(tooltipBox(tester).targetTranslate, const Offset(285, 210));
      await mouse.moveTo(child1Moved);
      await tester.pump();
      expect(tooltipBox(tester).targetTranslate, const Offset(285, 210));
    });

    testWidgets('empty title, one row "Child1 : 30"', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(chart(probe));
      final mouse = await mouseAt(tester, away);
      await mouse.moveTo(child1);
      await tester.pump();
      expect(probe.props!.label, isNull);
      expect(probe.rows, ['Child1 : 30']);
    });

    testWidgets('active=true keeps the tooltip after the pointer leaves, with the old index and coordinate', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(chart(probe, active: true));
      expect(probe.visible, isFalse);
      final mouse = await mouseAt(tester, away);
      await mouse.moveTo(child1);
      await tester.pump();
      expect(probe.visible, isTrue);
      await mouse.moveTo(away);
      await tester.pump();
      expect(probe.visible, isTrue);
      expect(probe.rows, ['Child1 : 30']);
      expect(probe.props!.coordinate, const Offset(275, 200));
    });

    testWidgets('active=false never shows it', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(chart(probe, active: false));
      final mouse = await mouseAt(tester, away);
      await mouse.moveTo(child1);
      await tester.pump();
      expect(probe.visible, isFalse);
    });

    testWidgets('active=null shows it only while over a sector', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(chart(probe));
      expect(probe.visible, isFalse);
      final mouse = await mouseAt(tester, away);
      await mouse.moveTo(child1);
      await tester.pump();
      expect(probe.visible, isTrue);
      await mouse.moveTo(away);
      await tester.pump();
      expect(probe.visible, isFalse);
    });
  });

  testWidgets('a label takes the pointer from its sector unless pointerEvents is none', (tester) async {
    final left = <Object?>[];
    Widget chart(SunburstTextOptions o) => host(SunburstChart(
          width: 400,
          height: 400,
          data: exampleSunburstData(),
          textOptions: o,
          onMouseLeave: (n, e) => left.add(n['name']),
        ));
    // Child1's label is centered at 54 degrees, radius 75: (244.1, 139.3).
    const sector = Offset(244, 139), edge = Offset(262, 175);
    await tester.pumpWidget(chart(const SunburstTextOptions(fill: Color(0xFF000000))));
    final mouse = await mouseAt(tester, const Offset(2, 2));
    await mouse.moveTo(edge);
    await tester.pump();
    await mouse.moveTo(sector);
    await tester.pump();
    expect(left, ['Child1']);

    left.clear();
    await tester.pumpWidget(chart(SunburstTextOptions.defaults));
    await mouse.moveTo(edge);
    await tester.pump();
    await mouse.moveTo(sector);
    await tester.pump();
    expect(left, isEmpty);
  });
}
