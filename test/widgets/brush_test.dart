// Brush interaction, ported from Recharts 3.10.1 test/cartesian/Brush.spec.tsx
// (traveller geometry, drag snapping, texts, keyboard, controlled indexes) plus
// Flutter-side input checks (touch, scroll views, leave timer, animation).


import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/recharts_flutter.dart';
import 'package:recharts_flutter/src/widgets/brush.dart';

import 'chart_widget_test.dart' show capture, host, pixel;

const data = [
  {'date': '2023-01-01', 'value': 10, 'name': 'A'},
  {'date': '2023-01-02', 'value': 20, 'name': 'B'},
  {'date': '2023-01-03', 'value': 10, 'name': 'C'},
  {'date': '2023-01-04', 'value': 30, 'name': 'D'},
  {'date': '2023-01-05', 'value': 50, 'name': 'E'},
  {'date': '2023-01-06', 'value': 10, 'name': 'F'},
  {'date': '2023-01-07', 'value': 30, 'name': 'G'},
  {'date': '2023-01-08', 'value': 20, 'name': 'H'},
  {'date': '2023-01-09', 'value': 10, 'name': 'I'},
  {'date': '2023-01-10', 'value': 70, 'name': 'J'},
  {'date': '2023-01-11', 'value': 40, 'name': 'K'},
  {'date': '2023-01-12', 'value': 20, 'name': 'L'},
  {'date': '2023-01-13', 'value': 10, 'name': 'M'},
  {'date': '2023-01-14', 'value': 10, 'name': 'N'},
];

BrushLayerState brushState(WidgetTester tester) => tester.state<BrushLayerState>(find.byType(BrushLayer));
BrushLayer brushLayer(WidgetTester tester) => tester.widget<BrushLayer>(find.byType(BrushLayer));

/// `<BarChart width={400} height={100}><Brush x={100} y={50} width={400} height={40} /></BarChart>`:
/// travellers at x 100 and 495, y 50..90.
Widget simpleBrush({
  Brush brush = const Brush(dataKey: 'value', x: 100, y: 50, width: 400, height: 40),
  double width = 400,
}) =>
    host(BarChart(width: width, height: 100, data: data, children: [brush]));

Future<TestGesture> mouseAt(WidgetTester tester, Offset p) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: p);
  await tester.pump();
  return mouse;
}

void main() {
  testWidgets('Render 2 travellers and 1 slide in simple Brush', (tester) async {
    await tester.pumpWidget(simpleBrush());
    final s = brushState(tester);
    expect(brushLayer(tester).rect, const Rect.fromLTWH(100, 50, 400, 40));
    expect([s.startX, s.endX], [100, 495]);
    expect(s.textVisible, isFalse);
    expect(s.ariaLabel, 'Min value: A, Max value: N');

    final image = await capture(tester);
    // DefaultTraveller: rect filled with stroke #666, white lines at y 69 and 71.
    expect(await pixel(tester, image, const Offset(102, 55)), const Color(0xFF666666));
    expect(await pixel(tester, image, const Offset(102, 69)), isNot(const Color(0xFF666666)));
    expect(await pixel(tester, image, const Offset(104, 85)), const Color(0xFF666666));
    // Slide: #666 at 0.2 opacity over the white background.
    final slide = await pixel(tester, image, const Offset(300, 70));
    expect(slide.r, closeTo((0xFF * 0.8 + 0x66 * 0.2) / 255, 0.01));
  });

  testWidgets('custom traveller receives x, y, width, height, fill and stroke', (tester) async {
    final calls = <BrushTravellerProps>[];
    await tester.pumpWidget(simpleBrush(
      brush: Brush(
        dataKey: 'value',
        x: 100,
        y: 50,
        width: 400,
        fill: const Color(0xFFAABBCC),
        stroke: const Color(0xFFDDEEFF),
        traveller: (canvas, p) => calls.add(p),
      ),
    ));
    expect(calls.take(2).map((p) => [p.x, p.y, p.width, p.height, p.fill, p.stroke]), [
      [100, 50, 5, 40, const Color(0xFFAABBCC), const Color(0xFFDDEEFF)],
      [495, 50, 5, 40, const Color(0xFFAABBCC), const Color(0xFFDDEEFF)],
    ]);
  });

  testWidgets('Don\'t render travellers when data is empty', (tester) async {
    await tester.pumpWidget(host(const BarChart(width: 400, height: 100, data: [], children: [
      Brush(x: 100, y: 50, width: 400, height: 40),
    ])));
    expect(find.byType(BrushLayer), findsNothing);
  });

  testWidgets('alwaysShowText: texts at min(startX, endX) - 5 and max + travellerWidth + 5', (tester) async {
    await tester.pumpWidget(simpleBrush(
        brush: const Brush(dataKey: 'value', x: 100, y: 50, width: 400, height: 40, alwaysShowText: true)));
    final s = brushState(tester);
    expect(s.textVisible, isTrue);
    expect(s.brushTexts.map((t) => (t.text, t.position, t.anchor)), [
      ('10', const Offset(95, 70), TextAnchor.end),
      ('10', const Offset(505, 70), TextAnchor.start),
    ]);
  });

  testWidgets('tickFormatter formats the labels; without dataKey the label is the index', (tester) async {
    await tester.pumpWidget(simpleBrush(
        brush: Brush(x: 100, y: 50, width: 400, alwaysShowText: true, tickFormatter: (v, i) => '#$v/$i')));
    expect(brushState(tester).brushTexts.map((t) => t.text), ['#0/0', '#13/13']);
  });

  testWidgets('mouse over the slide shows the texts, leaving hides them', (tester) async {
    await tester.pumpWidget(host(const BarChart(width: 500, height: 100, data: data, children: [
      Brush(dataKey: 'date', height: 90, stroke: Color(0xFF8884D8)),
    ])));
    expect(brushLayer(tester).rect, const Rect.fromLTWH(5, 5, 490, 90));
    final mouse = await mouseAt(tester, const Offset(250, 3));
    await mouse.moveTo(const Offset(250, 50));
    await tester.pump();
    final s = brushState(tester);
    expect(s.textVisible, isTrue);
    expect(s.brushTexts.map((t) => t.text), ['2023-01-01', '2023-01-14']);
    await mouse.moveTo(const Offset(250, 98));
    await tester.pump();
    expect(s.textVisible, isFalse);
  });

  testWidgets('mouse down on the slide shows the texts, mouse up outside hides them', (tester) async {
    await tester.pumpWidget(host(const BarChart(
      width: 500,
      height: 100,
      data: data,
      margin: Margin(right: 100, left: 100),
      children: [Brush(dataKey: 'date', height: 90, stroke: Color(0xFF8884D8))],
    )));
    expect(brushLayer(tester).rect, const Rect.fromLTWH(100, 10, 300, 90));
    final mouse = await mouseAt(tester, const Offset(250, 50));
    await mouse.down(const Offset(250, 50));
    await tester.pump();
    expect(brushState(tester).isSlideMoving, isTrue);
    expect(brushState(tester).textVisible, isTrue);
    await mouse.moveTo(const Offset(450, 50));
    await mouse.up();
    await tester.pump();
    expect(brushState(tester).textVisible, isFalse);
  });

  testWidgets('dragging the start traveller snaps to index 6 and slices the chart', (tester) async {
    final changes = <BrushStartEndIndex>[];
    final ends = <BrushStartEndIndex>[];
    await tester.pumpWidget(host(LineChart(width: 400, height: 100, data: data, children: [
      const Line(dataKey: 'value', isAnimationActive: false),
      Brush(dataKey: 'value', x: 100, y: 50, width: 400, height: 40, onChange: changes.add, onDragEnd: ends.add),
    ])));
    final mouse = await mouseAt(tester, const Offset(102, 70));
    await mouse.down(const Offset(102, 70));
    await mouse.moveTo(const Offset(302, 70));
    await tester.pump();
    expect(changes.last, (startIndex: 6, endIndex: 13));
    expect(brushState(tester).startX, 300);
    await mouse.up();
    await tester.pump();
    expect(ends, [(startIndex: 6, endIndex: 13)]);
    // the traveller stays where it was dropped, the label shows the snapped index
    expect(brushState(tester).startX, 300);
    expect((brushLayer(tester).startIndex, brushLayer(tester).endIndex), (6, 13));
    // focused after the mouse down (tabIndex=0), so the texts stay
    expect(brushState(tester).isTravellerFocused, isTrue);
    expect(brushState(tester).brushTexts.first.text, '30');
  });

  testWidgets('a traveller is clamped to the brush and the end traveller can pass the start one', (tester) async {
    final changes = <BrushStartEndIndex>[];
    await tester.pumpWidget(simpleBrush(
        width: 600, brush: Brush(dataKey: 'value', x: 100, y: 50, width: 400, height: 40, onChange: changes.add)));
    final mouse = await mouseAt(tester, const Offset(497, 70));
    await mouse.down(const Offset(497, 70));
    await mouse.moveTo(const Offset(150, 70));
    await mouse.moveTo(const Offset(-200, 70));
    await tester.pump();
    final s = brushState(tester);
    expect(s.endX, 100);
    expect(changes.last, (startIndex: 0, endIndex: 0));
    await mouse.up();
  });

  testWidgets('dragging the slide moves both ends and clamps at the bounds', (tester) async {
    final changes = <BrushStartEndIndex>[];
    await tester.pumpWidget(simpleBrush(
        brush: Brush(
            dataKey: 'value', x: 100, y: 50, width: 400, height: 40, startIndex: 3, endIndex: 6, onChange: changes.add)));
    final s = brushState(tester);
    final step = 395 / 13;
    expect(s.startX, closeTo(100 + 3 * step, 1e-9));
    expect(s.endX, closeTo(100 + 6 * step, 1e-9));
    final mouse = await mouseAt(tester, const Offset(250, 70));
    await mouse.down(const Offset(250, 70));
    await mouse.moveTo(Offset(250 + 2 * step + 1, 70));
    await tester.pump();
    expect(changes.last, (startIndex: 5, endIndex: 8));
    await mouse.moveTo(const Offset(2000, 70));
    await tester.pump();
    expect(s.endX, 495);
    expect(changes.last, (startIndex: 10, endIndex: 13));
    await mouse.up();
  });

  testWidgets('slide drag with controlled indexes does not snap back on mouseup', (tester) async {
    await tester.pumpWidget(simpleBrush(
        brush: const Brush(dataKey: 'value', x: 100, y: 50, width: 400, height: 40, startIndex: 3, endIndex: 6)));
    final mouse = await mouseAt(tester, const Offset(200, 70));
    await mouse.down(const Offset(200, 70));
    await mouse.moveTo(const Offset(220, 70));
    await tester.pump();
    final s = brushState(tester);
    final during = [s.startX, s.endX];
    await mouse.up();
    await tester.pump();
    expect([s.startX, s.endX], during);
  });

  testWidgets('controlled startIndex/endIndex move the travellers and slice the chart', (tester) async {
    Widget chart(int start, int end) => simpleBrush(
        brush: Brush(dataKey: 'value', x: 100, y: 50, width: 400, height: 40, startIndex: start, endIndex: end));
    await tester.pumpWidget(chart(3, 13));
    await tester.pumpWidget(chart(2, 5));
    final s = brushState(tester);
    final step = 395 / 13;
    expect(s.startX, closeTo(100 + 2 * step, 1e-9));
    expect(s.endX, closeTo(100 + 5 * step, 1e-9));
    expect((brushLayer(tester).startIndex, brushLayer(tester).endIndex), (2, 5));
  });

  testWidgets('keyboard: ArrowRight / ArrowLeft move the focused traveller by one index', (tester) async {
    await tester.pumpWidget(simpleBrush());
    final mouse = await mouseAt(tester, const Offset(102, 70));
    await mouse.down(const Offset(102, 70));
    await mouse.up();
    await tester.pump();
    final s = brushState(tester);
    expect(s.isTravellerFocused, isTrue);
    expect(s.brushTexts.first.text, '10');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(s.brushTexts.first.text, '20');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(s.brushTexts.first.text, '10');
  });

  testWidgets('keyboard after a mouse drag; the value 0 is not filtered out of scaleValues', (tester) async {
    // Brush.spec.tsx: "Travellers should move when valid keyboard events are fired AFTER mouse interaction"
    await tester.pumpWidget(simpleBrush());
    final mouse = await mouseAt(tester, const Offset(102, 70));
    await mouse.down(const Offset(102, 70));
    await mouse.moveTo(const Offset(132, 70));
    await mouse.up();
    await tester.pump();
    final s = brushState(tester);
    expect(s.brushTexts.first.text, '10');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(s.brushTexts.first.text, '20');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(s.brushTexts.first.text, '10');
  });

  testWidgets('Tab moves focus svg -> start -> end traveller; Enter toggles the chart tooltip', (tester) async {
    // Brush.spec.tsx: "Should not filter out the value 0 in scaleValues and cause indices to be off by 1"
    await tester.pumpWidget(host(ComposedChart(
      width: 200,
      height: 100,
      data: data.sublist(0, 6),
      margin: const Margin(),
      children: const [
        Line(dataKey: 'value', isAnimationActive: false),
        Tooltip(isAnimationActive: false),
        Brush(child: LineChart(children: [Line(dataKey: 'name', isAnimationActive: false)])),
      ],
    )));
    final mouse = await mouseAt(tester, const Offset(100, 30));
    await mouse.down(const Offset(100, 30));
    await mouse.up();
    await mouse.moveTo(const Offset(300, 300));
    await tester.pump();
    final s = brushState(tester);
    // the svg has focus: no traveller texts; mousedown's focus showed the keyboard
    // tooltip at index 0, and the click in the plot area (setMouseClickAxisIndex)
    // deactivated it again, as Chrome shows with Recharts
    expect(s.isTravellerFocused, isFalse);
    expect(find.text('0'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(brushLayer(tester).focusedTraveller, BrushTravellerId.endX);
    // focusout + focusin on the wrapper: the keyboard tooltip went inactive and stays so
    expect(find.text('0'), findsNothing);
    expect(s.brushTexts.last.text, '5');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(s.brushTexts.last.text, '4');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(s.brushTexts.last.text, '5');
    // Enter is not handled by the traveller and bubbles to the chart, which leaves its default alone
    expect(await tester.sendKeyEvent(LogicalKeyboardKey.enter), isFalse);
    await tester.pump();
    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('touch drag moves the end traveller and ends on touch up', (tester) async {
    final changes = <BrushStartEndIndex>[];
    final ends = <BrushStartEndIndex>[];
    await tester.pumpWidget(simpleBrush(
        width: 600,
        brush: Brush(
            dataKey: 'value', x: 100, y: 50, width: 400, height: 40, onChange: changes.add, onDragEnd: ends.add)));
    final finger = await tester.startGesture(const Offset(497, 70), kind: PointerDeviceKind.touch);
    await tester.pump();
    expect(brushState(tester).isTravellerMoving, isTrue);
    await finger.moveTo(const Offset(397, 70));
    await tester.pump();
    // endX 395 -> index 9 (100 + 9 * 30.38 = 373.5 <= 395 < 403.8)
    expect(changes.last, (startIndex: 0, endIndex: 9));
    await finger.up();
    await tester.pump();
    expect(ends, [(startIndex: 0, endIndex: 9)]);
    expect(brushState(tester).isTravellerMoving, isFalse);
  });

  testWidgets('leaving the brush starts the leave timer, the next move cancels it', (tester) async {
    final ends = <BrushStartEndIndex>[];
    Widget chart(double top) => host(Padding(
          padding: EdgeInsets.only(top: top),
          child: BarChart(width: 400, height: 100, data: data, children: [
            Brush(dataKey: 'value', x: 100, y: 50, width: 400, height: 40, onDragEnd: ends.add),
          ]),
        ));
    await tester.pumpWidget(chart(0));
    final mouse = await mouseAt(tester, const Offset(102, 70));
    await mouse.down(const Offset(102, 70));
    // mouseleave then mousemove: handleDrag clears the timer, the drag goes on
    await mouse.moveTo(const Offset(150, 20));
    await tester.pump(const Duration(milliseconds: 1500));
    expect(brushState(tester).isTravellerMoving, isTrue);
    expect(brushState(tester).startX, 148);
    // back inside, then the brush moves away from under the still mouse:
    // mouseleave without a mousemove
    await mouse.moveTo(const Offset(150, 70));
    await tester.pump();
    await tester.pumpWidget(chart(200));
    await tester.pump(const Duration(milliseconds: 999));
    expect(brushState(tester).isTravellerMoving, isTrue);
    await tester.pump(const Duration(milliseconds: 2));
    expect(brushState(tester).isTravellerMoving, isFalse);
    expect(ends.length, 1);
    // moves after the drag ended are ignored
    await mouse.moveTo(const Offset(300, 20));
    await tester.pump();
    expect(brushState(tester).startX, 148);
    await mouse.up();
    expect(ends.length, 1);
  });

  testWidgets('hovering the brush shows no tooltip; pressing it focuses the chart (tooltip at index 0)',
      (tester) async {
    // TapRegionSurface over a page background: what an app provides, for clicks outside the chart
    await tester.pumpWidget(TapRegionSurface(
        child: ColoredBox(
            color: const Color(0xFFFFFFFF),
            child: host(const LineChart(width: 400, height: 300, data: data, children: [
              XAxis(dataKey: 'name'),
              Line(dataKey: 'value'),
              Tooltip(),
              Brush(dataKey: 'name'),
            ])))));
    expect(brushLayer(tester).rect, const Rect.fromLTWH(5, 255, 390, 40));
    final mouse = await mouseAt(tester, const Offset(200, 298));
    await mouse.moveTo(const Offset(200, 275));
    await tester.pump();
    expect(find.text('A'), findsNothing);
    // mousedown focuses the traveller; the wrapper's focusin activates the
    // keyboard tooltip at index 0, which follows the slice
    await mouse.down(const Offset(7, 275));
    await tester.pump();
    expect(find.text('A'), findsOneWidget);
    await mouse.moveTo(const Offset(60, 275));
    await mouse.up();
    await tester.pump();
    expect(brushLayer(tester).startIndex, 1);
    expect(find.text('B'), findsOneWidget);
    // a click outside the chart blurs it and hides the tooltip
    await mouse.moveTo(const Offset(600, 500));
    await mouse.down(const Offset(600, 500));
    await mouse.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('B'), findsNothing);
  });

  testWidgets('accessibilityLayer false: pressing the brush drags it but shows no keyboard tooltip', (tester) async {
    await tester.pumpWidget(TapRegionSurface(
        child: ColoredBox(
            color: const Color(0xFFFFFFFF),
            child: host(const LineChart(width: 400, height: 300, data: data, accessibilityLayer: false, children: [
              XAxis(dataKey: 'name'),
              Line(dataKey: 'value'),
              Tooltip(),
              Brush(dataKey: 'name'),
            ])))));
    final mouse = await mouseAt(tester, const Offset(7, 275));
    await mouse.down(const Offset(7, 275));
    await tester.pump();
    expect(find.text('A'), findsNothing);
    await mouse.moveTo(const Offset(60, 275));
    await mouse.up();
    await tester.pump();
    expect(brushLayer(tester).startIndex, 1);
    expect(find.text('B'), findsNothing);
  });

  testWidgets('a chart with a brush in a ListView still scrolls when dragging outside the brush', (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: ListView(controller: controller, children: [
        const LineChart(width: 400, height: 300, data: data, children: [Line(dataKey: 'value'), Brush()]),
        const SizedBox(height: 2000),
      ]),
    ));
    await tester.dragFrom(const Offset(200, 100), const Offset(0, -200));
    await tester.pump();
    expect(controller.offset, greaterThan(100));
  });

  testWidgets('a horizontal touch drag on a traveller inside a ListView moves the brush', (tester) async {
    final changes = <BrushStartEndIndex>[];
    final controller = ScrollController();
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: ListView(controller: controller, children: [
        LineChart(width: 400, height: 300, data: data, children: [
          const Line(dataKey: 'value'),
          Brush(onChange: changes.add),
        ]),
        const SizedBox(height: 2000),
      ]),
    ));
    await tester.dragFrom(const Offset(7, 275), const Offset(150, 0));
    await tester.pump();
    expect(changes, isNotEmpty);
    expect(controller.offset, 0);
  });

  testWidgets('bars re-animate when the brush range changes', (tester) async {
    const flat = [
      {'v': 100},
      {'v': 100},
      {'v': 100},
      {'v': 100},
    ];
    Widget chart({bool? animate}) => host(BarChart(width: 400, height: 100, margin: const Margin(), data: flat, children: [
          Bar(dataKey: 'v', fill: const Color(0xFFFF0000), isAnimationActive: animate),
          const Brush(),
        ]));
    Future<Color> after(bool? animate) async {
      await tester.pumpWidget(chart(animate: animate));
      await tester.pump(const Duration(seconds: 1));
      // start traveller 0..5 at y 60..100; drop it at x 270 -> startIndex 2
      final mouse = await mouseAt(tester, const Offset(2, 80));
      await mouse.down(const Offset(2, 80));
      await mouse.moveTo(const Offset(272, 80));
      await mouse.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      final image = await capture(tester);
      await mouse.removePointer();
      // bars of the slice: x 20..180 and 220..380; before: 10..90, 110..190, ...
      return pixel(tester, image, const Offset(100, 30));
    }

    expect(await after(null), isNot(const Color(0xFFFF0000)));
    await tester.pump(const Duration(milliseconds: 450));
    expect(await pixel(tester, await capture(tester), const Offset(100, 30)), const Color(0xFFFF0000));

    await tester.pumpWidget(const SizedBox());
    expect(await after(false), const Color(0xFFFF0000));
  });

  testWidgets('panorama renders the child chart over the full data', (tester) async {
    await tester.pumpWidget(simpleBrush(
        brush: const Brush(
            x: 90,
            y: 40,
            width: 300,
            height: 50,
            child: LineChart(children: [Line(dataKey: 'value', stroke: Color(0xFFFF0000), isAnimationActive: false)]))));
    expect(find.byWidgetPredicate((w) => w is CategoricalChart), findsNWidgets(2));
    final panorama = tester.getRect(find.byWidgetPredicate((w) => w is CategoricalChart && w.width == 300));
    expect(panorama, const Rect.fromLTWH(90, 40, 300, 50));
  });

  testWidgets('charts sharing a syncId share the brush range', (tester) async {
    await tester.pumpWidget(host(Column(mainAxisSize: MainAxisSize.min, children: const [
      LineChart(width: 400, height: 100, data: data, syncId: 's', children: [
        Line(dataKey: 'value'),
        Brush(dataKey: 'value', x: 100, y: 50, width: 400, height: 40),
      ]),
      LineChart(width: 400, height: 100, data: data, syncId: 's', children: [
        Line(dataKey: 'value'),
        Brush(dataKey: 'value', x: 100, y: 50, width: 400, height: 40),
      ]),
    ])));
    final mouse = await mouseAt(tester, const Offset(102, 70));
    await mouse.down(const Offset(102, 70));
    await mouse.moveTo(const Offset(302, 70));
    await mouse.up();
    await tester.pump();
    await tester.pump();
    final layers = tester.widgetList<BrushLayer>(find.byType(BrushLayer)).toList();
    expect([for (final l in layers) (l.startIndex, l.endIndex)], [(6, 13), (6, 13)]);
  });

  group('Brush.spec.tsx / chartDataSlice.spec.ts: start and end index inside the data', () {
    testWidgets('startIndex and endIndex outside of the data give finite positions', (tester) async {
      await tester.pumpWidget(host(const LineChart(width: 400, height: 100, data: data, children: [
        Line(dataKey: 'value', isAnimationActive: false),
        Brush(dataKey: 'value', startIndex: -3, endIndex: 100),
      ])));
      final s = brushState(tester);
      expect((brushLayer(tester).startIndex, brushLayer(tester).endIndex), (0, 13));
      expect([s.startX, s.endX].every((x) => x.isFinite), isTrue);
    });

    testWidgets('a start index from longer data moves to the last item of the new data', (tester) async {
      Widget chart(List<Object?> d, Brush brush) => host(BarChart(width: 400, height: 100, data: d, children: [brush]));
      await tester.pumpWidget(chart(data, const Brush(dataKey: 'value', startIndex: 12)));
      expect((brushLayer(tester).startIndex, brushLayer(tester).endIndex), (12, 13));
      await tester.pumpWidget(chart(data.sublist(0, 5), const Brush(dataKey: 'value')));
      expect((brushLayer(tester).startIndex, brushLayer(tester).endIndex), (4, 4));
    });

    testWidgets('a synchronised range from a chart with more data is limited to this chart\'s data', (tester) async {
      await tester.pumpWidget(host(Column(mainAxisSize: MainAxisSize.min, children: [
        const LineChart(width: 400, height: 100, data: data, syncId: 's', children: [
          Line(dataKey: 'value'),
          Brush(dataKey: 'value', x: 100, y: 50, width: 400, height: 40),
        ]),
        LineChart(width: 400, height: 100, data: data.sublist(0, 5), syncId: 's', children: const [
          Line(dataKey: 'value'),
          Brush(dataKey: 'value', x: 100, y: 50, width: 400, height: 40),
        ]),
      ])));
      final mouse = await mouseAt(tester, const Offset(102, 70));
      await mouse.down(const Offset(102, 70));
      await mouse.moveTo(const Offset(302, 70));
      await mouse.up();
      await tester.pump();
      await tester.pump();
      final layers = tester.widgetList<BrushLayer>(find.byType(BrushLayer)).toList();
      expect([for (final l in layers) (l.startIndex, l.endIndex)], [(6, 13), (4, 4)]);
    });
  });

  testWidgets('semantics: travellers are sliders labelled with the names', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(simpleBrush());
    expect(find.semantics.byLabel('Min value: A, Max value: N'), findsExactly(2));
    handle.dispose();
  });

  group('noUndefinedInDom.spec.tsx: Brush traveller labels', () {
    const labelData = [
      {'label': 'a', 'value': 5},
      {'label': 'b', 'value': 3},
    ];

    testWidgets('use the dataKey value when the data has no name field', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(const LineChart(width: 300, height: 200, data: labelData, children: [
        XAxis(dataKey: 'label'),
        Line(dataKey: 'value', isAnimationActive: false),
        Brush(dataKey: 'label'),
      ])));
      expect(find.semantics.byLabel('Min value: a, Max value: b'), findsExactly(2));
      handle.dispose();
    });

    testWidgets('are left out when there is no name to show', (tester) async {
      await tester.pumpWidget(host(const LineChart(width: 300, height: 200, data: labelData, children: [
        Line(dataKey: 'value', isAnimationActive: false),
        Brush(),
      ])));
      expect(brushState(tester).ariaLabel, isNull);
    });
  });
}

