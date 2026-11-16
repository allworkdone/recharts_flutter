// SVG shape helpers: getRectanglePath from src/shape/Rectangle.tsx, stroke
// dashing as SVG/Skia do it (per subpath), and the legend icons of
// src/component/DefaultLegendContent.tsx (symbols from core/symbols.dart).

import 'dart:math' as math;
import 'dart:ui' hide Gradient;

import 'package:flutter/painting.dart' show Gradient;

import '../components.dart';
import '../core/symbols.dart';
import '../css_color.dart' show cssNone;
import '../util.dart';

/// `getRectanglePath(x, y, width, height, radius)`.
Path rectanglePath(double x, double y, double width, double height, Object radius) {
  final roundedWidth = round4(width), roundedHeight = round4(height);
  final maxRadius = math.min(roundedWidth.abs() / 2, roundedHeight.abs() / 2);
  final ySign = roundedHeight >= 0 ? 1 : -1;
  final xSign = roundedWidth >= 0 ? 1 : -1;
  final clockWise = (roundedHeight >= 0 && roundedWidth >= 0) || (roundedHeight < 0 && roundedWidth < 0);
  final path = Path();
  void arc(double r, double ex, double ey) =>
      path.arcToPoint(Offset(ex, ey), radius: Radius.circular(r), clockwise: clockWise);

  if (maxRadius > 0 && radius is List) {
    final r = [for (var i = 0; i < 4; i++) math.min(i < radius.length ? (radius[i] as num).toDouble() : 0.0, maxRadius)];
    path.moveTo(x, y + ySign * r[0]);
    if (r[0] > 0) arc(r[0], x + xSign * r[0], y);
    path.lineTo(x + width - xSign * r[1], y);
    if (r[1] > 0) arc(r[1], x + width, y + ySign * r[1]);
    path.lineTo(x + width, y + height - ySign * r[2]);
    if (r[2] > 0) arc(r[2], x + width - xSign * r[2], y + height);
    path.lineTo(x + xSign * r[3], y + height);
    if (r[3] > 0) arc(r[3], x, y + height - ySign * r[3]);
    path.close();
  } else if (maxRadius > 0 && radius is num && radius > 0) {
    final r = math.min(maxRadius, radius.toDouble());
    path.moveTo(x, y + ySign * r);
    arc(r, x + xSign * r, y);
    path.lineTo(x + width - xSign * r, y);
    arc(r, x + width, y + ySign * r);
    path.lineTo(x + width, y + height - ySign * r);
    arc(r, x + width - xSign * r, y + height);
    path.lineTo(x + xSign * r, y + height);
    arc(r, x, y + height - ySign * r);
    path.close();
  } else {
    path
      ..moveTo(x, y)
      ..lineTo(x + width, y)
      ..lineTo(x + width, y + height)
      ..lineTo(x, y + height)
      ..close();
  }
  return path;
}

/// Applies an SVG `stroke-dasharray`; the pattern restarts on every subpath,
/// which is what Chrome (Skia) does.
Path dashPath(Path source, List<double> dasharray) {
  final pattern = dasharray.length.isOdd ? [...dasharray, ...dasharray] : dasharray;
  final total = pattern.fold<double>(0, (a, b) => a + b);
  if (pattern.isEmpty || total <= 0 || pattern.any((d) => d < 0)) return source;
  final out = Path();
  for (final metric in source.computeMetrics()) {
    var distance = 0.0;
    var i = 0;
    while (distance < metric.length) {
      final len = pattern[i % pattern.length];
      if (i.isEven && len > 0) {
        out.addPath(metric.extractPath(distance, math.min(distance + len, metric.length)), Offset.zero);
      }
      distance += len;
      i++;
    }
  }
  return out;
}

Paint strokePaint(Color color, double width, {double opacity = 1}) => Paint()
  ..style = PaintingStyle.stroke
  ..color = opacity == 1 ? color : color.withValues(alpha: color.a * opacity)
  ..strokeWidth = width
  ..strokeMiterLimit = 4
  ..isAntiAlias = true;

Paint fillPaint(Color color, {double opacity = 1}) => Paint()
  ..style = PaintingStyle.fill
  ..color = opacity == 1 ? color : color.withValues(alpha: color.a * opacity);

/// A fill that is a [Color] or a [Gradient] laid over [bounds] (SVG's
/// objectBoundingBox); `fill-opacity` scales the gradient's stop opacities.
// ponytail: diagonal gradients on non-square boxes are not skewed like SVG's
// bounding-box transform; vertical and horizontal ones match.
Paint fillPaintOf(Object fill, Rect bounds, {double opacity = 1}) => fill is Gradient
    ? (Paint()
      ..style = PaintingStyle.fill
      ..shader = (opacity == 1 ? fill : fill.scale(opacity)).createShader(bounds))
    : fillPaint(fill as Color, opacity: opacity);

void drawStroke(Canvas canvas, Path path, Paint paint, List<double>? dasharray) {
  canvas.drawPath(dasharray == null || dasharray.isEmpty ? path : dashPath(path, dasharray), paint);
}

/// DefaultLegendContent `Icon`, drawn in its 32x32 viewBox scaled to [iconSize].
void paintLegendIcon(Canvas canvas, LegendPayload data, LegendType? iconType, Color inactiveColor, double iconSize) {
  const size = 32.0, half = size / 2, sixth = size / 6, third = size / 3;
  final color = data.inactive ? inactiveColor : (data.color ?? const Color(0xFF000000));
  final type = iconType ?? data.type;
  if (type == LegendType.none) return;
  final dot = data.dot;
  final dotColors = dot == null ? null : legendIconDotColors(dot, data, inactiveColor);
  // A symbol at the center, filled and stroked 3 wide with round joins.
  void symbol(SymbolType type, double diameter, Color? fill, Color? stroke) {
    final path = symbolPath(type, diameter, sizeType: SymbolSizeType.diameter).shift(const Offset(half, half));
    if (fill != null) canvas.drawPath(path, fillPaint(fill));
    if (stroke != null) canvas.drawPath(path, strokePaint(stroke, 3)..strokeJoin = StrokeJoin.round);
  }

  canvas.save();
  canvas.scale(iconSize / size);
  switch (type) {
    case LegendType.plainline:
      final path = Path()
        ..moveTo(0, half)
        ..lineTo(size, half);
      drawStroke(canvas, path, strokePaint(color, 4), data.strokeDasharray);
    // LineWithSymbolIcon: the line stops at the edge of the dot symbol.
    case LegendType.line when dot != null:
      final halfWidth = symbolHalfWidth(dot.symbol, 20, SymbolSizeType.diameter);
      final path = Path()
        ..moveTo(0, half)
        ..lineTo(half - halfWidth, half)
        ..moveTo(half + halfWidth, half)
        ..lineTo(size, half);
      canvas.drawPath(path, strokePaint(color, 4));
      symbol(dot.symbol, 20, dotColors!.fill, dotColors.stroke ?? color);
    case LegendType.line:
      final path = Path()
        ..moveTo(0, half)
        ..lineTo(third, half)
        ..arcToPoint(const Offset(2 * third, half), radius: const Radius.circular(sixth), largeArc: true)
        ..lineTo(size, half)
        ..moveTo(2 * third, half)
        ..arcToPoint(const Offset(third, half), radius: const Radius.circular(sixth), largeArc: true);
      canvas.drawPath(path, strokePaint(color, 4));
    case LegendType.rect:
      canvas.drawRect(const Rect.fromLTWH(0, size / 8, size, size * 3 / 4), fillPaint(color));
    // DotSymbolIcon: the stroke stays inside the icon.
    case _ when dot != null && dot.symbol.name == type.name:
      final stroke = dotColors!.stroke;
      final hasStroke = stroke != null && stroke != cssNone;
      symbol(dot.symbol, hasStroke ? size - 3 : size, dotColors.fill ?? color, hasStroke ? stroke : null);
    default:
      final symbol = SymbolType.values.asNameMap()[type.name] ?? SymbolType.circle;
      canvas.drawPath(symbolPath(symbol, size, sizeType: SymbolSizeType.diameter).shift(const Offset(half, half)),
          fillPaint(color));
  }
  canvas.restore();
}

/// `getIconDotColors`: a hidden item draws its symbol in [inactiveColor],
/// except for a fill that is not the item color (Line's white dots).
({Color? fill, Color? stroke}) legendIconDotColors(LegendPayloadDot dot, LegendPayload data, Color inactiveColor) {
  if (!data.inactive) return (fill: dot.fill, stroke: dot.stroke);
  bool hasColor(Color? c) => c != null && c != cssNone;
  final isItemFill = hasColor(dot.fill) && (dot.fill == data.color || dot.fill == dot.stroke);
  return (fill: isItemFill ? inactiveColor : dot.fill, stroke: hasColor(dot.stroke) ? inactiveColor : dot.stroke);
}

/// SVG color with optional opacity.
Color colorWithOpacity(Color c, double? opacity) => opacity == null ? c : c.withValues(alpha: c.a * opacity);
