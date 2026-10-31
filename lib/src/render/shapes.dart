// SVG shape helpers: getRectanglePath from src/shape/Rectangle.tsx, stroke
// dashing as SVG/Skia do it (per subpath), d3 symbols (src/shape/Symbols.tsx
// calculateAreaSize + d3-shape symbol*), and the legend icons of
// src/component/DefaultLegendContent.tsx.

import 'dart:math' as math;
import 'dart:ui';

import '../components.dart';
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

void drawStroke(Canvas canvas, Path path, Paint paint, List<double>? dasharray) {
  canvas.drawPath(dasharray == null || dasharray.isEmpty ? path : dashPath(path, dasharray), paint);
}

/// `calculateAreaSize(size, 'diameter', type)` from Symbols.tsx.
double _symbolArea(double size, LegendType type) {
  const angle = 18 * math.pi / 180;
  return switch (type) {
    LegendType.cross => 5 * size * size / 9,
    LegendType.diamond => 0.5 * size * size / math.sqrt(3),
    LegendType.square => size * size,
    LegendType.star => 1.25 * size * size * (math.tan(angle) - math.tan(angle * 2) * math.pow(math.tan(angle), 2)),
    LegendType.triangle => math.sqrt(3) * size * size / 4,
    LegendType.wye => (21 - 10 * math.sqrt(3)) * size * size / 8,
    _ => math.pi * size * size / 4,
  };
}

/// d3-shape symbol path centered at the origin.
Path symbolPath(LegendType type, double diameter) {
  final size = _symbolArea(diameter, type);
  final p = Path();
  switch (type) {
    case LegendType.cross:
      final r = math.sqrt(size / 5) / 2;
      p
        ..moveTo(-3 * r, -r)
        ..lineTo(-r, -r)
        ..lineTo(-r, -3 * r)
        ..lineTo(r, -3 * r)
        ..lineTo(r, -r)
        ..lineTo(3 * r, -r)
        ..lineTo(3 * r, r)
        ..lineTo(r, r)
        ..lineTo(r, 3 * r)
        ..lineTo(-r, 3 * r)
        ..lineTo(-r, r)
        ..lineTo(-3 * r, r)
        ..close();
    case LegendType.diamond:
      final tan30 = math.sqrt(1 / 3);
      final y = math.sqrt(size / (tan30 * 2)), x = y * tan30;
      p
        ..moveTo(0, -y)
        ..lineTo(x, 0)
        ..lineTo(0, y)
        ..lineTo(-x, 0)
        ..close();
    case LegendType.square:
      final w = math.sqrt(size), x = -w / 2;
      p.addRect(Rect.fromLTWH(x, x, w, w));
    case LegendType.star:
      const ka = 0.89081309152928522810;
      final kr = math.sin(math.pi / 10) / math.sin(7 * math.pi / 10);
      final kx = math.sin(2 * math.pi / 10) * kr, ky = -math.cos(2 * math.pi / 10) * kr;
      final r = math.sqrt(size * ka), x = kx * r, y = ky * r;
      p
        ..moveTo(0, -r)
        ..lineTo(x, y);
      for (var i = 1; i < 5; i++) {
        final a = 2 * math.pi * i / 5, c = math.cos(a), s = math.sin(a);
        p
          ..lineTo(s * r, -c * r)
          ..lineTo(c * x - s * y, s * x + c * y);
      }
      p.close();
    case LegendType.triangle:
      final y = -math.sqrt(size / (math.sqrt(3) * 3));
      p
        ..moveTo(0, y * 2)
        ..lineTo(-math.sqrt(3) * y, -y)
        ..lineTo(math.sqrt(3) * y, -y)
        ..close();
    case LegendType.wye:
      const c = -0.5;
      final s = math.sqrt(3) / 2, k = 1 / math.sqrt(12), a = (k / 2 + 1) * 3;
      final r = math.sqrt(size / a);
      final x0 = r / 2, y0 = r * k, x1 = x0, y1 = r * k + r, x2 = -x1, y2 = y1;
      p
        ..moveTo(x0, y0)
        ..lineTo(x1, y1)
        ..lineTo(x2, y2)
        ..lineTo(c * x0 - s * y0, s * x0 + c * y0)
        ..lineTo(c * x1 - s * y1, s * x1 + c * y1)
        ..lineTo(c * x2 - s * y2, s * x2 + c * y2)
        ..lineTo(c * x0 + s * y0, c * y0 - s * x0)
        ..lineTo(c * x1 + s * y1, c * y1 - s * x1)
        ..lineTo(c * x2 + s * y2, c * y2 - s * x2)
        ..close();
    default:
      p.addOval(Rect.fromCircle(center: Offset.zero, radius: math.sqrt(size / math.pi)));
  }
  return p;
}

/// DefaultLegendContent `Icon`, drawn in its 32x32 viewBox scaled to [iconSize].
void paintLegendIcon(Canvas canvas, LegendPayload data, LegendType? iconType, Color inactiveColor, double iconSize) {
  const size = 32.0, half = size / 2, sixth = size / 6, third = size / 3;
  final color = data.inactive ? inactiveColor : (data.color ?? const Color(0xFF000000));
  final type = iconType ?? data.type;
  if (type == LegendType.none) return;
  canvas.save();
  canvas.scale(iconSize / size);
  switch (type) {
    case LegendType.plainline:
      final path = Path()
        ..moveTo(0, half)
        ..lineTo(size, half);
      drawStroke(canvas, path, strokePaint(color, 4), data.strokeDasharray);
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
    default:
      canvas.drawPath(symbolPath(type, size).shift(const Offset(half, half)), fillPaint(color));
  }
  canvas.restore();
}

/// SVG color with optional opacity.
Color colorWithOpacity(Color c, double? opacity) => opacity == null ? c : c.withValues(alpha: c.a * opacity);
