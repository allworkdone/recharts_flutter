// Treemap interactions from test/chart/Treemap.spec.tsx ("mouse events" with the
// A-E data) and the nest mode, driven through the widget.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/recharts_flutter.dart';
import 'package:recharts_flutter/src/render/svg_text.dart' show debugTextMeasurerOverride;

import 'chart_widget_test.dart' show host;
import 'tooltip_item_test.dart' show Probe, mouseAt;

const data = [
  {'name': 'A', 'size': 24593},
  {'name': 'B', 'size': 1302},
  {'name': 'C', 'size': 652},
  {'name': 'D', 'size': 636},
  {'name': 'E', 'size': 6703},
];

void main() {
  setUp(() => debugTextMeasurerOverride = (_, _) => Size.zero);
  tearDown(() => debugTextMeasurerOverride = null);

  Widget chart({Probe? probe, TreemapType type = TreemapType.flat, List<Object?> d = data, Object dataKey = 'size', void Function(TreemapNode, PointerEvent)? onEnter, void Function(TreemapNode)? onClick}) =>
      host(Treemap(
        width: 500,
        height: 250,
        data: d,
        dataKey: dataKey,
        type: type,
        isAnimationActive: false,
        onMouseEnter: onEnter,
        onClick: onClick,
        children: [if (probe != null) Tooltip(isAnimationActive: false, content: probe.build)],
      ));

  testWidgets('hovering a node shows its name and value at the node centre', (tester) async {
    final probe = Probe();
    TreemapNode? entered;
    await tester.pumpWidget(chart(probe: probe, onEnter: (n, _) => entered = n));
    final mouse = await mouseAt(tester, const Offset(499, 249));
    await mouse.moveTo(const Offset(100, 100));
    await tester.pump();
    expect(probe.visible, isTrue);
    expect(probe.rows, ['A : 24593']);
    expect(probe.props!.coordinate, const Offset(181.5, 125));
    expect(entered!['name'], 'A');
    expect(entered!['value'], 24593);
    expect(entered!['tooltipIndex'], 'children[0]');
    expect((entered!['root'] as TreemapNode)['value'], 33886);
    expect([for (final b in (entered!['root'] as TreemapNode)['children'] as List) (b as TreemapNode)['width']], [363, 69, 34, 34, 137]);
    // E spans 363,70 137x180.
    await mouse.moveTo(const Offset(450, 200));
    await tester.pump();
    expect(probe.rows, ['E : 6703']);
    await mouse.moveTo(const Offset(-5, -5));
    await tester.pump();
    expect(probe.visible, isFalse);
  });

  testWidgets('a parent has no tooltip row when dataKey is not its own key', (tester) async {
    final probe = Probe();
    final nested = [
      {'name': 'P', 'children': [{'name': 'p1', 'size': 3}, {'name': 'p2', 'size': 1}]},
      {'name': 'Q', 'size': 2},
    ];
    await tester.pumpWidget(chart(probe: probe, d: nested, type: TreemapType.nest));
    final mouse = await mouseAt(tester, const Offset(499, 249));
    await mouse.moveTo(const Offset(10, 10));
    await tester.pump();
    expect(probe.visible, isFalse);
  });

  testWidgets('nest mode: clicking a parent drills into it and calls onClick twice', (tester) async {
    final probe = Probe();
    final clicked = <String>[];
    final nested = [
      {'name': 'P', 'children': [{'name': 'p1', 'size': 3}, {'name': 'p2', 'size': 1}]},
      {'name': 'Q', 'size': 2},
    ];
    await tester.pumpWidget(chart(probe: probe, d: nested, type: TreemapType.nest, onClick: (n) => clicked.add(n['name'] as String)));
    final mouse = await mouseAt(tester, const Offset(499, 249));
    await mouse.moveTo(const Offset(10, 10));
    await mouse.down(const Offset(10, 10));
    await mouse.up();
    await tester.pump();
    expect(clicked, ['P', 'P']);
    // The drilled root lays p1 out first: hovering it elsewhere shows p1.
    await mouse.moveTo(const Offset(20, 20));
    await tester.pump();
    expect(probe.rows, ['p1 : 3']);
    // A leaf does not drill further (it still calls onClick twice).
    await mouse.down(const Offset(20, 20));
    await mouse.up();
    await tester.pump();
    expect(clicked, ['P', 'P', 'p1', 'p1']); // handleClick calls onClick for every depth > 0 node
  });

  testWidgets('flat mode calls onClick once, for leaves only', (tester) async {
    final clicked = <String>[];
    await tester.pumpWidget(chart(onClick: (n) => clicked.add(n['name'] as String)));
    final mouse = await mouseAt(tester, const Offset(499, 249));
    await mouse.moveTo(const Offset(100, 100));
    await mouse.down(const Offset(100, 100));
    await mouse.up();
    await tester.pump();
    expect(clicked, ['A']);
  });
}
