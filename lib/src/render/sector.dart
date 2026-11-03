// Port of src/shape/Sector.tsx (getSectorPath, getSectorWithCorner,
// getTangentCircle; numbers rounded like roundTemplateLiteral in
// src/util/round.ts) and a small SVG path-data reader that turns the `d`
// string into a Path. SVG `A` arcs go through Path.arcToPoint, Skia's
// endpoint-parameterized arc, the same call Chrome makes for SVG arcs.

import 'dart:math' as math;
import 'dart:ui';

import '../core/polar_utils.dart';
import '../util.dart';

/// Recharts' `GeometrySector` plus the Sector-only props.
class SectorGeometry {
  const SectorGeometry({
    this.cx = 0,
    this.cy = 0,
    this.innerRadius = 0,
    this.outerRadius = 0,
    this.startAngle = 0,
    this.endAngle = 0,
    this.cornerRadius = 0,
    this.forceCornerRadius = false,
    this.cornerIsExternal = false,
  });
  final double cx, cy, innerRadius, outerRadius, startAngle, endAngle;

  /// A number or a percent string of `outerRadius - innerRadius`.
  final Object cornerRadius;
  final bool forceCornerRadius;
  final bool cornerIsExternal;
}

String _n(num v) => jsString(round4(v));

double _deltaAngle(double startAngle, double endAngle) =>
    mathSign(endAngle - startAngle) * math.min((endAngle - startAngle).abs(), 359.999);

({Offset center, Offset circleTangency, Offset lineTangency, double theta}) _tangentCircle(
    double cx, double cy, double radius, double angle, int sign, bool isExternal, double cornerRadius,
    bool cornerIsExternal) {
  final centerRadius = cornerRadius * (isExternal ? 1 : -1) + radius;
  final theta = math.asin(cornerRadius / centerRadius) / radian;
  final centerAngle = cornerIsExternal ? angle : angle + sign * theta;
  final center = polarToCartesian(cx, cy, centerRadius, centerAngle);
  final circleTangency = polarToCartesian(cx, cy, radius, centerAngle);
  final lineTangencyAngle = cornerIsExternal ? angle - sign * theta : angle;
  final lineTangency = polarToCartesian(cx, cy, centerRadius * math.cos(theta * radian), lineTangencyAngle);
  return (center: center, circleTangency: circleTangency, lineTangency: lineTangency, theta: theta);
}

String _sectorPath(double cx, double cy, double innerRadius, double outerRadius, double startAngle, double endAngle) {
  final angle = _deltaAngle(startAngle, endAngle);
  // When the angle of sector equals to 360, star point and end point coincide
  final tempEndAngle = startAngle + angle;
  final os = polarToCartesian(cx, cy, outerRadius, startAngle);
  final oe = polarToCartesian(cx, cy, outerRadius, tempEndAngle);
  final large = angle.abs() > 180 ? 1 : 0;
  var path = 'M ${_n(os.dx)},${_n(os.dy)} A ${_n(outerRadius)},${_n(outerRadius)},0, '
      '$large,${startAngle > tempEndAngle ? 1 : 0}, ${_n(oe.dx)},${_n(oe.dy)}';
  if (innerRadius > 0) {
    final ins = polarToCartesian(cx, cy, innerRadius, startAngle);
    final ine = polarToCartesian(cx, cy, innerRadius, tempEndAngle);
    path += ' L ${_n(ine.dx)},${_n(ine.dy)} A ${_n(innerRadius)},${_n(innerRadius)},0, '
        '$large,${startAngle <= tempEndAngle ? 1 : 0}, ${_n(ins.dx)},${_n(ins.dy)} Z';
  } else {
    path += ' L ${_n(cx)},${_n(cy)} Z';
  }
  return path;
}

String _sectorWithCorner(double cx, double cy, double innerRadius, double outerRadius, double cornerRadius,
    bool forceCornerRadius, bool cornerIsExternal, double startAngle, double endAngle) {
  final sign = mathSign(endAngle - startAngle);
  final s = _tangentCircle(cx, cy, outerRadius, startAngle, sign, false, cornerRadius, cornerIsExternal);
  final e = _tangentCircle(cx, cy, outerRadius, endAngle, -sign, false, cornerRadius, cornerIsExternal);
  final outerArcAngle =
      cornerIsExternal ? (startAngle - endAngle).abs() : (startAngle - endAngle).abs() - s.theta - e.theta;
  final cr = _n(cornerRadius);
  final sweep = sign < 0 ? 1 : 0;
  if (outerArcAngle < 0) {
    if (forceCornerRadius) {
      return 'M ${_n(s.lineTangency.dx)},${_n(s.lineTangency.dy)} a$cr,$cr,0,0,1,${_n(cornerRadius * 2)},0 '
          'a$cr,$cr,0,0,1,${_n(-cornerRadius * 2)},0';
    }
    return _sectorPath(cx, cy, innerRadius, outerRadius, startAngle, endAngle);
  }
  var path = 'M ${_n(s.lineTangency.dx)},${_n(s.lineTangency.dy)} '
      'A$cr,$cr,0,0,$sweep,${_n(s.circleTangency.dx)},${_n(s.circleTangency.dy)} '
      'A${_n(outerRadius)},${_n(outerRadius)},0,${outerArcAngle > 180 ? 1 : 0},$sweep,'
      '${_n(e.circleTangency.dx)},${_n(e.circleTangency.dy)} '
      'A$cr,$cr,0,0,$sweep,${_n(e.lineTangency.dx)},${_n(e.lineTangency.dy)}';
  if (innerRadius > 0) {
    final si = _tangentCircle(cx, cy, innerRadius, startAngle, sign, true, cornerRadius, cornerIsExternal);
    final ei = _tangentCircle(cx, cy, innerRadius, endAngle, -sign, true, cornerRadius, cornerIsExternal);
    final innerArcAngle =
        cornerIsExternal ? (startAngle - endAngle).abs() : (startAngle - endAngle).abs() - si.theta - ei.theta;
    if (innerArcAngle < 0 && cornerRadius == 0) return '$path L${jsString(cx)},${jsString(cy)}Z';
    path += ' L${_n(ei.lineTangency.dx)},${_n(ei.lineTangency.dy)} '
        'A$cr,$cr,0,0,$sweep,${_n(ei.circleTangency.dx)},${_n(ei.circleTangency.dy)} '
        'A${_n(innerRadius)},${_n(innerRadius)},0,${innerArcAngle > 180 ? 1 : 0},${sign > 0 ? 1 : 0},'
        '${_n(si.circleTangency.dx)},${_n(si.circleTangency.dy)} '
        'A$cr,$cr,0,0,$sweep,${_n(si.lineTangency.dx)},${_n(si.lineTangency.dy)}Z';
  } else {
    path += ' L${_n(cx)},${_n(cy)}Z';
  }
  return path;
}

/// The `d` attribute `<Sector>` renders (whitespace collapsed), or null when
/// it renders nothing.
String? sectorPathData(SectorGeometry s) {
  if (s.outerRadius < s.innerRadius || s.startAngle == s.endAngle) return null;
  final deltaRadius = s.outerRadius - s.innerRadius;
  final cr = getPercentValue(s.cornerRadius, deltaRadius, 0, true);
  final d = cr > 0 && (s.startAngle - s.endAngle).abs() < 360
      ? _sectorWithCorner(s.cx, s.cy, s.innerRadius, s.outerRadius, math.min(cr, deltaRadius / 2),
          s.forceCornerRadius, s.cornerIsExternal, s.startAngle, s.endAngle)
      : _sectorPath(s.cx, s.cy, s.innerRadius, s.outerRadius, s.startAngle, s.endAngle);
  // Chrome ignores a `d` with NaN or Infinity in it, so such a sector paints nothing. A NaN
  // innerRadius alone leaves `d` clean ('L cx,cy Z'): a full slice to the centre, as in Chrome.
  return d.contains('NaN') || d.contains('Infinity') ? null : d;
}

/// The painted sector; null when `<Sector>` renders nothing.
Path? sectorPath(SectorGeometry s) {
  final d = sectorPathData(s);
  return d == null ? null : parseSvgPathData(d);
}

final _token = RegExp(r'[MmLlAaZz]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?');

/// Reads SVG path data made of M, L, A and Z commands (absolute or relative).
Path parseSvgPathData(String d) {
  final tokens = _token.allMatches(d).map((m) => m[0]!).toList();
  final path = Path();
  var i = 0;
  var cmd = '';
  double next() => double.parse(tokens[i++]);
  while (i < tokens.length) {
    if ('MmLlAaZz'.contains(tokens[i])) cmd = tokens[i++];
    switch (cmd) {
      case 'M':
        path.moveTo(next(), next());
        cmd = 'L';
      case 'm':
        path.relativeMoveTo(next(), next());
        cmd = 'l';
      case 'L':
        path.lineTo(next(), next());
      case 'l':
        path.relativeLineTo(next(), next());
      case 'A' || 'a':
        final rx = next(), ry = next(), rotation = next();
        final largeArc = next() != 0, sweep = next() != 0;
        final x = next(), y = next();
        if (cmd == 'A') {
          path.arcToPoint(Offset(x, y),
              radius: Radius.elliptical(rx, ry), rotation: rotation, largeArc: largeArc, clockwise: sweep);
        } else {
          path.relativeArcToPoint(Offset(x, y),
              radius: Radius.elliptical(rx, ry), rotation: rotation, largeArc: largeArc, clockwise: sweep);
        }
      case 'Z' || 'z':
        path.close();
      default:
        throw FormatException('Unsupported path command', d);
    }
  }
  return path;
}

/// Whether [p] lies on the stroke of [path] with [strokeWidth], where SVG
/// hit testing (`pointer-events: visiblePainted`) also catches the pointer.
// ponytail: samples the outline every half pixel and treats joins as round.
bool strokeContains(Path path, Offset p, double strokeWidth) {
  final half = strokeWidth / 2;
  if (half <= 0 || !path.getBounds().inflate(half).contains(p)) return false;
  for (final metric in path.computeMetrics()) {
    for (var d = 0.0; d <= metric.length; d += 0.5) {
      final t = metric.getTangentForOffset(d);
      if (t != null && (t.position - p).distance <= half) return true;
    }
  }
  return false;
}
