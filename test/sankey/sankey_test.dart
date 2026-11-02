// Ported from test/chart/Sankey.spec.tsx. Layout runs on exampleSankeyData
// (test/_data.ts, 48 nodes and 68 links); the spec does not mock text
// measurement for any of these numbers, so they hold as they are.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/recharts_flutter.dart';
import 'package:recharts_flutter/src/sankey.dart';

import '../widgets/chart_widget_test.dart' show host;
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
          type: SankeyElementType.node, index: 0, nodes: nodes, links: links, dataKey: 'value', nameKey: 'name')!;
      expect([n.name, n.value, n.dataKey, n.unit], ['Agricultural waste', 124.729, 'value', '']);
      final l = sankeyTooltipEntry(
          type: SankeyElementType.link, index: 0, nodes: nodes, links: links, dataKey: 'value', nameKey: 'name')!;
      expect([l.name, l.value], ['Agricultural waste - Bio-conversion', 124.729]);
      expect(
          sankeyTooltipEntry(type: SankeyElementType.node, index: 99, nodes: nodes, links: links, dataKey: 'value', nameKey: 'name'),
          isNull);
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
}
