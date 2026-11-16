// The radial label positions of src/component/Label.tsx (renderRadialLabel):
// insideStart, insideEnd and end draw the text along an arc
// (`<Text dominantBaseline="central" textPath>`).

import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../components.dart';
import '../core/polar_utils.dart';
import '../util.dart';

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

/// The path renderRadialLabel lays the text on: `M start A r,r,0,1,sweep end`,
/// 359° from [startAngle] around ([cx], [cy]), counter-clockwise on screen when [direction].
Path radialLabelArc(double cx, double cy, double radius, double startAngle, bool direction) {
  final start = polarToCartesian(cx, cy, radius, startAngle);
  final end = polarToCartesian(cx, cy, radius, startAngle + (direction ? 359 : -359));
  return Path()
    ..moveTo(start.dx, start.dy)
    ..arcToPoint(end, radius: Radius.circular(radius), largeArc: true, clockwise: !direction);
}
