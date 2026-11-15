// Ported from test/chart/Sankey.spec.tsx. Layout runs on exampleSankeyData
// (test/_data.ts, 48 nodes and 68 links); the spec does not mock text
// measurement for any of these numbers, so they hold as they are.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/recharts_flutter.dart';
import 'package:recharts_flutter/src/sankey.dart';

import '../widgets/chart_widget_test.dart' show host, tooltipBox;
import '../widgets/tooltip_item_test.dart' show Probe, mouseAt;

final exampleSankeyData =
    SankeyData.fromJson(jsonDecode(File('test/sankey/example_sankey_data.json').readAsStringSync()) as Map<String, dynamic>);

SankeyLayout compute(SankeyData data, {int iterations = 32}) =>
    computeSankeyData(data: data, width: 1000, height: 500, iterations: iterations);

SankeyData chain(List<String> names, List<List<num>> links) => SankeyData(
      nodes: [for (final n in names) {'name': n}],
      links: [for (final l in links) SankeyLinkDatum(source: l[0].toInt(), target: l[1].toInt(), value: l[2].toDouble())],
    );

void main() {
  group('layout of exampleSankeyData at 990x490 content size', () {
    final layout = computeSankeyData(data: exampleSankeyData, width: 990, height: 490);

    test('node 0', () {
      final n = layout.nodes[0];
      expect(n.depth, 0);
      expect(n.dx, 10);
      expect(n.dy, 13.172337974085991);
      expect(n.x, 0);
      expect(n.y, 127.92976245668771);
      expect(n.value, 124.729);
      expect(n.sourceLinks, isEmpty);
      expect(n.sourceNodes, isEmpty);
      expect(n.targetLinks, [0]);
      expect(n.targetNodes, [1]);
    });

    test('node 1 has its link lists sorted by y', () {
      final n = layout.nodes[1];
      expect(n.depth, 1);
      expect(n.dy, 41.07345963305562);
      expect(n.x, 140);
      expect(n.y, 113.96304660380619);
      expect(n.value, 388.925);
      expect(n.sourceLinks, [65, 0, 51, 44]);
      expect(n.sourceNodes, [0, 34, 39, 45]);
      expect(n.targetLinks, [2, 3, 4, 1]);
      expect(n.targetNodes, [2, 3, 4, 5]);
    });

    test('link 0', () {
      final l = layout.links[0];
      expect(l.dy, 13.172337974085991);
      expect(l.sy, 0);
      expect(l.ty, 19.221650415407733);
    });
  });

  group('props and tooltip coordinates', () {
    final layout = computeSankeyData(data: exampleSankeyData, width: 990, height: 490);
    final nodes = [for (var i = 0; i < layout.nodes.length; i++) buildNodeProps(node: layout.nodes[i], top: 5, left: 5, i: i)];
    final links = [
      for (var i = 0; i < layout.links.length; i++)
        buildLinkProps(link: layout.links[i], nodes: layout.nodes, top: 5, left: 5, i: i, linkCurvature: 0.5)!,
    ];

    test('node props add the margin', () {
      final p = nodes[0];
      expect([p.x, p.y, p.width, p.height, p.index], [5, 132.9297624566877, 10, 13.172337974085991, 0]);
      expect(sankeyNodeTooltipCoordinate(p), const Offset(10, 139.51593144373072));
    });

    test('link props', () {
      final p = links[0];
      expect(p.sourceX, 15);
      expect(p.targetX, 145);
      expect(p.sourceY, 139.51593144373072);
      expect(p.targetY, 144.77086600625694);
      expect(p.sourceControlX, 80);
      expect(p.targetControlX, 80);
      expect(p.sourceRelativeY, 0);
      expect(p.targetRelativeY, 19.221650415407733);
      expect(p.linkWidth, 13.172337974085991);
      expect(p.index, 0);
      expect(p.payload['value'], 124.729);
      expect(sankeyLinkTooltipCoordinate(p), const Offset(80, 142.14339872499383));
    });

    test('tooltip entries: node name and value, link "source - target"', () {
      final n = sankeyTooltipEntry(
          type: SankeyElementType.node, index: 0, nodes: nodes, links: links, dataKey: 'value', nameKey: 'name');
      expect([n.name, n.value, n.dataKey, n.unit], ['Agricultural waste', 124.729, 'value', '']);
      final l = sankeyTooltipEntry(
          type: SankeyElementType.link, index: 0, nodes: nodes, links: links, dataKey: 'value', nameKey: 'name');
      expect([l.name, l.value], ['Agricultural waste - Bio-conversion', 124.729]);
      // An index with no item still yields one entry, with no value (the keyboard's '0').
      final none = sankeyTooltipEntry(
          type: SankeyElementType.node, index: 99, nodes: nodes, links: links, dataKey: 'value', nameKey: 'name', name: 'S');
      expect([none.value, none.name, none.payload], [null, 'S', null]);
    });
  });

  group('layout options', () {
    test('depth is the longest path from a source, even when nodes skip layers', () {
      final data = chain(['a', 'b', 'c'], [
        [0, 1, 1],
        [1, 2, 1],
        [0, 2, 1],
      ]);
      expect(compute(data).nodes.map((n) => n.depth), [0, 1, 2]);
    });

    test('heavily branching graph lays out with depth 2 * segments', () {
      const segments = 28;
      final names = ['entry-0'];
      final links = <List<num>>[];
      var entry = 0;
      for (var i = 0; i < segments; i++) {
        names.add('top-$i');
        final top = names.length - 1;
        names.add('bottom-$i');
        final bottom = names.length - 1;
        names.add('entry-${i + 1}');
        final next = names.length - 1;
        links.addAll([
          [entry, top, 1],
          [entry, bottom, 1],
          [top, next, 1],
          [bottom, next, 1],
        ]);
        entry = next;
      }
      final layout = compute(chain(names, links));
      expect(layout.nodes, hasLength(names.length));
      expect(layout.nodes.map((n) => n.depth).reduce(math.max), segments * 2);
    });

    test('all link values 0 produce no NaN positions or widths', () {
      final data = chain(['A', 'B', 'C'], [
        [0, 1, 0],
        [1, 2, 0],
      ]);
      final layout = computeSankeyData(data: data, width: 500, height: 300);
      for (final n in layout.nodes) {
        expect(n.dy, 0);
        expect(n.y.isNaN, isFalse);
      }
      for (var i = 0; i < layout.links.length; i++) {
        final p = buildLinkProps(link: layout.links[i], nodes: layout.nodes, top: 5, left: 5, i: i, linkCurvature: 0.5)!;
        expect(p.linkWidth.isFinite, isTrue);
        expect([p.sourceX, p.sourceY, p.targetX, p.targetY].any((v) => v.isNaN), isFalse);
      }
    });

    test('a depth with all 0 values does not squash positive nodes', () {
      final data = chain(['A', 'B', 'C', 'D'], [
        [0, 1, 100],
        [0, 2, 0],
        [2, 3, 0],
      ]);
      final layout = computeSankeyData(data: data, width: 500, height: 300);
      expect(layout.nodes.where((n) => n.dy > 0), hasLength(2));
    });

    test('intermediate nodes stay out of links that skip over their depth', () {
      final data = chain(
        ['Consumption bought', 'Total consumption', 'Total production', 'Consumed production', 'Passive surplus', 'Unused production'],
        [
          [0, 1, 797.44],
          [2, 3, 39.73],
          [3, 1, 39.73],
          [2, 4, 1.95],
          [4, 5, 1.95],
        ],
      );
      final layout = computeSankeyData(data: data, width: 750, height: 410);
      final link = buildLinkProps(link: layout.links[0], nodes: layout.nodes, top: 5, left: 5, i: 0, linkCurvature: 0.5)!;
      double cubic(double a, double b, double c, double d, double t) {
        final u = 1 - t;
        return u * u * u * a + 3 * u * u * t * b + 3 * u * t * t * c + t * t * t * d;
      }

      double linkY(double x) {
        var lo = 0.0, hi = 1.0;
        for (var i = 0; i < 30; i++) {
          final mid = (lo + hi) / 2;
          if (cubic(link.sourceX, link.sourceControlX, link.targetControlX, link.targetX, mid) < x) {
            lo = mid;
          } else {
            hi = mid;
          }
        }
        return cubic(link.sourceY, link.sourceY, link.targetY, link.targetY, (lo + hi) / 2);
      }

      for (final n in [layout.nodes[3], layout.nodes[4]]) {
        final x = n.x + 5 + n.dx / 2, y = n.y + 5;
        final ly = linkY(x);
        expect(y + n.dy <= ly - link.linkWidth / 2 || y >= ly + link.linkWidth / 2, isTrue, reason: 'node ${n.data['name']}');
      }
    });

    test('align left keeps sinks at their own depth; vertical top stacks from 0', () {
      final data = chain(['a', 'b', 'c', 'd'], [
        [0, 1, 1],
        [1, 2, 1],
        [0, 3, 1],
      ]);
      final justify = computeSankeyData(data: data, width: 1000, height: 500);
      expect(justify.nodes[3].depth, 2);
      final left = computeSankeyData(data: data, width: 1000, height: 500, align: SankeyAlign.left);
      expect(left.nodes[3].depth, 1);
      expect(left.nodes[3].x, 495);
      final top = computeSankeyData(data: data, width: 1000, height: 500, verticalAlign: SankeyVerticalAlign.top);
      expect(top.nodes[0].y, 0);
    });
  });

  group('layout of graphs that contain a cycle (recharts #7619)', () {
    test('a back edge lays out instead of exhausting the stack', () {
      final data = chain(['a', 'b', 'c'], [
        [0, 1, 10],
        [1, 2, 10],
        [2, 1, 5],
      ]);
      expect(compute(data).nodes, hasLength(3));
    });

    test('a self referencing node lays out', () {
      final data = chain(['a', 'b', 'c'], [
        [0, 1, 10],
        [1, 1, 5],
      ]);
      expect(compute(data).nodes, hasLength(3));
    });

    testWidgets('a graph with a back edge renders every node and link', (tester) async {
      var nodes = 0, links = 0;
      await tester.pumpWidget(host(Sankey(
        width: 1000,
        height: 500,
        data: chain(['a', 'b', 'c'], [
          [0, 1, 10],
          [1, 2, 10],
          [2, 1, 5],
        ]),
        node: (Canvas c, Size s, SankeyNodeProps p) {
          nodes++;
          return null;
        },
        link: (Canvas c, Size s, SankeyLinkProps p) {
          links++;
          return null;
        },
      )));
      expect([nodes, links], [3, 3]);
    });

    test('a target revisited by a longer acyclic path takes that depth', () {
      final data = chain(['a', 'b', 'c', 'd', 'e'], [
        [0, 1, 10],
        [1, 3, 10],
        [0, 2, 10],
        [2, 4, 10],
        [4, 3, 10],
      ]);
      expect(compute(data).nodes.map((n) => n.depth), [0, 1, 1, 3, 2]);
    });

    test('an acyclic graph keeps its depths', () {
      final data = chain(['a', 'b', 'c'], [
        [0, 1, 10],
        [1, 2, 10],
      ]);
      expect(compute(data).nodes.map((n) => n.depth), [0, 1, 2]);
    });
  });

  group('widget', () {
    Widget chart(Probe probe, {Tooltip? tooltip, SankeyEventHandler? onClick, SankeyEventHandler? onEnter, SankeyEventHandler? onLeave}) =>
        host(Sankey(
          width: 1000,
          height: 500,
          data: exampleSankeyData,
          onClick: onClick,
          onMouseEnter: onEnter,
          onMouseLeave: onLeave,
          children: [tooltip ?? Tooltip(isAnimationActive: false, content: probe.build)],
        ));

    testWidgets('hovering a node shows its row at the node centre; leaving hides it', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(chart(probe));
      expect(probe.visible, isFalse);
      final mouse = await mouseAt(tester, const Offset(999, 499));
      await mouse.moveTo(const Offset(10, 139));
      await tester.pump();
      expect(probe.visible, isTrue);
      expect(probe.rows, ['Agricultural waste : 124.729']);
      expect(probe.props!.coordinate, const Offset(10, 139.51593144373072));
      await mouse.moveTo(const Offset(999, 499));
      await tester.pump();
      expect(probe.visible, isFalse);
    });

    testWidgets('hovering a link shows "source - target" at the link midpoint', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(chart(probe));
      final mouse = await mouseAt(tester, const Offset(999, 499));
      // Link 0 at x 80 spans y 135.6..148.7; no other link crosses there.
      await mouse.moveTo(const Offset(80, 142));
      await tester.pump();
      expect(probe.rows, ['Agricultural waste - Bio-conversion : 124.729']);
      expect(probe.props!.coordinate, const Offset(80, 142.14339872499383));
    });

    testWidgets('defaultIndex accepts node-N and link-N; a numeric index activates with no payload at (0,0)', (tester) async {
      Future<Probe> show(Object index) async {
        final probe = Probe();
        await tester.pumpWidget(chart(probe, tooltip: Tooltip(isAnimationActive: false, content: probe.build, defaultIndex: index)));
        return probe;
      }

      var probe = await show('node-0');
      expect(probe.rows, ['Agricultural waste : 124.729']);
      expect(probe.props!.activeIndex, 'node-0');
      expect(probe.props!.coordinate, isNull);
      expect(tooltipBox(tester).targetTranslate, Offset.zero);
      probe = await show('link-0');
      expect(probe.rows, ['Agricultural waste - Bio-conversion : 124.729']);
      for (final bad in ['node-01', 'node-+1', 'node- 1', 'node-0x1', 'node-9999', 'nodes-0']) {
        probe = await show(bad);
        expect(probe.props!.payload, isEmpty, reason: bad);
      }
      probe = await show(0);
      expect(probe.props!.active, isTrue);
      expect(probe.props!.payload, isEmpty);
      expect(probe.props!.activeIndex, '0');
    });

    testWidgets('events fire with the props and type; click is not hover', (tester) async {
      final probe = Probe();
      final log = <String>[];
      String describe(Object item, SankeyElementType type, PointerEvent e) =>
          '${type.name}:${item is SankeyNodeProps ? item.index : (item as SankeyLinkProps).index}';
      await tester.pumpWidget(chart(probe,
          onClick: (i, t, e) => log.add('click ${describe(i, t, e)}'),
          onEnter: (i, t, e) => log.add('enter ${describe(i, t, e)}'),
          onLeave: (i, t, e) => log.add('leave ${describe(i, t, e)}')));
      final mouse = await mouseAt(tester, const Offset(999, 499));
      await mouse.moveTo(const Offset(10, 139));
      await mouse.down(const Offset(10, 139));
      await mouse.up();
      await mouse.moveTo(const Offset(999, 499));
      await tester.pump();
      expect(log, ['enter node:0', 'click node:0', 'leave node:0']);
    });

    testWidgets('trigger=click ignores hover and keeps the tooltip after the pointer leaves', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(chart(probe, tooltip: Tooltip(isAnimationActive: false, trigger: TooltipTrigger.click, content: probe.build)));
      final mouse = await mouseAt(tester, const Offset(999, 499));
      await mouse.moveTo(const Offset(10, 139));
      await tester.pump();
      expect(probe.visible, isFalse);
      await mouse.down(const Offset(10, 139));
      await mouse.up();
      await tester.pump();
      expect(probe.visible, isTrue);
      await mouse.moveTo(const Offset(999, 499));
      await tester.pump();
      expect(probe.visible, isTrue);
    });

    testWidgets('touch tap shows the tooltip', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(chart(probe));
      final g = await tester.createGesture(kind: PointerDeviceKind.touch);
      await g.down(const Offset(10, 139));
      await g.up();
      await tester.pump();
      expect(probe.rows, ['Agricultural waste : 124.729']);
    });
  });

  group('link data', () {
    test('extra link fields are kept in the payload; a missing value counts as 0', () {
      final data = SankeyData.fromJson({
        'nodes': [
          {'name': 'a'},
          {'name': 'b'}
        ],
        'links': [
          {'source': 0, 'target': 1, 'label': 'x'},
        ],
      });
      final layout = computeSankeyData(data: data, width: 100, height: 100);
      expect(layout.links[0].value, 0);
      expect(layout.links[0].dy, 0);
      final p = buildLinkProps(link: layout.links[0], nodes: layout.nodes, top: 0, left: 0, i: 0, linkCurvature: 0.5)!;
      expect(p.payload['label'], 'x');
      expect(p.payload.containsKey('value'), isFalse);
      final e = sankeyTooltipEntry(
          type: SankeyElementType.link,
          index: 0,
          nodes: const [],
          links: [p],
          dataKey: 'value',
          nameKey: 'name');
      expect([e.name, e.value], ['a - b', null]);
    });
  });

  test('viewBox is the chart less the margin', () {
    expect(sankeyViewBox(const Size(1000, 500), const Margin.all(5)), const Rect.fromLTWH(5, 5, 990, 490));
  });

  group('widget (spec ports)', () {
    Widget plain({SankeyData? data, Size size = const Size(1000, 500), Object? node, Object? link, List<RechartsElement> children = const [], Margin margin = const Margin.all(5), String? name, Object? onClickProbe}) =>
        host(Sankey(width: size.width, height: size.height, data: data ?? exampleSankeyData, node: node, link: link, margin: margin, name: name, children: children));

    testWidgets('node and link painters run for every node and link; counts follow the data', (tester) async {
      final nodeIdx = <int>{}, linkIdx = <int>{};
      Path? node(Canvas c, Size s, SankeyNodeProps p) {
        nodeIdx.add(p.index);
        return null;
      }

      Path? link(Canvas c, Size s, SankeyLinkProps p) {
        linkIdx.add(p.index);
        return null;
      }

      await tester.pumpWidget(plain(node: node, link: link));
      expect([nodeIdx.length, linkIdx.length], [48, 68]);
      nodeIdx.clear();
      linkIdx.clear();
      final next = SankeyData(
        nodes: [...exampleSankeyData.nodes, {'name': 'New Node'}],
        links: [...exampleSankeyData.links, SankeyLinkDatum(source: 2, target: exampleSankeyData.nodes.length, value: 100)],
      );
      await tester.pumpWidget(plain(data: next, node: node, link: link));
      expect([nodeIdx.length, linkIdx.length], [49, 69]);
    });

    testWidgets('a node painter also runs for zero-height nodes and receives the chart size', (tester) async {
      final data = chain(['A', 'B', 'C'], [
        [0, 1, 0],
        [1, 2, 0],
      ]);
      final calls = <(int, Size, double)>[];
      await tester.pumpWidget(plain(
          data: data,
          size: const Size(500, 300),
          node: (Canvas c, Size s, SankeyNodeProps p) {
            calls.add((p.index, s, p.height));
            return null;
          }));
      expect(calls.map((c) => c.$1), [0, 1, 2]);
      expect(calls.every((c) => c.$2 == const Size(500, 300) && c.$3 == 0), isTrue);
    });

    testWidgets('heavily branching graph renders every node and link', (tester) async {
      final names = ['entry-0'];
      final links = <List<num>>[];
      var entry = 0;
      for (var i = 0; i < 28; i++) {
        names.addAll(['top-$i', 'bottom-$i', 'entry-${i + 1}']);
        final top = names.length - 3, bottom = names.length - 2, next = names.length - 1;
        links.addAll([[entry, top, 1], [entry, bottom, 1], [top, next, 1], [bottom, next, 1]]);
        entry = next;
      }
      var nodes = 0, count = 0;
      await tester.pumpWidget(plain(
          data: chain(names, links),
          node: (Canvas c, Size s, SankeyNodeProps p) {
            nodes++;
            return null;
          },
          link: (Canvas c, Size s, SankeyLinkProps p) {
            count++;
            return null;
          }));
      expect([nodes, count], [names.length, links.length]);
    });

    testWidgets('axes as children do not throw', (tester) async {
      await tester.pumpWidget(plain(children: const [XAxis(dataKey: 'number'), YAxis(dataKey: 'name')]));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a custom node painter returning a path is what hover hits', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(host(Sankey(
        width: 400,
        height: 300,
        data: chain(['a', 'b'], [
          [0, 1, 10]
        ]),
        // Node 0 claims a square far from its rectangle.
        node: (Canvas c, Size s, SankeyNodeProps p) => p.index == 0 ? (Path()..addRect(const Rect.fromLTWH(300, 10, 50, 50))) : null,
        children: [Tooltip(isAnimationActive: false, content: probe.build)],
      )));
      final mouse = await mouseAt(tester, const Offset(399, 299));
      await mouse.moveTo(const Offset(320, 30));
      await tester.pump();
      expect(probe.rows, ['a : 10.0']);
    });

    Widget tip(Probe probe, {Tooltip? tooltip, Size size = const Size(1000, 500), Margin margin = const Margin.all(5), SankeyData? data, SankeyEventHandler? onClick, SankeyEventHandler? onEnter, SankeyEventHandler? onLeave, String? name, bool accessibilityLayer = true}) =>
        host(Sankey(
          width: size.width,
          height: size.height,
          data: data ?? exampleSankeyData,
          margin: margin,
          name: name,
          accessibilityLayer: accessibilityLayer,
          onClick: onClick,
          onMouseEnter: onEnter,
          onMouseLeave: onLeave,
          children: [tooltip ?? Tooltip(isAnimationActive: false, content: probe.build)],
        ));

    testWidgets('link tooltip hides on leave', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(tip(probe));
      final mouse = await mouseAt(tester, const Offset(999, 499));
      await mouse.moveTo(const Offset(80, 142));
      await tester.pump();
      expect(probe.visible, isTrue);
      await mouse.moveTo(const Offset(999, 499));
      await tester.pump();
      expect(probe.visible, isFalse);
    });

    for (final (label, at, row) in [
      ('link', const Offset(80, 142), 'Agricultural waste - Bio-conversion : 124.729'),
      ('node', const Offset(10, 139), 'Agricultural waste : 124.729'),
    ]) {
      testWidgets('trigger=click on a $label shows the tooltip and keeps it on a second click and after leaving', (tester) async {
        final probe = Probe();
        await tester.pumpWidget(tip(probe, tooltip: Tooltip(isAnimationActive: false, trigger: TooltipTrigger.click, content: probe.build)));
        final mouse = await mouseAt(tester, const Offset(999, 499));
        await mouse.moveTo(at);
        await tester.pump();
        expect(probe.visible, isFalse);
        for (var i = 0; i < 2; i++) {
          await mouse.down(at);
          await mouse.up();
          await tester.pump();
          expect(probe.rows, [row]);
        }
        await mouse.moveTo(const Offset(999, 499));
        await tester.pump();
        expect(probe.visible, isTrue);
      });

      testWidgets('trigger=hover: clicking a $label does not add anything once left', (tester) async {
        final probe = Probe();
        await tester.pumpWidget(tip(probe));
        final mouse = await mouseAt(tester, const Offset(999, 499));
        await mouse.moveTo(at);
        await mouse.down(at);
        await mouse.up();
        await mouse.moveTo(const Offset(999, 499));
        await tester.pump();
        expect(probe.visible, isFalse);
      });
    }

    testWidgets('link events carry the full props and payload', (tester) async {
      final probe = Probe();
      final log = <String>[];
      SankeyLinkProps? seen;
      SankeyEventHandler h(String n) => (Object i, SankeyElementType t, PointerEvent e) {
            log.add('$n ${t.name}');
            seen = i as SankeyLinkProps;
          };
      await tester.pumpWidget(tip(probe,
          onClick: h('click'), onEnter: h('enter'), onLeave: h('leave')));
      final mouse = await mouseAt(tester, const Offset(999, 499));
      await mouse.moveTo(const Offset(80, 142));
      await mouse.down(const Offset(80, 142));
      await mouse.up();
      await mouse.moveTo(const Offset(999, 499));
      await tester.pump();
      expect(log, ['enter link', 'click link', 'leave link']);
      final p = seen!;
      expect([p.sourceX, p.targetX, p.sourceY, p.targetY, p.sourceControlX, p.targetControlX], [15, 145, 139.51593144373072, 144.77086600625694, 80, 80]);
      expect([p.sourceRelativeY, p.targetRelativeY, p.linkWidth, p.index], [0, 19.221650415407733, 13.172337974085991, 0]);
      final payload = p.payload;
      expect([payload['value'], payload['dy'], payload['sy'], payload['ty']], [124.729, 13.172337974085991, 0, 19.221650415407733]);
      final source = payload['source'] as Map, target = payload['target'] as Map;
      expect([source['name'], source['y'], source['dy'], source['depth'], source['value']], ['Agricultural waste', 127.92976245668771, 13.172337974085991, 0, 124.729]);
      expect(source['targetLinks'], [0]);
      expect([target['name'], target['x'], target['y'], target['dy'], target['depth']], ['Bio-conversion', 140, 113.96304660380619, 41.07345963305562, 1]);
      expect(target['sourceLinks'], [65, 0, 51, 44]);
      expect(target['sourceNodes'], [0, 34, 39, 45]);
      expect(target['targetLinks'], [2, 3, 4, 1]);
      expect(target['targetNodes'], [2, 3, 4, 5]);
    });

    testWidgets('node events carry the full props and payload', (tester) async {
      final probe = Probe();
      SankeyNodeProps? seen;
      await tester.pumpWidget(tip(probe, onEnter: (i, t, e) => seen = i as SankeyNodeProps));
      final mouse = await mouseAt(tester, const Offset(999, 499));
      await mouse.moveTo(const Offset(10, 139));
      await tester.pump();
      final p = seen!;
      expect([p.x, p.y, p.width, p.height, p.index], [5, 132.9297624566877, 10, 13.172337974085991, 0]);
      final n = p.payload.toMap();
      expect([n['name'], n['depth'], n['x'], n['dx'], n['y'], n['dy'], n['value']],
          ['Agricultural waste', 0, 0, 10, 127.92976245668771, 13.172337974085991, 124.729]);
      expect([n['sourceNodes'], n['sourceLinks'], n['targetLinks'], n['targetNodes']], [<int>[], <int>[], [0], [1]]);
    });

    testWidgets('link hit area has butt caps: no phantom round cap over the neighbouring node', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(tip(probe, data: chain(['a', 'b', 'c'], [[0, 1, 100], [1, 2, 100]])));
      final mouse = await mouseAt(tester, const Offset(999, 499));
      await mouse.moveTo(const Offset(400, 250));
      await tester.pump();
      expect(probe.rows, ['a - b : 100.0']);
      expect(probe.props!.coordinate!.dx, closeTo(255, 1e-9));
      expect(probe.props!.coordinate!.dy, closeTo(250, 1e-9));
    });

    testWidgets('left of the first link nothing is hit', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(tip(probe, size: const Size(400, 300), margin: const Margin.all(50), data: chain(['a', 'b'], [[0, 1, 10]])));
      final mouse = await mouseAt(tester, const Offset(399, 299));
      await mouse.moveTo(const Offset(30, 150));
      await tester.pump();
      expect(probe.visible, isFalse);
    });

    testWidgets('400x400 margin 20: node 0 tooltip coordinate (Tooltip.visibility.spec)', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(tip(probe, size: const Size(400, 400), margin: const Margin.all(20)));
      final mouse = await mouseAt(tester, const Offset(399, 399));
      await mouse.moveTo(const Offset(25, 104.89236115144739));
      await tester.pump();
      expect(probe.props!.coordinate, const Offset(25, 104.89236115144739));
      expect(probe.rows, ['Agricultural waste : 124.729']);
    });

    testWidgets('600x600 node and link rows (Tooltip.payload.spec)', (tester) async {
      final layout = computeSankeyData(data: exampleSankeyData, width: 590, height: 590);
      final node = buildNodeProps(node: layout.nodes[0], top: 5, left: 5, i: 0);
      final link = buildLinkProps(link: layout.links[0], nodes: layout.nodes, top: 5, left: 5, i: 0, linkCurvature: 0.5)!;
      final probe = Probe();
      await tester.pumpWidget(tip(probe, size: const Size(600, 600)));
      final mouse = await mouseAt(tester, const Offset(599, 599));
      await mouse.moveTo(sankeyNodeTooltipCoordinate(node));
      await tester.pump();
      expect(probe.rows, ['Agricultural waste : 124.729']);
      await mouse.moveTo(sankeyLinkTooltipCoordinate(link));
      await tester.pump();
      expect(probe.rows, ['Agricultural waste - Bio-conversion : 124.729']);
    });

    testWidgets('chart-level stroke goes into the tooltip entry', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(host(Sankey(
        width: 1000,
        height: 500,
        data: exampleSankeyData,
        stroke: const Color(0xFF123456),
        children: [Tooltip(isAnimationActive: false, content: probe.build)],
      )));
      final mouse = await mouseAt(tester, const Offset(999, 499));
      await mouse.moveTo(const Offset(10, 139));
      await tester.pump();
      expect(probe.props!.payload.single.stroke, const Color(0xFF123456));
    });
  });

  group('keyboard (accessibilityLayer)', () {
    // The index '0' finds no item: one entry without a value and no coordinate.
    Widget chart(Probe probe, {bool accessibilityLayer = true, bool? active}) => host(Sankey(
          width: 1000,
          height: 500,
          data: exampleSankeyData,
          name: 'S',
          accessibilityLayer: accessibilityLayer,
          children: [Tooltip(isAnimationActive: false, filterNull: false, active: active, content: probe.build)],
        ));

    TestGesture? shared;
    Future<TestGesture> mouseOnce(WidgetTester tester) async =>
        shared = shared ?? await mouseAt(tester, const Offset(790, 499));
    setUp(() => shared = null);

    Future<void> focus(WidgetTester tester) async {
      final mouse = await mouseOnce(tester);
      await mouse.down(const Offset(790, 499));
      await mouse.up();
      await tester.pump();
      await tester.pump();
    }

    testWidgets('first focus activates the tooltip state at index 0; Enter toggles; blur deactivates', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(chart(probe));
      expect(probe.props!.active, isFalse);
      await focus(tester);
      expect(probe.props!.active, isTrue);
      expect(probe.props!.coordinate, isNull);
      expect(probe.props!.payload, hasLength(1));
      expect([probe.props!.payload.single.name, probe.props!.payload.single.value], ['S', null]);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(probe.props!.active, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(probe.props!.active, isTrue);
      // Arrows return early.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(probe.props!.active, isTrue);

      FocusManager.instance.primaryFocus!.unfocus();
      await tester.pump();
      await tester.pump();
      expect(probe.props!.active, isFalse);
      // Refocusing does not activate again: the index was set once.
      await focus(tester);
      expect(probe.props!.active, isFalse);
    });

    testWidgets('an item hover clears the keyboard state', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(chart(probe));
      await focus(tester);
      expect(probe.props!.active, isTrue);
      final mouse = await mouseOnce(tester);
      await mouse.moveTo(const Offset(10, 139));
      await tester.pump();
      expect(probe.props!.payload.single.value, 124.729);
      await mouse.moveTo(const Offset(790, 499));
      await tester.pump();
      expect(probe.props!.active, isFalse);
    });

    testWidgets('the keyboard outranks the sticky active prop', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(chart(probe, active: true));
      final mouse = await mouseOnce(tester);
      await mouse.moveTo(const Offset(10, 139));
      await tester.pump();
      await mouse.moveTo(const Offset(790, 499));
      await tester.pump();
      // Sticky: the last hovered node stays.
      expect(probe.props!.payload.single.value, 124.729);
      await focus(tester);
      expect(probe.props!.payload.single.value, isNull);
    });

    testWidgets('accessibilityLayer=false: no focus, no keyboard state', (tester) async {
      final probe = Probe();
      await tester.pumpWidget(chart(probe, accessibilityLayer: false));
      await focus(tester);
      expect(probe.props!.active, isFalse);
    });
  });
}
