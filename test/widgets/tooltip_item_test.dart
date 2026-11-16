// Tooltip `shared={false}` (tooltip event type 'item') and Bar `activeBar`,
// ported from Recharts 3.10.1 test/component/Tooltip/tooltipEventType.spec.tsx,
// Tooltip.payload.spec.tsx, test/state/selectors/selectActiveTooltipIndex.spec.tsx,
// test/cartesian/Bar/Bar.spec.tsx ("mouse interactions in stacked bar") and
// test/chart/BarChart.spec.tsx (activeBar), plus touch, keyboard and syncId
// checks against tooltipSlice.ts / touchEventsMiddleware.ts, and test/component/Tooltip/Tooltip.sync.spec.tsx.

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/recharts_flutter.dart';

import 'chart_widget_test.dart' show capture, host, pixel, tooltipBox;

const pageData = [
  {'name': 'Page A', 'uv': 400, 'pv': 2400, 'amt': 2400},
  {'name': 'Page B', 'uv': 300, 'pv': 4567, 'amt': 2400},
  {'name': 'Page C', 'uv': 300, 'pv': 1398, 'amt': 2400},
  {'name': 'Page D', 'uv': 200, 'pv': 9800, 'amt': 2400},
  {'name': 'Page E', 'uv': 278, 'pv': 3908, 'amt': 2400},
  {'name': 'Page F', 'uv': 189, 'pv': 4800, 'amt': 2400},
];

const red = Color(0xFFFF0000);
const black = Color(0xFF000000);

/// A 10x10 tooltip content (Recharts' mocked bounding box) that records its props.
class Probe {
  TooltipContentProps? props;
  Widget build(TooltipContentProps p) {
    props = p;
    return const SizedBox.square(dimension: 10);
  }

  bool get visible => props!.active && props!.payload.isNotEmpty;
  List<String> get rows => [for (final e in props!.payload) '${e.name} : ${e.value}${e.unit ?? ''}'];
}

Future<TestGesture> mouseAt(WidgetTester tester, Offset p) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: p);
  await tester.pump();
  return mouse;
}

Future<void> click(WidgetTester tester, TestGesture mouse, Offset p) async {
  await mouse.moveTo(p);
  await mouse.down(p);
  await mouse.up();
  await tester.pump();
}

void main() {
  group('stacked bars with activeBar (Bar.spec: mouse interactions in stacked bar)', () {
    // Bars: x = 14,65 72x30 (dataKey x), 14,5 72x60 (dataKey y).
    Widget chart(Probe probe, {bool? shared}) => host(BarChart(width: 100, height: 100, data: const [
          {'x': 1, 'y': 2},
        ], children: [
          const Bar(dataKey: 'x', stackId: '1', activeBar: SvgStyle(fill: red), isAnimationActive: false),
          const Bar(dataKey: 'y', stackId: '1', activeBar: SvgStyle(fill: red), isAnimationActive: false),
          Tooltip(shared: shared, isAnimationActive: false, content: probe.build),
        ]));

    testWidgets('shared=false: the hovered bar alone is active, the tooltip sticks to its center', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(chart(probe, shared: false));
      expect(probe.props!.activeIndex, isNull);
      var image = await capture(tester);
      expect(await pixel(tester, image, const Offset(50, 80)), black);

      final mouse = await mouseAt(tester, const Offset(99, 99));
      await mouse.moveTo(const Offset(50, 80));
      await tester.pump();
      expect(probe.props!.activeIndex, 0);
      expect(probe.rows, ['x : 1']);
      expect(probe.props!.label, isNull);
      expect(probe.props!.coordinate, const Offset(50, 80));
      expect(tooltipBox(tester).targetTranslate, const Offset(60, 60));
      image = await capture(tester);
      expect(await pixel(tester, image, const Offset(50, 80)), red);
      expect(await pixel(tester, image, const Offset(50, 35)), black);

      // the tooltip sticks to the item, not to the mouse
      await mouse.moveTo(const Offset(30, 90));
      await tester.pump();
      expect(tooltipBox(tester).targetTranslate, const Offset(60, 60));

      await mouse.moveTo(const Offset(50, 35));
      await tester.pump();
      expect(probe.rows, ['y : 2']);
      expect(tooltipBox(tester).targetTranslate!.dx, 60);
      expect(tooltipBox(tester).targetTranslate!.dy, closeTo(45, 1e-9));
      image = await capture(tester);
      expect(await pixel(tester, image, const Offset(50, 80)), black);
      expect(await pixel(tester, image, const Offset(50, 35)), red);
    });

    testWidgets('shared=true: hovering the chart makes both bars active', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(chart(probe, shared: true));
      final mouse = await mouseAt(tester, const Offset(99, 99));
      await mouse.moveTo(const Offset(10, 10));
      await tester.pump();
      expect(probe.props!.activeIndex, 0);
      expect(probe.props!.label, 0);
      expect(probe.rows, ['x : 1', 'y : 2']);
      expect(tooltipBox(tester).targetTranslate, const Offset(60, 20));
      final image = await capture(tester);
      expect(await pixel(tester, image, const Offset(50, 80)), red);
      expect(await pixel(tester, image, const Offset(50, 35)), red);
    });
  });

  group('tooltipEventType item in BarChart (tooltipEventType.spec)', () {
    // 500x500, uv only: bar 0 is x 13.3..78.3 full height, bar 1 x 95..160 from y 127.5.
    const onBar0 = Offset(40, 300), empty = Offset(130, 60);
    Widget chart(Probe probe, {TooltipTrigger trigger = TooltipTrigger.hover, Object background = false}) =>
        host(BarChart(width: 500, height: 500, data: pageData, children: [
          Bar(dataKey: 'uv', isAnimationActive: false, background: background),
          Tooltip(shared: false, trigger: trigger, content: probe.build),
        ]));

    for (final trigger in TooltipTrigger.values) {
      testWidgets('trigger=${trigger.name}: no tooltip before interaction nor on the chart area', (tester) async {
        final probe = Probe();
        await tester.pumpWidget(chart(probe, trigger: trigger));
        expect(probe.visible, isFalse);
        final mouse = await mouseAt(tester, const Offset(499, 499));
        await click(tester, mouse, empty);
        expect(probe.visible, isFalse);
        await mouse.moveTo(const Offset(200, 60));
        await tester.pump();
        expect(probe.visible, isFalse);
      });
    }

    testWidgets('trigger=hover: hovering a bar shows its tooltip, leaving it hides it', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(chart(probe));
      final mouse = await mouseAt(tester, const Offset(499, 499));
      await mouse.moveTo(onBar0);
      await tester.pump();
      expect(probe.visible, isTrue);
      expect(probe.rows, ['uv : 400']);
      await mouse.moveTo(empty);
      await tester.pump();
      expect(probe.visible, isFalse);
      // no cursor in item mode
      final image = await capture(tester);
      expect(await pixel(tester, image, const Offset(30, 200)), black);
      expect(await pixel(tester, image, const Offset(8, 200)), const Color(0x00000000));
    });

    testWidgets('the bar background is a hover target too', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(chart(probe, background: const SvgStyle(stroke: red)));
      final mouse = await mouseAt(tester, const Offset(499, 499));
      await mouse.moveTo(empty);
      await tester.pump();
      expect(probe.visible, isTrue);
      expect(probe.rows, ['uv : 300']);
      // the tooltip goes to the bar's center, not the background's
      expect(probe.props!.coordinate!.dy, closeTo((127.5 + 495) / 2, 1e-9));
      await mouse.moveTo(const Offset(87, 60));
      await tester.pump();
      expect(probe.visible, isFalse);
    });

    testWidgets('trigger=click: a click on a bar shows it and it stays through clicks and mouse leave',
        (tester) async {
      final probe = Probe();
      await tester.pumpWidget(chart(probe, trigger: TooltipTrigger.click));
      final mouse = await mouseAt(tester, const Offset(499, 499));
      await mouse.moveTo(onBar0);
      await tester.pump();
      expect(probe.visible, isFalse);
      await click(tester, mouse, onBar0);
      expect(probe.visible, isTrue);
      await click(tester, mouse, onBar0);
      expect(probe.visible, isTrue);
      await mouse.moveTo(empty);
      await tester.pump();
      expect(probe.visible, isTrue);
      await mouse.moveTo(const Offset(700, 550));
      await tester.pump();
      expect(probe.visible, isTrue);
      expect(probe.rows, ['uv : 400']);
      // clicking the chart area keeps it; clicking another bar moves it
      await click(tester, mouse, empty);
      expect(probe.rows, ['uv : 400']);
      await click(tester, mouse, const Offset(120, 300));
      expect(probe.rows, ['uv : 300']);
    });

    testWidgets('a press on one bar released on another is no item click', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(chart(probe, trigger: TooltipTrigger.click));
      final mouse = await mouseAt(tester, onBar0);
      await mouse.down(onBar0);
      await mouse.moveTo(const Offset(120, 300));
      await mouse.up();
      await tester.pump();
      expect(probe.visible, isFalse);
    });
  });

  group('payload and active index (Tooltip.payload.spec, selectActiveTooltipIndex.spec)', () {
    testWidgets('shared=false renders the payload of the hovered Bar only, without a label', (tester) async {
      // 400x400: bars of index 0 are uv x 11..26, pv x 30..45, amt x 49..64.
      await tester.pumpWidget(host(const BarChart(width: 400, height: 400, data: pageData, children: [
        Bar(dataKey: 'uv', unit: 'kg', isAnimationActive: false),
        Bar(dataKey: 'pv', unit: r'$$$', name: 'My custom name', isAnimationActive: false),
        Bar(dataKey: 'amt', unit: '', isAnimationActive: false),
        Tooltip(shared: false, isAnimationActive: false),
      ])));
      final mouse = await mouseAt(tester, const Offset(399, 399));
      await mouse.moveTo(const Offset(18, 390));
      await tester.pump();
      expect(find.text('uv : 400kg', findRichText: true), findsOneWidget);
      expect(find.text('0'), findsNothing);
      await mouse.moveTo(const Offset(37, 350));
      await tester.pump();
      expect(find.text(r'My custom name : 2400$$$', findRichText: true), findsOneWidget);
      expect(find.text('uv : 400kg', findRichText: true), findsNothing);
    });

    testWidgets('activeIndex: hover index, null after leaving; defaultIndex before any hover', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(host(BarChart(width: 500, height: 500, data: pageData, children: [
        const Bar(dataKey: 'uv', isAnimationActive: false),
        Tooltip(shared: false, defaultIndex: 3, content: probe.build),
      ])));
      expect(probe.props!.activeIndex, 3);
      expect(probe.rows, ['uv : 200']);
      final mouse = await mouseAt(tester, const Offset(499, 499));
      await mouse.moveTo(const Offset(40, 300));
      await tester.pump();
      expect(probe.props!.activeIndex, 0);
      await mouse.moveTo(const Offset(130, 60));
      await tester.pump();
      expect(probe.props!.activeIndex, isNull);
    });
  });

  group('activeBar (BarChart.spec)', () {
    // 700x200, one bar per category: bar 0 is x 16.5..108.5, y 5..195.
    Future<Color> barColorWhileHovering(WidgetTester tester, Object activeBar) async {
      await tester.pumpWidget(host(BarChart(width: 700, height: 200, data: pageData, children: [
        Bar(
            dataKey: 'uv',
            stackId: 'test',
            fill: const Color(0xFFFF7300),
            activeBar: activeBar,
            isAnimationActive: false),
        const Tooltip(),
      ])));
      final mouse = await mouseAt(tester, const Offset(699, 199));
      await mouse.moveTo(const Offset(100, 100));
      await tester.pump();
      return pixel(tester, await capture(tester), const Offset(60, 150));
    }

    testWidgets('no active bar by default or with activeBar false', (tester) async {
      expect(await barColorWhileHovering(tester, false), const Color(0xFFFF7300));
    });

    testWidgets('activeBar true renders the bar shape itself', (tester) async {
      expect(await barColorWhileHovering(tester, true), const Color(0xFFFF7300));
    });

    testWidgets('an activeBar object is merged over the bar props', (tester) async {
      expect(await barColorWhileHovering(tester, const SvgStyle(strokeWidth: 4, fill: Color(0xFF008000))),
          const Color(0xFF008000));
    });

    testWidgets('the active bar is drawn above the axis line and stays there after the tooltip hides',
        (tester) async {
      const blue = Color(0xFF0000FF), orange = Color(0xFFFF7300), green = Color(0xFF008000);
      // plot bottom y = 165; the 6px axis line covers 162..168
      await tester.pumpWidget(host(const BarChart(width: 700, height: 200, data: pageData, children: [
        XAxis(dataKey: 'name', axisLine: SvgStyle(stroke: blue, strokeWidth: 6)),
        Bar(dataKey: 'uv', fill: orange, activeBar: SvgStyle(fill: green), isAnimationActive: false),
        Tooltip(),
      ])));
      Future<Color> at(Offset p) async => pixel(tester, await capture(tester), p);
      const bar0Base = Offset(60, 163.5), bar5Base = Offset(637, 163.5);
      expect(await at(bar0Base), blue);
      final mouse = await mouseAt(tester, const Offset(699, 199));
      await mouse.moveTo(const Offset(100, 100));
      await tester.pump();
      expect(await at(bar0Base), green);
      await mouse.moveTo(const Offset(600, 100));
      await tester.pump();
      expect(await at(bar0Base), blue);
      expect(await at(bar5Base), green);
      await mouse.moveTo(const Offset(800, 300));
      await tester.pump();
      expect(await at(bar5Base), orange);
    });
  });

  group('touch', () {
    const onBar0 = Offset(40, 300), onBar1 = Offset(120, 300), onBar2 = Offset(200, 300), empty = Offset(130, 60);
    Widget chart(Probe probe, {TooltipTrigger trigger = TooltipTrigger.hover}) =>
        host(BarChart(width: 500, height: 500, data: pageData, children: [
          const Bar(dataKey: 'uv', isAnimationActive: false),
          Tooltip(shared: false, trigger: trigger, content: probe.build),
        ]));

    testWidgets('a tap on a bar shows its tooltip until another tap leaves it', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(chart(probe));
      await tester.tapAt(onBar0, kind: PointerDeviceKind.touch);
      await tester.pump();
      expect(probe.visible, isTrue);
      expect(probe.rows, ['uv : 400']);
      await tester.tapAt(onBar1, kind: PointerDeviceKind.touch);
      await tester.pump();
      expect(probe.rows, ['uv : 300']);
      await tester.tapAt(empty, kind: PointerDeviceKind.touch);
      await tester.pump();
      expect(probe.visible, isFalse);
    });

    testWidgets('a touch drag across bars does not change the active item', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(chart(probe));
      var finger = await tester.startGesture(onBar0, kind: PointerDeviceKind.touch);
      await finger.moveTo(onBar1);
      await tester.pump();
      expect(probe.visible, isFalse);
      await finger.up();
      await tester.pump();
      expect(probe.visible, isFalse);

      await tester.tapAt(onBar0, kind: PointerDeviceKind.touch);
      await tester.pump();
      finger = await tester.startGesture(onBar1, kind: PointerDeviceKind.touch);
      await finger.moveTo(onBar2);
      await tester.pump();
      await finger.up();
      await tester.pump();
      expect(probe.rows, ['uv : 400']);
    });

    testWidgets('trigger=click: a tap is a click on the bar', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(chart(probe, trigger: TooltipTrigger.click));
      await tester.tapAt(onBar1, kind: PointerDeviceKind.touch);
      await tester.pump();
      expect(probe.visible, isTrue);
      expect(probe.rows, ['uv : 300']);
    });
  });

  testWidgets('LineChart and ComposedChart only allow the axis event type and ignore shared=false', (tester) async {
    await tester.pumpWidget(host(const LineChart(width: 400, height: 300, data: pageData, children: [
      XAxis(dataKey: 'name'),
      Line(dataKey: 'uv'),
      Tooltip(shared: false),
    ])));
    final mouse = await mouseAt(tester, const Offset(399, 299));
    await mouse.moveTo(const Offset(170, 100));
    await tester.pump();
    expect(find.text('Page C'), findsOneWidget);

    await tester.pumpWidget(host(const ComposedChart(width: 400, height: 300, data: pageData, children: [
      XAxis(dataKey: 'name'),
      Bar(dataKey: 'uv', isAnimationActive: false),
      Tooltip(shared: false),
    ])));
    await mouse.moveTo(const Offset(240, 40));
    await tester.pump();
    expect(find.text('Page D'), findsOneWidget);
  });

  testWidgets('keyboard: focus shows the first item, a hover makes later keys show the hovered item',
      (tester) async {
    // 500x500, uv + pv: index 0 has uv x 12.8..43.8 (from y 475.4), pv x 47.8..78.8 (from y 377.4).
    final probe = Probe();
    await tester.pumpWidget(host(BarChart(width: 500, height: 500, data: pageData, children: [
      const Bar(dataKey: 'uv', isAnimationActive: false),
      const Bar(dataKey: 'pv', isAnimationActive: false),
      Tooltip(shared: false, content: probe.build),
    ])));
    // a press outside the plot area focuses the chart: keyboard tooltip at index 0
    final mouse = await mouseAt(tester, const Offset(2, 2));
    await click(tester, mouse, const Offset(2, 2));
    expect(probe.visible, isTrue);
    expect(probe.rows, ['uv : 400']);
    expect(probe.props!.label, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(probe.rows, ['uv : 300']);
    await mouse.moveTo(const Offset(63, 450));
    await tester.pump();
    expect(probe.rows, ['pv : 2400']);
    // setActiveMouseOverItemIndex deactivated the keyboard
    await mouse.moveTo(const Offset(63, 300));
    await tester.pump();
    expect(probe.visible, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(probe.props!.activeIndex, 2);
    expect(probe.rows, ['pv : 1398']);
  });

  testWidgets('syncId: an item hover reaches other charts by index and dataKey', (tester) async {
    // 300x200, uv + pv: index 0 has uv x 10.2..27.2, pv x 31.2..48.2 (from y 149.4).
    const blue = Color(0xFF0000FF), green = Color(0xFF00FF00);
    final a = Probe(), b = Probe();
    Widget chart(Probe probe) => BarChart(width: 300, height: 200, data: pageData, syncId: 'sync', children: [
          const Bar(dataKey: 'uv', fill: blue, activeBar: SvgStyle(fill: red), isAnimationActive: false),
          const Bar(dataKey: 'pv', fill: green, activeBar: SvgStyle(fill: red), isAnimationActive: false),
          Tooltip(shared: false, content: probe.build),
        ]);
    await tester.pumpWidget(host(Column(mainAxisSize: MainAxisSize.min, children: [chart(a), chart(b)])));
    final mouse = await mouseAt(tester, const Offset(299, 199));
    await mouse.moveTo(const Offset(40, 180));
    await tester.pump();
    expect(a.rows, ['pv : 2400']);
    // the receiving chart shows all of its items at the synced index
    expect(b.visible, isTrue);
    expect(b.rows, ['uv : 400', 'pv : 2400']);
    final image = await capture(tester);
    expect(await pixel(tester, image, const Offset(40, 380)), red);
    expect(await pixel(tester, image, const Offset(18, 393)), blue);
    await mouse.moveTo(const Offset(40, 100));
    await tester.pump();
    expect(a.visible, isFalse);
    expect(b.visible, isFalse);
  });

  group('Tooltip.sync.spec.tsx: when a synchronised chart unmounts', () {
    // Three 200x150 LineCharts; points at x = 5, 43, 81, ... An unmounted chart leaves its slot empty.
    String shown(Probe p) => '${p.props!.label}: ${p.rows.join(', ')}';
    Widget charts(List<Probe?> probes, {bool activeA = false}) => host(Column(mainAxisSize: MainAxisSize.min, children: [
          for (final (i, probe) in probes.indexed)
            probe == null
                ? const SizedBox(width: 200, height: 150)
                : LineChart(width: 200, height: 150, data: pageData, syncId: 'unmount-sync', children: [
                    const XAxis(dataKey: 'name'),
                    const Line(dataKey: 'uv', isAnimationActive: false),
                    Tooltip(active: i == 0 && activeA ? true : null, content: probe.build),
                  ]),
        ]));

    testWidgets('hides the tooltip in the other charts when the hovered chart unmounts', (tester) async {
      final a = Probe(), b = Probe(), c = Probe();
      await tester.pumpWidget(charts([a, b, c]));
      final mouse = await mouseAt(tester, const Offset(399, 599));
      await mouse.moveTo(const Offset(85, 50));
      await tester.pump();
      expect(shown(b), 'Page C: uv : 300');

      // the pointer is still over chart A when it goes away, so it never gets a mouseleave
      await tester.pumpWidget(charts([null, b, c]));
      await tester.pump();
      expect(b.visible, isFalse);
      expect(c.visible, isFalse);
    });

    testWidgets('keeps the synchronised tooltip when a chart that only receives it unmounts', (tester) async {
      final a = Probe(), b = Probe(), c = Probe();
      await tester.pumpWidget(charts([a, b, c]));
      final mouse = await mouseAt(tester, const Offset(399, 599));
      await mouse.moveTo(const Offset(85, 50));
      await tester.pump();

      await tester.pumpWidget(charts([a, null, c]));
      await tester.pump();
      expect(shown(a), 'Page C: uv : 300');
      expect(shown(c), 'Page C: uv : 300');
    });

    testWidgets('keeps the tooltip of the current source when a chart that sent one earlier unmounts', (tester) async {
      final a = Probe(), b = Probe(), c = Probe();
      await tester.pumpWidget(charts([a, b, c], activeA: true));
      final mouse = await mouseAt(tester, const Offset(399, 599));
      await mouse.moveTo(const Offset(85, 50));
      await tester.pump();
      await mouse.moveTo(const Offset(399, 50));
      await tester.pump();
      await mouse.moveTo(const Offset(45, 350));
      await tester.pump();
      expect(shown(b), 'Page B: uv : 300');

      await tester.pumpWidget(charts([null, b, c], activeA: true));
      await tester.pump();
      expect(shown(b), 'Page B: uv : 300');
      expect(b.visible, isTrue);
    });
  });

  group('Tooltip.sync.spec.tsx: cursor alignment between charts with different scales', () {
    // A 400x300 LineChart above a BarChart; the cursor rectangle follows the coordinate along the tooltip axis.
    Future<void> expectSameCursor(WidgetTester tester, ChartLayout layout, Offset hover) async {
      final line = Probe(), bar = Probe();
      final vertical = layout == ChartLayout.vertical;
      final axes = vertical
          ? const [XAxis(type: AxisDomainType.number), YAxis(dataKey: 'name', type: AxisDomainType.category)]
          : const [XAxis(dataKey: 'name')];
      await tester.pumpWidget(host(Column(mainAxisSize: MainAxisSize.min, children: [
        LineChart(width: 400, height: 300, layout: layout, data: pageData, syncId: 'alignment', children: [
          ...axes,
          const Line(dataKey: 'uv'),
          Tooltip(content: line.build),
        ]),
        BarChart(width: 400, height: 300, layout: layout, data: pageData, syncId: 'alignment', children: [
          ...axes,
          const Bar(dataKey: 'uv'),
          Tooltip(content: bar.build),
        ]),
      ])));
      double along(Offset c) => vertical ? c.dy : c.dx;
      final mouse = await mouseAt(tester, const Offset(799, 599));
      await mouse.moveTo(hover + const Offset(0, 300));
      await tester.pump();
      expect(bar.props!.label, 'Page D');
      final direct = along(bar.props!.coordinate!);
      await mouse.moveTo(const Offset(799, 599));
      await tester.pump();

      await mouse.moveTo(hover);
      await tester.pump();
      expect(bar.visible, isTrue);
      expect(bar.props!.label, 'Page D');
      expect(along(bar.props!.coordinate!), direct);
    }

    testWidgets('the BarChart cursor is where hovering it directly puts it, synchronised from a LineChart',
        (tester) => expectSameCursor(tester, ChartLayout.horizontal, const Offset(230, 100)));

    testWidgets('the same in vertical charts',
        (tester) => expectSameCursor(tester, ChartLayout.vertical, const Offset(200, 150)));
  });
}
