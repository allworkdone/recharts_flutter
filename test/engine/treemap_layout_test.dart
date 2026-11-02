// Layout expectations from test/chart/Treemap.spec.tsx.

import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/src/treemap.dart';

const exampleTreemapData = [
  {
    'rank': '1',
    'name': 'A',
    'children': [
      {'rank': '21', 'name': 'U', 'value': 12490887132},
      {'rank': '22', 'name': 'V', 'value': 10772738863},
      {'rank': '23', 'name': 'W', 'value': 8236223813},
    ],
  },
  {'rank': '2', 'name': 'B', 'value': 12490887132},
  {'rank': '3', 'name': 'C', 'value': 10772738863},
  {'rank': '4', 'name': 'D', 'value': 8236223813},
  {'rank': '5', 'name': 'E', 'value': 6583448127},
  {'rank': '6', 'name': 'F', 'value': 5834718183},
  {'rank': '7', 'name': 'G', 'value': 5559852006},
  {'rank': '8', 'name': 'H', 'value': 4651272674},
  {'rank': '9', 'name': 'I', 'value': 4248844205},
  {'rank': '10', 'name': 'J', 'value': 3862568602},
  {'rank': '11', 'name': 'K', 'value': 3803070009},
  {'rank': '12', 'name': 'L', 'value': 3480361169},
  {'rank': '13', 'name': 'M', 'value': 3476552989},
  {'rank': '14', 'name': 'N', 'value': 3147229713},
  {'rank': '15', 'name': 'O', 'value': 2907504853},
  {'rank': '16', 'name': 'P', 'value': 2555558916},
  {'rank': '17', 'name': 'Q', 'value': 2149183029},
  {'rank': '18', 'name': 'R', 'value': 2107468912},
  {'rank': '19', 'name': 'S', 'value': 2088055427},
  {'rank': '20', 'name': 'T', 'value': 1885463047},
];

const phi = 1.618033988749895;

TreemapNode layout(List<Object?> data, {String dataKey = 'value', double w = 500, double h = 250, double inset = 0, double gap = 0}) {
  final root = computeNode(
      depth: 0, node: {'children': data, 'x': 0, 'y': 0, 'width': w, 'height': h}, index: 0, dataKey: dataKey, nameKey: 'name');
  return squarify(root, phi, inset, gap);
}

Iterable<TreemapNode> walk(TreemapNode n) sync* {
  yield n;
  for (final c in (n['children'] as List?) ?? const []) {
    yield* walk(c as TreemapNode);
  }
}

List<num> box(Object? n) {
  final m = n as TreemapNode;
  return [m['x']!, m['y']!, m['width']!, m['height']!].cast<num>();
}

void main() {
  const data = [
    {'name': 'A', 'size': 24593},
    {'name': 'B', 'size': 1302},
    {'name': 'C', 'size': 652},
    {'name': 'D', 'size': 636},
    {'name': 'E', 'size': 6703},
  ];

  test('squarify positions and areas of the size-keyed A-E data (mouse events spec)', () {
    final root = layout(data, dataKey: 'size');
    expect(root['value'], 33886);
    expect(root['name'], '');
    expect(root['tooltipIndex'], '');
    final c = (root['children'] as List).cast<TreemapNode>();
    expect([for (final n in c) box(n)], [
      [0, 0, 363, 250],
      [363, 0, 69, 70],
      [432, 0, 34, 70],
      [466, 0, 34, 70],
      [363, 70, 137, 180],
    ]);
    expect(c[0]['area'], 90719.61872159594);
    expect(c[1]['area'], 4802.868441244172);
    expect(c[2]['area'], 2405.1230596706605);
    expect(c[3]['area'], 2346.1016348934663);
    expect(c[4]['area'], 24726.28814259576);
    expect([for (final n in c) n['tooltipIndex']], ['children[0]', 'children[1]', 'children[2]', 'children[3]', 'children[4]']);
    expect(c[0]['children'], isNull);
    expect([for (final n in c) n['depth']], everyElement(1));
  });

  test('exampleTreemapData has 24 nodes, 21 at the nest depth', () {
    final root = layout(exampleTreemapData);
    expect(walk(root).length, 24);
    expect(walk(root).where((n) => n['depth'] == 1).length, 20);
  });

  test('nodeInset insets the children of a parent', () {
    final data = [
      {
        'name': 'Root A',
        'children': [
          {
            'name': 'A1',
            'children': [
              {'name': 'A1a', 'value': 100}
            ]
          }
        ]
      }
    ];
    final plain = walk(layout(data)).toList();
    expect(box(plain[3]), box(plain[2]));
    final inset = walk(layout(data, inset: 8)).toList();
    final d1 = box(inset[2]), d2 = box(inset[3]);
    expect(d2, [d1[0] + 8, d1[1] + 8, d1[2] - 16, d1[3] - 16]);
  });

  test('nodeGap separates siblings', () {
    const sibling = [
      {'name': 'Left', 'value': 100},
      {'name': 'Right', 'value': 100}
    ];
    num gapOf(TreemapNode root) {
      final [a, b] = (root['children'] as List).map(box).toList();
      return [b[0] - (a[0] + a[2]), a[0] - (b[0] + b[2]), b[1] - (a[1] + a[3]), a[1] - (b[1] + b[3]), 0].reduce((p, q) => p > q ? p : q);
    }

    expect(gapOf(layout(sibling)), 0);
    expect(gapOf(layout(sibling, gap: 10)), 10);
  });

  test('addToTreemapNodeIndex + treemapPayloadSearcher', () {
    final root = computeNode(
        depth: 0, node: {'children': exampleTreemapData}, index: 0, dataKey: 'value', nameKey: 'name');
    final children = root['children'] as List;
    expect(addToTreemapNodeIndex(4), 'children[4]');
    expect(treemapPayloadSearcher(root, 'children[4]'), same(children[4]));
    final level1 = children[0] as TreemapNode;
    final index2 = addToTreemapNodeIndex(1, addToTreemapNodeIndex(0));
    expect(index2, 'children[0]children[1]');
    expect(treemapPayloadSearcher(root, index2), same((level1['children'] as List)[1]));
    expect(treemapPayloadSearcher(root, ''), isNull);
  });
}
