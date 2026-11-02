// Port of the layout half of src/chart/Treemap.tsx: computeNode, squarify
// (insetRect, applyGapToChildren, getAreaOfChildren, getWorstScore and the
// row positioning), addToTreemapNodeIndex and treemapPayloadSearcher. Nodes
// are plain maps like the JS objects: user data keys are kept, the computed
// ones (children, name, value, depth, index, tooltipIndex, x, y, width,
// height, area, root) are added.

import 'dart:math' as math;

import 'util.dart';

/// `TreemapNode`.
typedef TreemapNode = Map<String, Object?>;

const _nodeValueKey = 'value';

/// `COLOR_PANEL` from src/util/Constants.ts.
const treemapColorPanel = [
  '#1890FF',
  '#66B5FF',
  '#41D9C7',
  '#2FC25B',
  '#6EDB8F',
  '#9AE65C',
  '#FACC14',
  '#E6965C',
  '#57AD71',
  '#223273',
  '#738AE6',
  '#7564CC',
  '#8543E0',
  '#A877ED',
  '#5C8EE6',
  '#13C2C2',
  '#70E0E0',
  '#5CA3E6',
  '#3436C7',
  '#8082FF',
  '#DD81E6',
  '#F04864',
  '#FA7D92',
  '#D598D9',
];

/// `addToTreemapNodeIndex`.
String addToTreemapNodeIndex(int indexInChildrenArr, [String activeTooltipIndexSoFar = '']) =>
    '${activeTooltipIndexSoFar}children[$indexInChildrenArr]';

/// `treemapPayloadSearcher`: lodash `get(data, 'children[0]children[1]')`.
TreemapNode? treemapPayloadSearcher(Object? data, String? activeIndex) {
  if (data == null || activeIndex == null || activeIndex.isEmpty) return null;
  Object? cur = data;
  for (final m in RegExp(r'children\[(\d+)\]').allMatches(activeIndex)) {
    final children = cur is Map ? cur['children'] : null;
    final i = int.parse(m[1]!);
    if (children is! List || i >= children.length) return null;
    cur = children[i];
  }
  return cur is TreemapNode ? cur : cur is Map ? cur.cast<String, Object?>() : null;
}

double _num(Object? v) => (v as num).toDouble();

/// `computeNode`.
TreemapNode computeNode({
  required int depth,
  required TreemapNode node,
  required int index,
  required Object? dataKey,
  required Object? nameKey,
  String? nestedActiveTooltipIndex,
}) {
  final currentTooltipIndex = depth == 0 ? '' : addToTreemapNodeIndex(index, nestedActiveTooltipIndex ?? '');
  final children = node['children'];
  final childDepth = depth + 1;
  final computedChildren = children is List && children.isNotEmpty
      ? [
          for (final (i, child) in children.indexed)
            computeNode(
              depth: childDepth,
              node: (child as Map).cast<String, Object?>(),
              index: i,
              dataKey: dataKey,
              nameKey: nameKey,
              nestedActiveTooltipIndex: currentTooltipIndex,
            ),
        ]
      : null;
  double nodeValue;
  if (computedChildren != null && computedChildren.isNotEmpty) {
    nodeValue = computedChildren.fold(0.0, (result, child) => result + _num(child[_nodeValueKey]));
  } else {
    final raw = dataKey is String || dataKey is num ? node[dataKey is String ? dataKey : jsString(dataKey)] : null;
    final numeric = raw is num ? raw.toDouble() : 0.0;
    nodeValue = numeric.isNaN || numeric <= 0 ? 0 : numeric;
  }
  return {
    ...node,
    'children': computedChildren,
    'name': getValueByDataKey(node, nameKey, ''),
    _nodeValueKey: nodeValue,
    'depth': depth,
    'index': index,
    'tooltipIndex': currentTooltipIndex,
  };
}

class _Rect {
  const _Rect(this.x, this.y, this.width, this.height);
  final double x, y, width, height;
}

/// JS truthiness of a number.
bool _truthy(double v) => v != 0 && !v.isNaN;

/// `Math.round` (half up).
double _round(double v) => (v + 0.5).floorToDouble();

_Rect _insetRect(_Rect rect, double nodeInset) {
  if (!nodeInset.isFinite || nodeInset <= 0) return rect;
  final p = math.min(nodeInset, math.min(rect.width / 2, rect.height / 2));
  return _Rect(rect.x + p, rect.y + p, math.max(rect.width - p * 2, 0), math.max(rect.height - p * 2, 0));
}

List<TreemapNode> _applyGapToChildren(List<TreemapNode> children, _Rect parentRect, double nodeGap) {
  if (!nodeGap.isFinite || nodeGap <= 0) return children;
  final halfGap = nodeGap / 2;
  final parentRight = parentRect.x + parentRect.width;
  final parentBottom = parentRect.y + parentRect.height;
  return [
    for (final child in children)
      () {
        final x = _num(child['x']), y = _num(child['y']), w = _num(child['width']), h = _num(child['height']);
        final leftInset = x > parentRect.x ? halfGap : 0.0;
        final rightInset = x + w < parentRight ? halfGap : 0.0;
        final topInset = y > parentRect.y ? halfGap : 0.0;
        final bottomInset = y + h < parentBottom ? halfGap : 0.0;
        return {
          ...child,
          'x': x + leftInset,
          'y': y + topInset,
          'width': math.max(w - leftInset - rightInset, 0),
          'height': math.max(h - topInset - bottomInset, 0),
        };
      }(),
  ];
}

List<TreemapNode> _getAreaOfChildren(List<Object?> children, double areaValueRatio) {
  final ratio = areaValueRatio < 0 ? 0 : areaValueRatio;
  return [
    for (final c in children)
      () {
        final child = c as TreemapNode;
        final area = _num(child[_nodeValueKey]) * ratio;
        return {...child, 'area': area.isNaN || area <= 0 ? 0.0 : area};
      }(),
  ];
}

class _Row {
  final items = <TreemapNode>[];
  double area = 0;
  void clear() {
    items.clear();
    area = 0;
  }
}

double _getWorstScore(_Row row, double parentSize, double aspectRatio) {
  final parentArea = parentSize * parentSize;
  final rowArea = row.area * row.area;
  var min = double.infinity, max = 0.0;
  for (final child in row.items) {
    final a = _num(child['area']);
    min = math.min(min, a);
    max = math.max(max, a);
  }
  return _truthy(rowArea)
      ? math.max((parentArea * max * aspectRatio) / rowArea, rowArea / (parentArea * min * aspectRatio))
      : double.infinity;
}

_Rect _horizontalPosition(_Row row, double parentSize, _Rect parentRect, bool isFlush) {
  var rowHeight = _truthy(parentSize) ? _round(row.area / parentSize) : 0.0;
  if (isFlush || rowHeight > parentRect.height) rowHeight = parentRect.height;
  var curX = parentRect.x;
  TreemapNode? child;
  for (final c in row.items) {
    child = c;
    c['x'] = curX;
    c['y'] = parentRect.y;
    c['height'] = rowHeight;
    final w = math.min(_truthy(rowHeight) ? _round(_num(c['area']) / rowHeight) : 0.0, parentRect.x + parentRect.width - curX);
    c['width'] = w;
    curX += w;
  }
  // add the remain x to the last one of row
  if (child != null) child['width'] = _num(child['width']) + parentRect.x + parentRect.width - curX;
  return _Rect(parentRect.x, parentRect.y + rowHeight, parentRect.width, parentRect.height - rowHeight);
}

_Rect _verticalPosition(_Row row, double parentSize, _Rect parentRect, bool isFlush) {
  var rowWidth = _truthy(parentSize) ? _round(row.area / parentSize) : 0.0;
  if (isFlush || rowWidth > parentRect.width) rowWidth = parentRect.width;
  var curY = parentRect.y;
  TreemapNode? child;
  for (final c in row.items) {
    child = c;
    c['x'] = parentRect.x;
    c['y'] = curY;
    c['width'] = rowWidth;
    final h = math.min(_truthy(rowWidth) ? _round(_num(c['area']) / rowWidth) : 0.0, parentRect.y + parentRect.height - curY);
    c['height'] = h;
    curY += h;
  }
  if (child != null) child['height'] = _num(child['height']) + parentRect.y + parentRect.height - curY;
  return _Rect(parentRect.x + rowWidth, parentRect.y, parentRect.width - rowWidth, parentRect.height);
}

_Rect _position(_Row row, double parentSize, _Rect parentRect, bool isFlush) =>
    parentSize == parentRect.width
        ? _horizontalPosition(row, parentSize, parentRect, isFlush)
        : _verticalPosition(row, parentSize, parentRect, isFlush);

/// `squarify`: recursively arranges the node's children into squarified rows.
TreemapNode squarify(TreemapNode node, double aspectRatio, double nodeInset, double nodeGap) {
  final children = node['children'];
  if (children is! List || children.isEmpty) return node;
  final layoutRect = _insetRect(_Rect(_num(node['x']), _num(node['y']), _num(node['width']), _num(node['height'])), nodeInset);
  var rect = layoutRect;
  final row = _Row();
  var best = double.infinity; // the best row score so far
  var size = math.min(rect.width, rect.height); // initial orientation
  final scaleChildren = _getAreaOfChildren(children, (rect.width * rect.height) / _num(node[_nodeValueKey]));
  final tempChildren = [...scaleChildren];

  while (tempChildren.isNotEmpty) {
    final child = tempChildren.first;
    // row first
    row.items.add(child);
    row.area += _num(child['area']);
    final score = _getWorstScore(row, size, aspectRatio);
    if (score <= best) {
      // continue with this orientation
      tempChildren.removeAt(0);
      best = score;
    } else {
      // abort, and try a different orientation
      row.area -= _num(row.items.removeLast()['area']);
      rect = _position(row, size, rect, false);
      size = math.min(rect.width, rect.height);
      row.clear();
      best = double.infinity;
    }
  }
  if (row.items.isNotEmpty) {
    rect = _position(row, size, rect, true);
    row.clear();
  }

  final childrenWithGaps = _applyGapToChildren(scaleChildren, layoutRect, nodeGap);
  return {...node, 'children': [for (final c in childrenWithGaps) squarify(c, aspectRatio, nodeInset, nodeGap)]};
}
