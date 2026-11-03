// Treemap interactions from test/chart/Treemap.spec.tsx, driven through the
// widget. Text measurement is 0x0 like jsdom (debugTextMeasurerOverride).

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/recharts_flutter.dart';
import 'package:recharts_flutter/src/render/svg_text.dart' show debugTextMeasurerOverride;

import '../engine/treemap_layout_test.dart' show exampleTreemapData, layout, box;
import 'chart_widget_test.dart' show capture, host, pixel;
import 'tooltip_item_test.dart' show Probe, mouseAt;

const data = [
  {'name': 'A', 'size': 24593},
  {'name': 'B', 'size': 1302},
  {'name': 'C', 'size': 652},
  {'name': 'D', 'size': 636},
  {'name': 'E', 'size': 6703},
];

/// A `content` painter that records the nodes of the last paint, root first.
class Recorder {
  List<TreemapNode> nodes = [];
  void call(Canvas canvas, TreemapNode node) {
    if (node['depth'] == 0) nodes = [];
    nodes.add(node);
  }

  int get rects => nodes.length;
  List<TreemapNode> depth(int d) => [for (final n in nodes) if (n['depth'] == d) n];
}

TreemapNode expectedNode(int i) {
  const b = [
    // name, size, area, x, y, width, height
    ['A', 24593, 90719.61872159594, 0, 0, 363, 250],
    ['B', 1302, 4802.868441244172, 363, 0, 69, 70],
    ['C', 652, 2405.1230596706605, 432, 0, 34, 70],
    ['D', 636, 2346.1016348934663, 466, 0, 34, 70],
    ['E', 6703, 24726.28814259576, 363, 70, 137, 180],
  ];
  final r = b[i];
  return {
    'name': r[0], 'size': r[1], 'children': null, 'value': r[1], 'depth': 1, 'index': i,
    'tooltipIndex': 'children[$i]', 'area': r[2], 'x': r[3], 'y': r[4], 'width': r[5], 'height': r[6],
  };
}

Matcher nodeLike(int i) => equals({
      'id': startsWith('recharts-treemap-'),
      ...expectedNode(i),
      'root': {
        'children': [for (var k = 0; k < 5; k++) expectedNode(k)],
        'x': 0, 'y': 0, 'width': 500, 'height': 250, 'name': '', 'value': 33886, 'depth': 0, 'index': 0, 'tooltipIndex': '',
      },
    });

Future<void> clickAt(WidgetTester tester, TestGesture mouse, Offset p) async {
  await mouse.moveTo(p);
  await mouse.down(p);
  await mouse.up();
  await tester.pump();
}

void main() {
  setUp(() => debugTextMeasurerOverride = (_, _) => Size.zero);
  tearDown(() => debugTextMeasurerOverride = null);

  Widget chart({
    List<Object?> d = data,
    Object dataKey = 'size',
    TreemapType type = TreemapType.flat,
    double height = 250,
    Recorder? rec,
    Probe? probe,
    TooltipTrigger trigger = TooltipTrigger.hover,
    String Function(TreemapNode, int)? nestIndexContent,
    void Function(TreemapNode, PointerEvent)? onEnter,
    void Function(TreemapNode, PointerEvent)? onLeave,
    void Function(TreemapNode)? onClick,
    double nodeInset = 0,
    double nodeGap = 0,
  }) =>
      host(Treemap(
        width: 500,
        height: height,
        data: d,
        dataKey: dataKey,
        type: type,
        isAnimationActive: false,
        nodeInset: nodeInset,
        nodeGap: nodeGap,
        content: rec?.call,
        nestIndexContent: nestIndexContent,
        onMouseEnter: onEnter,
        onMouseLeave: onLeave,
        onClick: onClick,
        children: [if (probe != null) Tooltip(isAnimationActive: false, trigger: trigger, content: probe.build)],
      ));

  group('rect counts (:31, :46, :62)', () {
    testWidgets('flat: 24 rects', (tester) async {
      final rec = Recorder();
      await tester.pumpWidget(chart(d: exampleTreemapData, dataKey: 'value', rec: rec));
      expect(rec.rects, 24);
    });

    testWidgets('nest: 21 rects (depth 2 is filtered) and the surface is 30px shorter', (tester) async {
      final rec = Recorder();
      await tester.pumpWidget(chart(d: exampleTreemapData, dataKey: 'value', type: TreemapType.nest, rec: rec));
      expect(rec.rects, 21);
      expect(rec.depth(1), hasLength(20));
      expect(rec.depth(0).single['height'], 220);
    });
  });

  group('nest navigation (:208-:344)', () {
    // Node A of exampleTreemapData in the 500x220 nest layout; a point away from its label.
    final a = box((layout(exampleTreemapData, h: 220)['children'] as List).first);
    final onA = Offset(a[0] + a[2] - 5, a[1] + 5);
    // Breadcrumb boxes ('root', 'A'): 14px wide (0x0 text), centred; the line starts at 220 + 2 (descent) + 8.
    const rootBox = Offset(240, 236), aBox = Offset(257, 236);
    String crumbs(TreemapNode item, int i) => i == 0 ? 'root' : '${item['name']}';

    Future<(WidgetTester, Recorder, TestGesture)> start(WidgetTester tester, {List<String>? clicks}) async {
      final rec = Recorder();
      await tester.pumpWidget(chart(
          d: exampleTreemapData,
          dataKey: 'value',
          type: TreemapType.nest,
          rec: rec,
          nestIndexContent: crumbs,
          onClick: clicks == null ? null : (n) => clicks.add('${n['name']}')));
      return (tester, rec, await mouseAt(tester, const Offset(600, 400)));
    }

    testWidgets('clicking A drills: 21 -> 4 rects, 3 depth-1 nodes, the first is U', (tester) async {
      final (_, rec, mouse) = await start(tester);
      expect(rec.rects, 21);
      expect(rec.depth(1), hasLength(20));
      await clickAt(tester, mouse, onA);
      expect(rec.rects, 4);
      expect(rec.depth(1), hasLength(3));
      expect(rec.depth(1).first['name'], 'U');
    });

    testWidgets('the root breadcrumb goes back to root', (tester) async {
      final (_, rec, mouse) = await start(tester);
      await clickAt(tester, mouse, onA);
      expect(rec.rects, 4);
      await clickAt(tester, mouse, rootBox);
      expect(rec.rects, 21);
    });

    testWidgets('the breadcrumb click needs the pointer down on the same box', (tester) async {
      final (_, rec, mouse) = await start(tester);
      await clickAt(tester, mouse, onA);
      await mouse.moveTo(rootBox);
      await mouse.down(rootBox);
      await mouse.moveTo(aBox);
      await mouse.up();
      await tester.pump();
      expect(rec.rects, 4);
    });

    testWidgets('with the default name the root box is empty, so it cannot be clicked', (tester) async {
      final rec = Recorder();
      await tester.pumpWidget(chart(d: exampleTreemapData, dataKey: 'value', type: TreemapType.nest, rec: rec));
      final mouse = await mouseAt(tester, const Offset(600, 400));
      await clickAt(tester, mouse, onA);
      expect(rec.rects, 4);
      await clickAt(tester, mouse, rootBox);
      expect(rec.rects, 4);
    });

    testWidgets('clicking the current root does not drill again', (tester) async {
      final rec = Recorder();
      final clicks = <String>[];
      final d = [
        {'name': 'P', 'children': [{'name': 'p1', 'value': 3}, {'name': 'p2', 'value': 3}]},
        {'name': 'Q', 'value': 2},
      ];
      // nodeInset leaves a strip of the root visible around its children.
      await tester.pumpWidget(chart(
          d: d, dataKey: 'value', type: TreemapType.nest, nodeInset: 10, rec: rec, onClick: (n) => clicks.add('${n['name']}')));
      final mouse = await mouseAt(tester, const Offset(600, 400));
      final p = box((layout(d, h: 220, inset: 10)['children'] as List).first);
      await clickAt(tester, mouse, Offset(p[0] + p[2] - 5, p[1] + 3));
      expect(rec.rects, 3);
      clicks.clear();
      await clickAt(tester, mouse, const Offset(3, 100));
      expect(rec.rects, 3);
      expect(clicks, ['P']); // the drilled root is named after the node it shows
    });

    testWidgets('no arrow on the current root (nodeInset leaves its left strip visible)', (tester) async {
      await tester.pumpWidget(chart(
          d: [
            {'name': 'P', 'children': [{'name': 'p1', 'value': 3}]},
            {'name': 'Q', 'value': 2},
          ],
          dataKey: 'value',
          type: TreemapType.nest,
          nodeInset: 10));
      final image = await capture(tester);
      // Root fill is colorPanel[0]; the arrow would be black at x 2..6 around y = 110.
      expect(await pixel(tester, image, const Offset(3, 112)), const Color(0xFF1890FF));
    });

    testWidgets('clicking a leaf does not navigate', (tester) async {
      final (_, rec, mouse) = await start(tester);
      await clickAt(tester, mouse, onA);
      expect(rec.rects, 4);
      final u = box(rec.depth(1).first);
      await clickAt(tester, mouse, Offset(u[0] + u[2] - 5, u[1] + 5));
      expect(rec.rects, 4);
    });
  });

  group('tooltip', () {
    testWidgets('hover shows the node at its centre and hides on leaving the chart', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(chart(probe: probe));
      final mouse = await mouseAt(tester, const Offset(600, 400));
      await mouse.moveTo(const Offset(340, 20));
      await tester.pump();
      expect(probe.rows, ['A : 24593']);
      expect(probe.props!.coordinate, const Offset(181.5, 125));
      await mouse.moveTo(const Offset(450, 200));
      await tester.pump();
      expect(probe.rows, ['E : 6703']);
      await mouse.moveTo(const Offset(-5, -5));
      await tester.pump();
      expect(probe.visible, isFalse);
    });

    testWidgets('hovering a label does not dispatch the tooltip (the text is not the rect)', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(chart(probe: probe));
      final mouse = await mouseAt(tester, const Offset(600, 400));
      await mouse.moveTo(const Offset(340, 20));
      await tester.pump();
      expect(probe.rows, ['A : 24593']);
      // A's label starts at x 8 with the baseline at y 132: its cell, not the rect, is under the pointer.
      await mouse.moveTo(const Offset(450, 150));
      await tester.pump();
      expect(probe.rows, ['E : 6703']);
      await mouse.moveTo(const Offset(10, 125));
      await tester.pump();
      expect(probe.rows, ['E : 6703']);
    });

    testWidgets('trigger click: a click shows the tooltip and keeps it after leaving (:521)', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(chart(probe: probe, trigger: TooltipTrigger.click));
      final mouse = await mouseAt(tester, const Offset(600, 400));
      await clickAt(tester, mouse, const Offset(450, 200));
      expect(probe.rows, ['E : 6703']);
      await clickAt(tester, mouse, const Offset(450, 200));
      expect(probe.visible, isTrue);
      await mouse.moveTo(const Offset(-5, -5));
      await tester.pump();
      expect(probe.visible, isTrue);
    });

    testWidgets('trigger click: hover does nothing (:542)', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(chart(probe: probe, trigger: TooltipTrigger.click));
      final mouse = await mouseAt(tester, const Offset(600, 400));
      await mouse.moveTo(const Offset(450, 200));
      await tester.pump();
      expect(probe.visible, isFalse);
    });

    testWidgets('custom content still drives the tooltip (:394)', (tester) async {
      final probe = Probe();
      final rec = Recorder();
      await tester.pumpWidget(chart(probe: probe, rec: rec));
      final mouse = await mouseAt(tester, const Offset(600, 400));
      await mouse.moveTo(const Offset(340, 20));
      await tester.pump();
      expect(probe.visible, isTrue);
      expect(rec.depth(1).first['name'], 'A');
      await mouse.moveTo(const Offset(-5, -5));
      await tester.pump();
      expect(probe.visible, isFalse);
    });

    testWidgets('a parent has no row when dataKey is not its own key', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(chart(probe: probe, d: [
        {'name': 'P', 'children': [{'name': 'p1', 'size': 3}, {'name': 'p2', 'size': 1}]},
        {'name': 'Q', 'size': 2},
      ], type: TreemapType.nest));
      final mouse = await mouseAt(tester, const Offset(600, 400));
      await mouse.moveTo(const Offset(10, 10));
      await tester.pump();
      expect(probe.visible, isFalse);
    });
  });

  group('mouse events (:787, :929)', () {
    testWidgets('onMouseEnter, onMouseLeave between nodes and onClick get the literal node', (tester) async {
      final entered = <TreemapNode>[], left = <TreemapNode>[], clicked = <TreemapNode>[];
      await tester.pumpWidget(chart(
          onEnter: (n, _) => entered.add(n), onLeave: (n, _) => left.add(n), onClick: clicked.add));
      final mouse = await mouseAt(tester, const Offset(600, 400));
      await mouse.moveTo(const Offset(340, 20));
      expect(entered, hasLength(1));
      expect(entered.single, nodeLike(0));
      await mouse.down(const Offset(340, 20));
      await mouse.up();
      expect(clicked.single, nodeLike(0));
      expect(left, isEmpty);
      await mouse.moveTo(const Offset(400, 30));
      expect(entered, hasLength(2));
      expect(left, hasLength(1));
      expect(left.single, nodeLike(0));
    });

    testWidgets('moving onto a label of the same node fires nothing', (tester) async {
      final entered = <TreemapNode>[], left = <TreemapNode>[];
      await tester.pumpWidget(chart(onEnter: (n, _) => entered.add(n), onLeave: (n, _) => left.add(n)));
      final mouse = await mouseAt(tester, const Offset(600, 400));
      await mouse.moveTo(const Offset(340, 20));
      await mouse.moveTo(const Offset(10, 128)); // A's label cell
      expect(entered, hasLength(1));
      expect(left, isEmpty);
    });

    testWidgets('flat mode calls onClick once, for leaves only', (tester) async {
      final clicked = <String>[];
      await tester.pumpWidget(chart(onClick: (n) => clicked.add('${n['name']}')));
      final mouse = await mouseAt(tester, const Offset(600, 400));
      await clickAt(tester, mouse, const Offset(340, 20));
      expect(clicked, ['A']);
    });

    testWidgets('nest mode: onClick is called twice for a depth > 0 node', (tester) async {
      final clicked = <String>[];
      await tester.pumpWidget(chart(d: [
        {'name': 'P', 'children': [{'name': 'p1', 'size': 3}, {'name': 'p2', 'size': 1}]},
        {'name': 'Q', 'size': 2},
      ], type: TreemapType.nest, onClick: (n) => clicked.add('${n['name']}')));
      final mouse = await mouseAt(tester, const Offset(600, 400));
      await clickAt(tester, mouse, const Offset(10, 10));
      expect(clicked, ['P', 'P']);
    });
  });

  group('touch (:1052)', () {
    testWidgets('touch move shows the tooltip without user callbacks', (tester) async {
      final probe = Probe();
      var calls = 0;
      await tester.pumpWidget(chart(probe: probe, onEnter: (_, _) => calls++, onClick: (_) => calls++));
      final g = await tester.startGesture(const Offset(100, 100), kind: PointerDeviceKind.touch);
      await g.moveTo(const Offset(450, 200));
      await tester.pump();
      expect(probe.rows, ['E : 6703']);
      expect(calls, 0);
      await g.cancel();
    });

    testWidgets('a tap enters then clicks; a drag from A to B does not click', (tester) async {
      final log = <String>[];
      await tester.pumpWidget(chart(
          onEnter: (n, _) => log.add('enter ${n['name']}'), onClick: (n) => log.add('click ${n['name']}')));
      var g = await tester.startGesture(const Offset(340, 20), kind: PointerDeviceKind.touch);
      await g.up();
      await tester.pump();
      expect(log, ['enter A', 'click A']);
      log.clear();
      g = await tester.startGesture(const Offset(340, 20), kind: PointerDeviceKind.touch);
      await g.moveTo(const Offset(450, 200));
      await g.up();
      await tester.pump();
      expect(log, isEmpty);
    });
  });
}
