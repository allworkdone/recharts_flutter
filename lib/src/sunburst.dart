// Port of the geometry in src/chart/SunburstChart.tsx: getMaxDepthOf and the
// recursive drawArcs (rScale = scaleLinear([0, root[dataKey]], [0, endAngle]),
// tooltip indexes like `[0]children[1]`, positions keyed by node name) and
// resolveSectorProps without a theme.

import 'dart:ui';

import 'core/polar_utils.dart';
import 'core/scale.dart';
import 'util.dart';
import 'css_color.dart';

/// One sector `drawArcs` pushes.
class SunburstSector {
  const SunburstSector({
    required this.node,
    required this.startAngle,
    required this.endAngle,
    required this.innerRadius,
    required this.outerRadius,
    required this.fill,
    required this.stroke,
    required this.strokeWidth,
    this.fillOpacity,
    this.strokeOpacity,
    required this.textPosition,
  });

  /// The data node with its `tooltipIndex`.
  final Map<String, Object?> node;
  final double startAngle, endAngle, innerRadius, outerRadius;

  /// The entry's own `fill`, else the parent's, else the chart's.
  final Color fill;

  /// The entry's `stroke` / `strokeWidth`, else the chart's `stroke` / `padding`.
  final Color? stroke;
  final double strokeWidth;
  final double? fillOpacity, strokeOpacity;

  /// Where the label is anchored (`textX + cx`, `cy - textY`).
  final Offset textPosition;
}

class SunburstLayout {
  const SunburstLayout(
      {required this.sectors, required this.positions, required this.thickness, required this.byIndex});
  final List<SunburstSector> sectors;

  /// The original data node by `tooltipIndex` (`get(data.children, index)`).
  final Map<String, Map<String, Object?>> byIndex;

  /// `positions`: the tooltip coordinate by node name; a repeated name keeps the last one.
  final Map<String, Offset> positions;
  final double thickness;
}

/// `+value`: undefined is NaN.
double _num(Object? v) => v == null ? double.nan : jsNumber(v);

int getMaxDepthOf(Map<String, Object?> node) {
  final children = node['children'];
  if (children is! List || children.isEmpty) return 1;
  var max = 0;
  for (final c in children) {
    final d = getMaxDepthOf((c as Map).cast<String, Object?>());
    if (d > max) max = d;
  }
  return 1 + max;
}

SunburstLayout computeSunburst({
  required Map<String, Object?> data,
  required double width,
  required double height,
  required String dataKey,
  required double padding,
  required double ringPadding,
  required double innerRadius,
  double? outerRadius,
  double? cx,
  double? cy,
  required double startAngle,
  required double endAngle,
  required Color fill,
  Color? stroke,
}) {
  final outer = outerRadius ?? (width < height ? width : height) / 2;
  final centerX = cx ?? width / 2, centerY = cy ?? height / 2;
  final total = _num(data[dataKey]);
  final rScale = LinearScale(domain: [0, total], range: [0, endAngle]);
  final thickness = (outer - innerRadius) / getMaxDepthOf(data);
  final sectors = <SunburstSector>[];
  final positions = <String, Offset>{};
  final byIndex = <String, Map<String, Object?>>{};

  void drawArcs(List? childNodes, double radius, double innerR, double initialAngle, Color? childColor,
      String? nestedIndex, int depth) {
    if (childNodes == null) return;
    var currentAngle = initialAngle;
    for (var i = 0; i < childNodes.length; i++) {
      final d = (childNodes[i] as Map).cast<String, Object?>();
      final tooltipIndex = depth == 1 ? '[$i]' : '${nestedIndex ?? ''}children[$i]';
      final node = {...d, 'tooltipIndex': tooltipIndex};
      byIndex[tooltipIndex] = d;
      final arcLength = rScale.map(_num(d[dataKey])) ?? double.nan;
      final start = currentAngle;
      final fillColor = cssFillOf(d['fill']) ?? childColor ?? fill;
      double? number(String k) => switch (d[k]) { final num n => n.toDouble(), _ => null };
      final text = polarToCartesian(0, 0, innerR + radius / 2, -(start + arcLength - arcLength / 2));
      currentAngle += arcLength;
      sectors.add(SunburstSector(
        node: node,
        startAngle: start,
        endAngle: start + arcLength,
        innerRadius: innerR,
        outerRadius: innerR + radius,
        fill: fillColor,
        stroke: cssStrokeOf(d['stroke']) ?? stroke,
        strokeWidth: number('strokeWidth') ?? padding,
        fillOpacity: number('fillOpacity'),
        strokeOpacity: number('strokeOpacity'),
        textPosition: Offset(text.dx + centerX, centerY - text.dy),
      ));
      final tooltip = polarToCartesian(centerX, centerY, innerR + radius / 2, start);
      positions[jsString(d['name'])] = tooltip;
      drawArcs(d['children'] as List?, radius, innerR + radius + ringPadding, start, fillColor, tooltipIndex, depth + 1);
    }
  }

  drawArcs(data['children'] as List?, thickness, innerRadius, startAngle, null, null, 1);
  return SunburstLayout(sectors: sectors, positions: positions, thickness: thickness, byIndex: byIndex);
}
