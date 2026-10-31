// Port of src/animation/easing.ts: named CSS beziers, cubic-bezier(...)
// strings and the spring easing, computed the way Recharts computes them.

import 'dart:math' as math;

import 'package:flutter/animation.dart';

import 'js_math.dart';

typedef EasingFunction = double Function(double t);

const double _accuracy = 1e-4;

List<double> _cubicBezierFactor(double c1, double c2) => [0, 3 * c1, 3 * c2 - 6 * c1, 3 * c1 - 3 * c2 + 1];

double _evaluatePolynomial(List<double> params, double t) {
  var sum = params[0] * math.pow(t, 0).toDouble();
  for (var i = 1; i < params.length; i++) {
    sum += params[i] * math.pow(t, i).toDouble();
  }
  return sum;
}

EasingFunction _cubicBezier(double c1, double c2) {
  final params = _cubicBezierFactor(c1, c2);
  return (t) => _evaluatePolynomial(params, t);
}

EasingFunction _derivativeCubicBezier(double c1, double c2) {
  final params = _cubicBezierFactor(c1, c2);
  final newParams = [for (var i = 1; i < params.length; i++) params[i] * i, 0.0];
  return (t) => _evaluatePolynomial(newParams, t);
}

List<double>? _parseCubicBezier(String easing) {
  final easingParts = easing.split('(');
  if (easingParts.length != 2 || easingParts[0] != 'cubic-bezier') return null;
  final numbers = easingParts[1].split(')')[0].split(',');
  if (numbers.length != 4) return null;
  return numbers.map(jsParseFloat).toList();
}

List<double> _getBezierCoordinates(String name) => switch (name) {
      'linear' => [0.0, 0.0, 1.0, 1.0],
      'ease' => [0.25, 0.1, 0.25, 1.0],
      'ease-in' => [0.42, 0.0, 1.0, 1.0],
      'ease-out' => [0.42, 0.0, 0.58, 1.0],
      'ease-in-out' => [0.0, 0.0, 0.58, 1.0],
      // Fallback for invalid input: linear.
      _ => _parseCubicBezier(name) ?? [0.0, 0.0, 1.0, 1.0],
    };

EasingFunction _createBezierEasing(double x1, double y1, double x2, double y2) {
  final curveX = _cubicBezier(x1, x2);
  final curveY = _cubicBezier(y1, y2);
  final derCurveX = _derivativeCubicBezier(x1, x2);
  double rangeValue(double value) {
    if (value > 1) return 1;
    if (value < 0) return 0;
    return value;
  }

  return (animationElapsedTimeIn) {
    final animationElapsedTime = animationElapsedTimeIn > 1 ? 1.0 : animationElapsedTimeIn;
    var x = animationElapsedTime;

    for (var i = 0; i < 8; ++i) {
      final evalT = curveX(x) - animationElapsedTime;
      final derVal = derCurveX(x);

      if ((evalT - animationElapsedTime).abs() < _accuracy || derVal < _accuracy) {
        return curveY(x);
      }

      x = rangeValue(x - evalT / derVal);
    }

    return curveY(x);
  };
}

/// `configBezier(x1, y1, x2, y2)`.
EasingFunction configBezier(double x1, double y1, double x2, double y2) => _createBezierEasing(x1, y1, x2, y2);

/// `configBezier(name)`: a named easing or a `cubic-bezier(...)` string;
/// anything unparseable falls back to linear, as in Recharts.
EasingFunction configBezierNamed(String name) {
  final c = _getBezierCoordinates(name);
  return _createBezierEasing(c[0], c[1], c[2], c[3]);
}

/// `createSpringEasing({stiff, damping, dt})`: spring physics baked into
/// frames, then sampled by progress.
EasingFunction createSpringEasing({double stiff = 100, double damping = 8, double dt = 16.67}) {
  const destX = 1.0;

  final positions = <double>[0];
  var currX = 0.0;
  var currV = 0.0;

  const maxIterations = 10000;
  var iterations = 0;

  while (iterations < maxIterations) {
    final fSpring = -(currX - destX) * stiff;
    final fDamping = currV * damping;

    currV += ((fSpring - fDamping) * dt) / 1000;
    currX += (currV * dt) / 1000;

    positions.add(currX);

    if ((currX - destX).abs() < _accuracy && currV.abs() < _accuracy) break;
    iterations++;
  }

  positions[positions.length - 1] = destX;
  final maxIndex = positions.length - 1;

  return (t) {
    if (t <= 0) return 0;
    if (t >= 1) return destX;
    if (t.isNaN) return double.nan; // JS: positions[NaN] ?? 0 gives NaN below.

    final exactFrame = t * maxIndex;
    final index = exactFrame.floor();
    final fraction = exactFrame - index;

    final p0 = index < positions.length ? positions[index] : 0.0;
    final p1 = index + 1 < positions.length ? positions[index + 1] : 0.0;
    return p0 + (p1 - p0) * fraction;
  };
}

/// `createEasingFunction(easing)`. [easing] is one of 'linear', 'ease',
/// 'ease-in', 'ease-out', 'ease-in-out', 'cubic-bezier(a,b,c,d)', 'spring',
/// or an [EasingFunction]. Returns null for input Recharts rejects.
EasingFunction? createEasingFunction(Object easing) {
  if (easing is String) {
    switch (easing) {
      case 'ease' || 'ease-in-out' || 'ease-out' || 'ease-in' || 'linear':
        return configBezierNamed(easing);
      case 'spring':
        return createSpringEasing();
      default:
        if (easing.split('(')[0] == 'cubic-bezier') return configBezierNamed(easing);
    }
  }
  if (easing is EasingFunction) return easing;
  return null;
}

/// Adapts a Recharts easing to a Flutter [Curve] for AnimationController use.
class RechartsCurve extends Curve {
  const RechartsCurve(this.easing);
  final EasingFunction easing;

  @override
  double transformInternal(double t) => easing(t);
}
