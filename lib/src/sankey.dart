// Port of the layout and props of src/chart/Sankey.tsx (computeData and the
// helpers above it, buildNodeProps / buildLinkProps, getEntrySvgProps without
// a theme, the tooltip payload searcher). JS names are kept; Array.prototype.sort is stable, so `_sortBy`
// is too.

import 'dart:math' as math;
import 'dart:ui';

import 'components.dart';
import 'css_color.dart';
import 'util.dart';

enum SankeyElementType { node, link }

enum SankeyVerticalAlign { justify, top }

enum SankeyAlign { left, justify }

/// `links` entry of `SankeyData`. [raw] is the whole link object (extra fields
/// included), spread into the layout and tooltip payloads like `{...link}`.
class SankeyLinkDatum {
  SankeyLinkDatum({required this.source, required this.target, this.value = 0, Map<String, Object?> extra = const {}})
      : raw = {...extra, 'source': source, 'target': target, 'value': value};

  /// A link object as JSON; a missing `value` counts as 0 (`getValue`).
  SankeyLinkDatum.fromMap(Map<dynamic, dynamic> m)
      : raw = Map<String, Object?>.from(m),
        source = (m['source'] as num).toInt(),
        target = (m['target'] as num).toInt(),
        value = (m['value'] as num?)?.toDouble() ?? 0;

  final int source;
  final int target;
  final double value;
  final Map<String, Object?> raw;
}

/// `SankeyData`: [nodes] are arbitrary maps (`{name: ...}`), [links] reference them by index.
class SankeyData {
  const SankeyData({required this.nodes, required this.links});
  final List<Map<String, Object?>> nodes;
  final List<SankeyLinkDatum> links;

  /// `{nodes: [{name}], links: [{source, target, value}]}` as JSON.
  factory SankeyData.fromJson(Map<String, dynamic> json) => SankeyData(
        nodes: [for (final n in (json['nodes'] as List? ?? const [])) Map<String, Object?>.from(n as Map)],
        links: [
          for (final l in (json['links'] as List? ?? const []).cast<Map>()) SankeyLinkDatum.fromMap(l),
        ],
      );
}

/// `SankeyNode` after layout.
class SankeyNode {
  SankeyNode(this.data);
  final Map<String, Object?> data;
  List<int> sourceNodes = [], sourceLinks = [], targetNodes = [], targetLinks = [];
  double value = 0;
  int depth = 0;
  // Only set when maxDepth >= 1; Recharts leaves them undefined (NaN) otherwise.
  double x = double.nan, dx = double.nan, y = double.nan, dy = double.nan;

  /// The JS object `{...entry, sourceNodes, sourceLinks, ..., x, dx, y, dy}`.
  Map<String, Object?> toMap() => {
        ...data,
        'sourceNodes': sourceNodes,
        'sourceLinks': sourceLinks,
        'targetNodes': targetNodes,
        'targetLinks': targetLinks,
        'value': value,
        'depth': depth,
        'x': x,
        'dx': dx,
        'y': y,
        'dy': dy,
      };
}

/// `LinkDataItemDy`.
class SankeyLink {
  SankeyLink(this.source, this.target, this.value, this.dy, [this.raw = const {}]);
  final Map<String, Object?> raw;
  final int source;
  final int target;
  final double value;
  final double dy;
  double? sy, ty;
}

class SankeyLayout {
  const SankeyLayout(this.nodes, this.links);
  final List<SankeyNode> nodes;
  final List<SankeyLink> links;
}

double _centerY(SankeyNode node) => node.y + node.dy / 2;

double _cubicValue(double start, double control1, double control2, double end, double t) {
  final inverseT = 1 - t;
  double pow(double b, int e) => math.pow(b, e).toDouble();
  return pow(inverseT, 3) * start + 3 * pow(inverseT, 2) * t * control1 + 3 * inverseT * pow(t, 2) * control2 + pow(t, 3) * end;
}

double _value(double? v) => (v == null || v.isNaN) ? 0 : v;

double _getValue(SankeyLinkDatum? l) => _value(l?.value);

double _getSumOfIds(List<SankeyLinkDatum> links, List<int> ids) =>
    ids.fold(0.0, (result, id) => result + (id < links.length ? _getValue(links[id]) : 0));

double _getSumWithWeightedSource(List<SankeyNode> tree, List<SankeyLink> links, List<int> ids) =>
    ids.fold(0.0, (result, id) {
      final link = id < links.length ? links[id] : null;
      if (link == null || link.source >= tree.length) return result;
      return result + _centerY(tree[link.source]) * _value(link.value);
    });

double _getSumWithWeightedTarget(List<SankeyNode> tree, List<SankeyLink> links, List<int> ids) =>
    ids.fold(0.0, (result, id) {
      final link = id < links.length ? links[id] : null;
      if (link == null || link.target >= tree.length) return result;
      return result + _centerY(tree[link.target]) * _value(link.value);
    });

void _sortBy<T>(List<T> list, double Function(T a, T b) compare) {
  final indexed = list.indexed.toList()
    ..sort((a, b) {
      final c = compare(a.$2, b.$2);
      return c < 0 ? -1 : (c > 0 ? 1 : a.$1 - b.$1);
    });
  for (var i = 0; i < indexed.length; i++) {
    list[i] = indexed[i].$2;
  }
}

double _ascendingY(SankeyNode a, SankeyNode b) => a.y - b.y;

void _searchTargetsAndSources(SankeyNode node, List<SankeyLinkDatum> links, int id) {
  for (var i = 0; i < links.length; i++) {
    final link = links[i];
    if (link.source == id) {
      node.targetNodes.add(link.target);
      node.targetLinks.add(i);
    }
    if (link.target == id) {
      node.sourceNodes.add(link.source);
      node.sourceLinks.add(i);
    }
  }
}

/// [onPath] holds the nodes on the current recursion path: a link back to one of
/// them is skipped, else depth grows on every trip around the cycle.
void _updateDepthOfTargets(List<SankeyNode> tree, SankeyNode curNode, [Set<SankeyNode>? onPath]) {
  onPath ??= {};
  onPath.add(curNode);
  for (final targetNode in curNode.targetNodes) {
    if (targetNode < 0 || targetNode >= tree.length) continue;
    final target = tree[targetNode];
    if (onPath.contains(target)) continue;
    final newDepth = curNode.depth + 1;
    if (newDepth > target.depth) {
      target.depth = newDepth;
      _updateDepthOfTargets(tree, target, onPath);
    }
  }
  onPath.remove(curNode);
}

List<SankeyNode> _getNodesTree(SankeyData data, double width, double nodeWidth, SankeyAlign align) {
  final links = data.links;
  final tree = <SankeyNode>[];
  for (var index = 0; index < data.nodes.length; index++) {
    final node = SankeyNode(data.nodes[index]);
    _searchTargetsAndSources(node, links, index);
    node.value = math.max(_getSumOfIds(links, node.sourceLinks), _getSumOfIds(links, node.targetLinks));
    tree.add(node);
  }
  for (final node in tree) {
    if (node.sourceNodes.isEmpty) _updateDepthOfTargets(tree, node);
  }
  final maxDepth = tree.isEmpty ? 0 : tree.map((n) => n.depth).reduce(math.max);
  if (maxDepth >= 1) {
    final childWidth = (width - nodeWidth) / maxDepth;
    for (final node in tree) {
      if (node.targetNodes.isEmpty && align == SankeyAlign.justify) node.depth = maxDepth;
      node.x = node.depth * childWidth;
      node.dx = nodeWidth;
    }
  }
  return tree;
}

List<List<SankeyNode>?> _getDepthTree(List<SankeyNode> tree) {
  final result = <List<SankeyNode>?>[];
  for (final node in tree) {
    while (result.length <= node.depth) {
      result.add(null);
    }
    (result[node.depth] ??= []).add(node);
  }
  return result;
}

List<SankeyLink> _updateYOfTree(
  List<List<SankeyNode>?> depthTree,
  double height,
  double nodePadding,
  List<SankeyLinkDatum> links,
  SankeyVerticalAlign verticalAlign,
) {
  var yRatio = double.infinity;
  for (final nodes in depthTree) {
    if (nodes == null) continue;
    final value = nodes.fold(0.0, (a, n) => a + _value(n.value));
    yRatio = math.min(yRatio, value == 0 ? double.infinity : (height - (nodes.length - 1) * nodePadding) / value);
  }
  if (yRatio == double.infinity) yRatio = 0;

  for (final nodes in depthTree) {
    if (nodes == null) continue;
    if (verticalAlign == SankeyVerticalAlign.top) {
      var currentY = 0.0;
      for (final node in nodes) {
        node.dy = node.value * yRatio;
        node.y = currentY;
        currentY += node.dy + nodePadding;
      }
    } else {
      for (var i = 0; i < nodes.length; i++) {
        nodes[i].y = i.toDouble();
        nodes[i].dy = nodes[i].value * yRatio;
      }
    }
  }
  return [for (final l in links) SankeyLink(l.source, l.target, l.value, _getValue(l) * yRatio, l.raw)];
}

void _resolveCollisions(List<List<SankeyNode>?> depthTree, double height, double nodePadding, bool sort) {
  for (final nodes in depthTree) {
    if (nodes == null) continue;
    final n = nodes.length;
    if (sort) _sortBy(nodes, _ascendingY);

    var y0 = 0.0;
    for (var j = 0; j < n; j++) {
      final node = nodes[j];
      final dy = y0 - node.y;
      if (dy > 0) node.y += dy;
      y0 = node.y + node.dy + nodePadding;
    }

    y0 = height + nodePadding;
    for (var j = n - 1; j >= 0; j--) {
      final node = nodes[j];
      final dy = node.y + node.dy + nodePadding - y0;
      if (dy > 0) {
        node.y -= dy;
        y0 = node.y;
      } else {
        break;
      }
    }
  }
}

void _relaxLeftToRight(List<SankeyNode> tree, List<List<SankeyNode>?> depthTree, List<SankeyLink> links, double alpha) {
  final plain = [for (final l in links) SankeyLinkDatum(source: l.source, target: l.target, value: l.value)];
  for (final nodes in depthTree) {
    if (nodes == null) continue;
    for (final node in nodes) {
      if (node.sourceLinks.isNotEmpty) {
        final sourceSum = _getSumOfIds(plain, node.sourceLinks);
        final weightedSum = _getSumWithWeightedSource(tree, links, node.sourceLinks);
        final y = sourceSum == 0 ? _centerY(node) : weightedSum / sourceSum;
        node.y += (y - _centerY(node)) * alpha;
      }
    }
  }
}

void _relaxRightToLeft(List<SankeyNode> tree, List<List<SankeyNode>?> depthTree, List<SankeyLink> links, double alpha) {
  final plain = [for (final l in links) SankeyLinkDatum(source: l.source, target: l.target, value: l.value)];
  for (var i = depthTree.length - 1; i >= 0; i--) {
    final nodes = depthTree[i];
    if (nodes == null) continue;
    for (final node in nodes) {
      if (node.targetLinks.isNotEmpty) {
        final targetSum = _getSumOfIds(plain, node.targetLinks);
        final weightedSum = _getSumWithWeightedTarget(tree, links, node.targetLinks);
        final y = targetSum == 0 ? _centerY(node) : weightedSum / targetSum;
        node.y += (y - _centerY(node)) * alpha;
      }
    }
  }
}

void _updateYOfLinks(List<SankeyNode> tree, List<SankeyLink> links) {
  for (final node in tree) {
    var sy = 0.0;
    var ty = 0.0;
    double byY(int a, int b, int Function(SankeyLink) end) {
      if (a >= links.length || b >= links.length) return 0;
      final ia = end(links[a]), ib = end(links[b]);
      if (ia >= tree.length || ib >= tree.length) return 0;
      return tree[ia].y - tree[ib].y;
    }

    _sortBy(node.targetLinks, (a, b) => byY(a, b, (l) => l.target));
    _sortBy(node.sourceLinks, (a, b) => byY(a, b, (l) => l.source));

    for (final id in node.targetLinks) {
      if (id >= links.length) continue;
      final link = links[id];
      link.sy = sy;
      sy += link.dy;
    }
    for (final id in node.sourceLinks) {
      if (id >= links.length) continue;
      final link = links[id];
      link.ty = ty;
      ty += link.dy;
    }
  }
}

double _getLinkYAtX(SankeyNode sourceNode, SankeyNode targetNode, SankeyLink link, double x) {
  final sourceX = sourceNode.x + sourceNode.dx;
  final targetX = targetNode.x;
  final progress = targetX == sourceX ? 0.0 : (x - sourceX) / (targetX - sourceX);
  final boundedProgress = math.min(math.max(progress, 0), 1).toDouble();
  final sourceY = sourceNode.y + (link.sy ?? 0) + link.dy / 2;
  final targetY = targetNode.y + (link.ty ?? 0) + link.dy / 2;
  return _cubicValue(sourceY, sourceY, targetY, targetY, boundedProgress);
}

class _CollisionItem {
  _CollisionItem.node(SankeyNode this.node)
      : fixed = false,
        _y = 0,
        _dy = 0;
  _CollisionItem.obstacle(double y, double dy)
      : node = null,
        fixed = true,
        _y = y,
        _dy = dy;
  final SankeyNode? node;
  final bool fixed;
  final double _y, _dy;
  double get y => fixed ? _y : node!.y;
  double get dy => fixed ? _dy : node!.dy;
}

void _resolveNodeLinkCollisions(
    List<SankeyNode> tree, List<List<SankeyNode>?> depthTree, List<SankeyLink> links, double height, double nodePadding) {
  final depthByNode = <SankeyNode, int>{};
  for (var depth = 0; depth < depthTree.length; depth++) {
    for (final node in depthTree[depth] ?? const <SankeyNode>[]) {
      depthByNode[node] = depth;
    }
  }

  for (var depth = 0; depth < depthTree.length; depth++) {
    final nodes = depthTree[depth];
    if (nodes == null || nodes.isEmpty) continue;

    final depthX = nodes[0].x + nodes[0].dx / 2;

    final fixedObstacles = <_CollisionItem>[];
    for (final link in links) {
      if (link.source >= tree.length || link.target >= tree.length) continue;
      final sourceNode = tree[link.source], targetNode = tree[link.target];
      final sourceDepth = depthByNode[sourceNode], targetDepth = depthByNode[targetNode];
      if (sourceDepth == null || targetDepth == null) continue;
      if (depth <= math.min(sourceDepth, targetDepth) || depth >= math.max(sourceDepth, targetDepth)) continue;
      final y = _getLinkYAtX(sourceNode, targetNode, link, depthX) - link.dy / 2;
      fixedObstacles.add(_CollisionItem.obstacle(y, link.dy));
    }

    final containedNodeObstacles = [
      for (final o in fixedObstacles)
        if (nodes.any((node) => node.y >= o.y && node.y + node.dy <= o.y + o.dy)) o,
    ];
    if (containedNodeObstacles.isEmpty) continue;

    final items = [for (final node in nodes) _CollisionItem.node(node), ...containedNodeObstacles];
    _sortBy(items, (a, b) => a.y - b.y);

    var nextY = 0.0;
    for (final item in items) {
      if (item.fixed) {
        nextY = math.max(nextY, item.y + item.dy + nodePadding);
        continue;
      }
      if (item.node!.y < nextY) item.node!.y = nextY;
      nextY = item.node!.y + item.node!.dy + nodePadding;
    }

    _sortBy(items, (a, b) => a.y - b.y);

    var previousY = height + nodePadding;
    for (var i = items.length - 1; i >= 0; i--) {
      final item = items[i];
      if (item.fixed) {
        previousY = math.min(previousY, item.y - nodePadding);
        continue;
      }
      final dy = item.node!.y + item.dy + nodePadding - previousY;
      if (dy > 0) item.node!.y -= dy;
      previousY = item.node!.y;
    }
  }
}

/// `computeData`.
SankeyLayout computeSankeyData({
  required SankeyData data,
  required double width,
  required double height,
  int iterations = 32,
  double nodeWidth = 10,
  double nodePadding = 10,
  bool sort = true,
  SankeyVerticalAlign verticalAlign = SankeyVerticalAlign.justify,
  SankeyAlign align = SankeyAlign.justify,
}) {
  final tree = _getNodesTree(data, width, nodeWidth, align);
  final depthTree = _getDepthTree(tree);
  final links = _updateYOfTree(depthTree, height, nodePadding, data.links, verticalAlign);

  _resolveCollisions(depthTree, height, nodePadding, sort);

  if (verticalAlign == SankeyVerticalAlign.justify) {
    var alpha = 1.0;
    for (var i = 1; i <= iterations; i++) {
      alpha *= 0.99;
      _relaxRightToLeft(tree, depthTree, links, alpha);
      _resolveCollisions(depthTree, height, nodePadding, sort);
      _relaxLeftToRight(tree, depthTree, links, alpha);
      _resolveCollisions(depthTree, height, nodePadding, sort);
    }
  }

  _updateYOfLinks(tree, links);
  _resolveNodeLinkCollisions(tree, depthTree, links, height, nodePadding);
  _updateYOfLinks(tree, links);
  return SankeyLayout(tree, links);
}

/// `NodeProps`: [x] and [y] include the margin; [payload] is the laid out node.
class SankeyNodeProps {
  const SankeyNodeProps({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.index,
    required this.payload,
    this.style,
  });
  final double x, y, width, height;
  final int index;
  final SankeyNode payload;

  /// The `node` option when it is an [SvgStyle], under the data entry's own styles ([sankeyEntryStyle]).
  final SvgStyle? style;
}

/// `LinkProps`; [payload] has its `source` and `target` as nodes.
class SankeyLinkProps {
  const SankeyLinkProps({
    required this.sourceX,
    required this.targetX,
    required this.sourceY,
    required this.targetY,
    required this.sourceControlX,
    required this.targetControlX,
    required this.sourceRelativeY,
    required this.targetRelativeY,
    required this.linkWidth,
    required this.index,
    required this.link,
    required this.source,
    required this.target,
    this.style,
  });
  final double sourceX, targetX, sourceY, targetY, sourceControlX, targetControlX;
  final double sourceRelativeY, targetRelativeY, linkWidth;
  final int index;
  final SankeyLink link;
  final SankeyNode source, target;

  /// The `link` option when it is an [SvgStyle], under the data entry's own styles ([sankeyEntryStyle]).
  final SvgStyle? style;

  /// `{...link, source: sourceNode, target: targetNode}` as a JS object.
  Map<String, Object?> get payload => {
        ...link.raw,
        'dy': link.dy,
        'sy': link.sy,
        'ty': link.ty,
        'source': source.toMap(),
        'target': target.toMap(),
      };
}

/// `getEntrySvgProps` merged over the `node` / `link` [base]: a `fill`,
/// `stroke`, `strokeWidth`, `fillOpacity` or `strokeOpacity` of the data
/// [entry] wins, a null one keeps [base]'s.
SvgStyle? sankeyEntryStyle(Map<String, Object?> entry, SvgStyle? base) {
  double? number(String k) => switch (entry[k]) { final num n => n.toDouble(), _ => null };
  final fill = cssFillOf(entry['fill']), stroke = cssStrokeOf(entry['stroke']);
  final strokeWidth = number('strokeWidth'), fillOpacity = number('fillOpacity'), strokeOpacity = number('strokeOpacity');
  if (fill == null && stroke == null && strokeWidth == null && fillOpacity == null && strokeOpacity == null) return base;
  return SvgStyle(
    fill: fill ?? base?.fill,
    fillOpacity: fillOpacity ?? base?.fillOpacity,
    stroke: stroke ?? base?.stroke,
    strokeWidth: strokeWidth ?? base?.strokeWidth,
    strokeOpacity: strokeOpacity ?? base?.strokeOpacity,
    strokeDasharray: base?.strokeDasharray,
    r: base?.r,
    radius: base?.radius,
  );
}

/// `buildLinkProps`; null when a link points at a missing node.
SankeyLinkProps? buildLinkProps({
  required SankeyLink link,
  required List<SankeyNode> nodes,
  required double top,
  required double left,
  required int i,
  required double linkCurvature,
  SvgStyle? style,
}) {
  if (link.source < 0 || link.target < 0 || link.source >= nodes.length || link.target >= nodes.length) return null;
  final sourceNode = nodes[link.source], targetNode = nodes[link.target];
  final sourceRelativeY = link.sy ?? double.nan, targetRelativeY = link.ty ?? double.nan, linkWidth = link.dy;
  final sourceX = sourceNode.x + sourceNode.dx + left;
  final targetX = targetNode.x + left;
  // interpolationGenerator(sourceX, targetX)
  final kb = targetX - sourceX;
  return SankeyLinkProps(
    sourceX: sourceX,
    targetX: targetX,
    sourceY: sourceNode.y + sourceRelativeY + linkWidth / 2 + top,
    targetY: targetNode.y + targetRelativeY + linkWidth / 2 + top,
    sourceControlX: sourceX + kb * linkCurvature,
    targetControlX: sourceX + kb * (1 - linkCurvature),
    sourceRelativeY: sourceRelativeY,
    targetRelativeY: targetRelativeY,
    linkWidth: linkWidth,
    index: i,
    link: link,
    source: sourceNode,
    target: targetNode,
    style: style,
  );
}

/// `buildNodeProps`.
SankeyNodeProps buildNodeProps({
  required SankeyNode node,
  required double top,
  required double left,
  required int i,
  SvgStyle? style,
}) =>
    SankeyNodeProps(x: node.x + left, y: node.y + top, width: node.dx, height: node.dy, index: i, payload: node, style: style);

/// `getNodeCoordinateOfTooltip`.
Offset sankeyNodeTooltipCoordinate(SankeyNodeProps p) => Offset(p.x + p.width / 2, p.y + p.height / 2);

/// `getLinkCoordinateOfTooltip`.
Offset sankeyLinkTooltipCoordinate(SankeyLinkProps p) => Offset((p.sourceX + p.targetX) / 2, (p.sourceY + p.targetY) / 2);

/// `sankeyPayloadSearcher` + `combineTooltipPayload`'s non-array branch: the
/// one tooltip entry of item `type-index`, or null. The searched item's `color`
/// is `getRenderedPaint`: the node's own fill or the link's own stroke, which
/// wins over the series [fill].
TooltipPayloadEntry sankeyTooltipEntry({
  required SankeyElementType type,
  required int index,
  required List<SankeyNodeProps> nodes,
  required List<SankeyLinkProps> links,
  required Object? dataKey,
  required Object? nameKey,
  Object? name,
  Color? fill,
  Color? stroke,
}) {
  // An index with no item (the keyboard's '0') leaves the searcher result undefined.
  Object? searched;
  Object? payload, itemName, itemValue;
  Color? color;
  // getRenderedPaint: a color that paints, not none.
  Color? paint(Color? c) => isCssNone(c) ? null : c;
  final inRange = index >= 0 && index < (type == SankeyElementType.node ? nodes.length : links.length);
  if (!inRange) {
    // searched stays null
  } else if (type == SankeyElementType.node) {
    final node = nodes[index].payload.toMap();
    payload = node;
    color = paint(nodes[index].style?.fill);
    itemName = getValueByDataKey(node, nameKey, '');
    itemValue = getValueByDataKey(node, 'value');
  } else {
    final p = links[index].payload;
    payload = p;
    color = paint(links[index].style?.stroke);
    final sourceName = getValueByDataKey(p['source'], nameKey, '');
    final targetName = getValueByDataKey(p['target'], nameKey, '');
    itemName = '${jsString(sourceName)} - ${jsString(targetName)}';
    itemValue = getValueByDataKey(p, 'value');
  }
  if (inRange) searched = <String, Object?>{'payload': payload, 'name': itemName, 'value': itemValue, 'color': ?color};
  final n = getValueByDataKey(searched, nameKey) ?? name;
  return TooltipPayloadEntry(
    dataKey: dataKey,
    name: n == null ? null : jsString(n),
    value: getValueByDataKey(searched, dataKey),
    payload: searched,
    color: color ?? fill,
    fill: fill,
    stroke: stroke,
    unit: '',
  );
}

/// `selectChartViewBox` for a Sankey: the chart less its margin.
Rect sankeyViewBox(Size size, Margin margin) => Rect.fromLTWH(margin.left, margin.top,
    math.max(size.width - margin.left - margin.right, 0), math.max(size.height - margin.top - margin.bottom, 0));
