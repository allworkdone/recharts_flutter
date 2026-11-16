// PieChart interactions, ported from Recharts 3.11.0-canary.9 test/polar/Pie/Pie.spec.tsx
// ('Tooltip integration', activeShape / inactiveShape, 'keyboard
// interaction'), Pie-TwoLevelPieChart.spec.tsx and PieChart.spec.tsx, plus
// the entrance timing of Pie.animation.spec.tsx (animationBegin 400) and
// labels hidden while animating.

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/recharts_flutter.dart';

import '../widgets/chart_widget_test.dart' show capture, host, pixel, tooltipBox;
import '../widgets/tooltip_item_test.dart' show Probe, mouseAt;

const sectorsData = [
  {'name': 'A', 'value': 40, 'cy': 250},
  {'name': 'B', 'cy': 250},
  {'name': 'C', 'cy': 250},
  {'cy': 250},
  {'cy': 250},
];

const groupData = [
  {'name': 'Group A', 'value': 400},
  {'name': 'Group B', 'value': 300},
  {'name': 'Group C', 'value': 300},
  {'name': 'Group D', 'value': 200},
];

const red = Color(0xFFFF0000), green = Color(0xFF00FF00), blue = Color(0xFF0000FF), grey = Color(0xFF808080);

/// The center of the sector between [a0] and [a1] degrees at radius [r] around (200, 200).
Offset at(double angle, double r) => Offset(200, 200) + Offset.fromDirection(-angle * 3.141592653589793 / 180, r);

void main() {
  group('Tooltip integration', () {
    // 400x400: center (200, 200), outerRadius 80% of 195; five equal sectors.
    Widget chart(Probe probe, {Object? activeShape, Object? inactiveShape, Object? defaultIndex}) => host(PieChart(
          width: 400,
          height: 400,
          children: [
            Pie(
                isAnimationActive: false,
                data: sectorsData,
                dataKey: 'cy',
                id: 'cy-pie',
                activeShape: activeShape,
                inactiveShape: inactiveShape),
            Tooltip(isAnimationActive: false, content: probe.build, defaultIndex: defaultIndex),
          ],
        ));

    testWidgets('hovering a sector shows its row at the sector center', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(chart(probe));
      expect(probe.visible, isFalse);
      final mouse = await mouseAt(tester, at(36, 80));
      expect(probe.visible, isTrue);
      expect(probe.rows, ['A : 250']);
      expect(probe.props!.label, isNull);
      expect(probe.props!.coordinate, const Offset(263.1033255612459, 154.15275032118709));
      expect(tooltipBox(tester).currentTranslate, const Offset(273.1033255612459, 164.15275032118709));

      await mouse.moveTo(at(108, 80));
      await tester.pump();
      expect(probe.rows, ['B : 250']);

      // mouseLeaveItem
      await mouse.moveTo(const Offset(390, 390));
      await tester.pump();
      expect(probe.visible, isFalse);
      await mouse.removePointer();
    });

    testWidgets('activeShape props are merged over the hovered sector', (tester) async {
      await tester.pumpWidget(chart(Probe(), activeShape: const SectorStyle(fill: red)));
      expect(await pixel(tester, await capture(tester), at(36, 80)), grey);
      final mouse = await mouseAt(tester, at(36, 80));
      final image = await capture(tester);
      expect(await pixel(tester, image, at(36, 80)), red);
      expect(await pixel(tester, image, at(108, 80)), grey);
      await mouse.removePointer();
    });

    testWidgets('inactiveShape only applies while a sector is active', (tester) async {
      await tester.pumpWidget(chart(Probe(), activeShape: const SectorStyle(fill: red), inactiveShape: const SectorStyle(fill: blue)));
      expect(await pixel(tester, await capture(tester), at(108, 80)), grey);
      final mouse = await mouseAt(tester, at(36, 80));
      final image = await capture(tester);
      expect(await pixel(tester, image, at(36, 80)), red);
      expect(await pixel(tester, image, at(108, 80)), blue);
      await mouse.removePointer();
    });

    testWidgets('a grown active shape keeps the pointer, stroke included', (tester) async {
      await tester.pumpWidget(chart(Probe(), activeShape: const SectorStyle(outerRadius: 170, stroke: red, strokeWidth: 4)));
      final mouse = await mouseAt(tester, at(36, 80));
      // Beyond the grown fill (170), on its stroke (to 172): the sector stays active.
      await mouse.moveTo(at(36, 171.5));
      await tester.pump();
      expect(await pixel(tester, await capture(tester), at(36, 165)), grey);
      await mouse.moveTo(at(36, 173));
      await tester.pump();
      expect(await pixel(tester, await capture(tester), at(36, 165)), const Color(0x00000000));
      await mouse.removePointer();
    });

    testWidgets("defaultIndex '1' as a String shows the second sector", (tester) async {
      final probe = Probe();
      await tester.pumpWidget(chart(probe, defaultIndex: '1'));
      expect(probe.rows, ['B : 250']);
      expect(probe.props!.activeIndex, 1);
    });

    testWidgets('defaultIndex shows the first Pie; focus and arrows move between sectors', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(chart(probe, defaultIndex: 1));
      expect(probe.rows, ['B : 250']);
      // A tap outside the sectors focuses the chart: keyboard tooltip at index 0.
      await tester.tapAt(const Offset(390, 390));
      await tester.pump();
      expect(probe.rows, ['A : 250']);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(probe.rows, ['B : 250']);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(probe.rows, ['C : 250']);
      final c = probe.props!.coordinate!, expected = sectorCenter(2);
      expect(c.dx, closeTo(expected.dx, 1e-9));
      expect(c.dy, closeTo(expected.dy, 1e-9));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(probe.rows, ['A : 250']);
      // Past the first sector the keys do nothing.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(probe.rows, ['A : 250']);
    });
  });

  testWidgets('label text above a sector takes the pointer, like SVG text', (tester) async {
    final probe = Probe();
    await tester.pumpWidget(host(PieChart(width: 400, height: 400, children: [
      const Pie(isAnimationActive: false, data: sectorsData, dataKey: 'cy', children: [LabelList(dataKey: 'name')]),
      Tooltip(isAnimationActive: false, content: probe.build),
    ])));
    // LabelList 'middle': the name at the sector's middle radius.
    final mouse = await mouseAt(tester, const Offset(263, 154));
    expect(probe.visible, isFalse);
    await mouse.moveTo(at(36, 120));
    await tester.pump();
    expect(probe.rows, ['A : 250']);
    await mouse.removePointer();
  });

  testWidgets('TwoLevelPieChart: only the hovered Pie shows its active shape', (tester) async {
    final active = <String>[];
    void shape(String name) => active.add(name);
    PieShapePainter activeShape(String name) => (canvas, props) {
          if (props.isActive) shape('$name${props.index}');
        };
    await tester.pumpWidget(host(PieChart(width: 400, height: 400, children: [
      Pie(isAnimationActive: false, activeShape: activeShape('inner'), data: groupData, outerRadius: 80),
      Pie(isAnimationActive: false, activeShape: activeShape('outer'), data: groupData, innerRadius: 100, outerRadius: 140),
    ])));
    expect(active, isEmpty);
    final mouse = await mouseAt(tester, at(10, 120));
    expect(active.toSet(), {'outer0'});
    active.clear();
    await mouse.moveTo(at(10, 40));
    await tester.pump();
    expect(active.toSet(), {'inner0'});
    active.clear();
    await mouse.moveTo(const Offset(5, 395));
    await tester.pump();
    expect(active, isEmpty);
    await mouse.removePointer();
  });

  testWidgets('the entrance waits animationBegin, then sweeps; labels show at the end', (tester) async {
    var started = 0, ended = 0;
    await tester.pumpWidget(host(PieChart(width: 400, height: 400, children: [
      Pie(
        data: groupData,
        outerRadius: 100,
        label: true,
        children: const [Cell(fill: red), Cell(fill: green), Cell(fill: blue), Cell(fill: red)],
        onAnimationStart: () => started++,
        onAnimationEnd: () => ended++,
      ),
    ])));
    await tester.pump(const Duration(milliseconds: 390));
    expect(started, 1);
    // Still in animationBegin: nothing drawn.
    expect(await pixel(tester, await capture(tester), at(30, 50)), const Color(0x00000000));
    await tester.pump(const Duration(milliseconds: 10)); // ACTIVE
    await tester.pump(const Duration(milliseconds: 750)); // half way, 'ease'
    final image = await capture(tester);
    expect(await pixel(tester, image, at(30, 50)), red);
    // Half way the sweep has reached ease(0.5) * 360 = 289 degrees.
    expect(await pixel(tester, image, at(320, 50)), const Color(0x00000000));
    // The label line of Group A (stroke = sector fill) is not drawn yet.
    expect((await pixel(tester, image, at(60, 110))).a, 0);
    await tester.pump(const Duration(milliseconds: 800));
    expect(ended, 1);
    final done = await capture(tester);
    expect(await pixel(tester, done, at(320, 50)), red);
    expect(await pixel(tester, done, at(250, 50)), blue);
    expect((await pixel(tester, done, at(60, 110))).a, greaterThan(0));
  });

  testWidgets('Legend lists every sector; a hidden Pie keeps its legend and draws nothing', (tester) async {
    await tester.pumpWidget(host(const PieChart(width: 400, height: 400, children: [
      Pie(isAnimationActive: false, hide: true, data: groupData, fill: red),
      Legend(),
    ])));
    for (final name in ['Group A', 'Group B', 'Group C', 'Group D']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(await pixel(tester, await capture(tester), const Offset(200, 190)), const Color(0x00000000));
  });

  testWidgets('touch: a finger over a sector activates it, elsewhere nothing changes', (tester) async {
    final probe = Probe();
    await tester.pumpWidget(host(PieChart(width: 400, height: 400, children: [
      const Pie(isAnimationActive: false, data: sectorsData, dataKey: 'cy'),
      Tooltip(isAnimationActive: false, content: probe.build),
    ])));
    final finger = await tester.startGesture(const Offset(390, 390), kind: PointerDeviceKind.touch);
    await finger.moveTo(at(36, 80));
    await tester.pump();
    expect(probe.rows, ['A : 250']);
    await finger.moveTo(const Offset(390, 380));
    await tester.pump();
    expect(probe.rows, ['A : 250']);
    await finger.up();
  });

  // Pie.theme.spec.tsx 'keeps only the entry color on the label line and the label text'
  testWidgets('a label line takes the entry color but not its strokeWidth', (tester) async {
    await tester.pumpWidget(host(const PieChart(width: 400, height: 400, children: [
      Pie(isAnimationActive: false, label: true, data: [
        {'name': 'A', 'value': 100, 'fill': red, 'strokeWidth': 7},
        {'name': 'B', 'value': 100},
      ]),
    ])));
    // Sector A spans 0..180 degrees: its label line runs straight up at x = 200, from radius 156 to 176.
    final image = await capture(tester);
    final onLine = await pixel(tester, image, const Offset(200, 34));
    expect(onLine.a, greaterThan(0));
    expect(onLine.r, greaterThan(onLine.g));
    expect((await pixel(tester, image, const Offset(202, 34))).a, 0);
  });
}

/// Tooltip position of the i-th of five equal sectors of the 400x400 chart.
Offset sectorCenter(int i) {
  final mid = 72.0 * i + 36;
  return Offset(200, 200) + Offset.fromDirection(-mid * 3.141592653589793 / 180, 156 / 2);
}
