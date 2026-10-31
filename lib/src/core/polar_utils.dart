// Port of src/util/PolarUtils.ts: angles are degrees, counter-clockwise from
// 3 o'clock, with SVG's y axis pointing down.

import 'dart:math' as math;
import 'dart:ui' show Offset;

const double radian = math.pi / 180;

double degreeToRadian(double angle) => angle * math.pi / 180;

double radianToDegree(double angleInRadian) => angleInRadian * 180 / math.pi;

/// `polarToCartesian(cx, cy, radius, angle)`.
Offset polarToCartesian(double cx, double cy, double radius, double angle) =>
    Offset(cx + math.cos(-radian * angle) * radius, cy + math.sin(-radian * angle) * radius);

/// `getMaxRadius(width, height, offset)`: half the smaller side of the box
/// left after removing the offset.
double getMaxRadius(double width, double height,
        {double top = 0, double right = 0, double bottom = 0, double left = 0}) =>
    math.min((width - left - right).abs(), (height - top - bottom).abs()) / 2;

/// `PolarViewBoxRequired`.
class PolarViewBox {
  const PolarViewBox({
    required this.cx,
    required this.cy,
    required this.innerRadius,
    required this.outerRadius,
    required this.startAngle,
    required this.endAngle,
    this.clockWise = false,
  });
  final double cx, cy, innerRadius, outerRadius, startAngle, endAngle;
  final bool clockWise;
}

/// `getAngleOfPoint`.
({double radius, double angle}) getAngleOfPoint(Offset p, double cx, double cy) {
  final radius = math.sqrt(math.pow(p.dx - cx, 2) + math.pow(p.dy - cy, 2));
  if (radius <= 0) return (radius: radius, angle: 0);
  var angleInRadian = math.acos((p.dx - cx) / radius);
  if (p.dy > cy) angleInRadian = 2 * math.pi - angleInRadian;
  return (radius: radius, angle: radianToDegree(angleInRadian));
}

int _turns(PolarViewBox v) => math.min((v.startAngle / 360).floor(), (v.endAngle / 360).floor());

/// `inRangeOfSector`: the pointer's radius and angle when it lies inside
/// [viewBox], else null.
({double radius, double angle})? inRangeOfSector(Offset p, PolarViewBox viewBox) {
  final (:radius, :angle) = getAngleOfPoint(p, viewBox.cx, viewBox.cy);
  if (radius < viewBox.innerRadius || radius > viewBox.outerRadius || radius == 0) return null;
  // formatAngleOfSector
  final min = _turns(viewBox);
  final startAngle = viewBox.startAngle - min * 360, endAngle = viewBox.endAngle - min * 360;
  var formatAngle = angle;
  final bool inRange;
  if (startAngle <= endAngle) {
    while (formatAngle > endAngle) {
      formatAngle -= 360;
    }
    while (formatAngle < startAngle) {
      formatAngle += 360;
    }
    inRange = formatAngle >= startAngle && formatAngle <= endAngle;
  } else {
    while (formatAngle > startAngle) {
      formatAngle -= 360;
    }
    while (formatAngle < endAngle) {
      formatAngle += 360;
    }
    inRange = formatAngle >= endAngle && formatAngle <= startAngle;
  }
  // reverseFormatAngleOfSector
  return inRange ? (radius: radius, angle: formatAngle + min * 360) : null;
}
