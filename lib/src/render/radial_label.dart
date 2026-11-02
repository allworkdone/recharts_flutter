// The radial label positions of src/component/Label.tsx (renderRadialLabel):
// insideStart, insideEnd and end draw the text along an arc
// (`<text dominantBaseline="central"><textPath>`). Chrome lays each glyph on
// the path by its midpoint and turns it to the path's tangent.

import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../components.dart';
import '../core/polar_utils.dart';
import '../util.dart';
import 'svg_text.dart';

bool isRadialLabelPosition(LabelPosition p) =>
    p == LabelPosition.insideStart || p == LabelPosition.insideEnd || p == LabelPosition.end;

double _deltaAngle(double startAngle, double endAngle) =>
    mathSign(endAngle - startAngle) * math.min((endAngle - startAngle).abs(), 360);

/// The arc `renderRadialLabel` builds: its radius, where it starts (a polar
/// angle) and whether it runs counter-clockwise on screen (`direction`).
({double radius, double labelAngle, bool direction}) radialLabelPath(PolarViewBox v, double offset, LabelPosition position) {
  final radius = (v.innerRadius + v.outerRadius) / 2;
  final deltaAngle = _deltaAngle(v.startAngle, v.endAngle);
  final sign = deltaAngle >= 0 ? 1 : -1;
  final double labelAngle;
  bool direction;
  switch (position) {
    case LabelPosition.insideStart:
      labelAngle = v.startAngle + sign * offset;
      direction = v.clockWise;
    case LabelPosition.insideEnd:
      labelAngle = v.endAngle - sign * offset;
      direction = !v.clockWise;
    case LabelPosition.end:
      labelAngle = v.endAngle + sign * offset;
      direction = v.clockWise;
    default:
      throw ArgumentError('Unsupported position $position');
  }
  direction = deltaAngle <= 0 ? direction : !direction;
  return (radius: radius, labelAngle: labelAngle, direction: direction);
}

/// Draws [text] along the arc of [path] around ([cx], [cy]).
void paintTextOnArc(Canvas canvas, String text, double cx, double cy,
    ({double radius, double labelAngle, bool direction}) path,
    {required TextStyle style, required TextScaler scaler}) {
  final r = path.radius;
  if (!(r > 0) || text.isEmpty) return;
  final pathLength = 2 * math.pi * r * 359 / 360;
  final sign = path.direction ? 1.0 : -1.0;
  final units = text.runes.map(String.fromCharCode).toList();
  final em = textPainterFor(units.first, style, scaler);
  final ascent = em.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  // dominant-baseline: central puts the middle of the em box on the path.
  final centralShift = ascent - em.height / 2;
  var prefix = '';
  var advance = 0.0;
  for (final unit in units) {
    prefix += unit;
    final end = textPainterFor(prefix, style, scaler).width;
    final width = end - advance;
    final mid = advance + width / 2;
    advance = end;
    if (mid > pathLength) break;
    final theta = path.labelAngle + sign * (mid / r) / radian;
    final p = polarToCartesian(cx, cy, r, theta);
    // d/dθ of (cos(-θ), sin(-θ)) is (-sin θ, -cos θ): the heading for counter-clockwise travel.
    final rad = theta * radian;
    final heading = math.atan2(-math.cos(rad) * sign, -math.sin(rad) * sign);
    final tp = textPainterFor(unit, style, scaler);
    canvas.save();
    canvas.translate(p.dx, p.dy);
    canvas.rotate(heading);
    tp.paint(canvas, Offset(-tp.width / 2, centralShift - ascent));
    canvas.restore();
  }
}
