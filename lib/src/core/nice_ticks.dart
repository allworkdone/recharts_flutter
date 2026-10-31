// Port of src/util/scale/getNiceTickValues.ts and src/util/scale/util/arithmetic.ts
// (formerly the recharts-scale package). The TS version does its step math in
// decimal.js-light; [_Decimal] reproduces the parts it uses, so values like
// 0.1 + 0.2 come out the same.

import 'dart:math' as math;

import 'js_math.dart';

enum NiceTicksAlgorithm { auto, adaptive, snap125, none }

/// The slice of decimal.js-light 2.5.1 the tick math uses. Default config:
/// precision 20, and every arithmetic result is truncated (not rounded) to
/// 20 significant digits, as decimal.js-light's internal `round(x, pr)` does
/// when no rounding mode is passed. Value = [c] * 10^[e].
class _Decimal {
  const _Decimal._(this.c, this.e);

  final BigInt c;
  final int e;

  static const int _precision = 20;
  static final BigInt _ten = BigInt.from(10);
  static final _Decimal zero = _Decimal._(BigInt.zero, 0);

  /// `new Decimal(number)`: exact value of the number's JS string form.
  factory _Decimal(num v) {
    if (!v.isFinite) throw ArgumentError('[DecimalError] Invalid argument: $v');
    if (v is int) return _norm(BigInt.from(v), 0);
    // Dart's double.toString yields the same shortest digits as JS Number#toString.
    var s = v.toString();
    final neg = s.startsWith('-');
    if (neg) s = s.substring(1);
    var exp = 0;
    final ei = s.indexOf('e');
    if (ei >= 0) {
      exp = int.parse(s.substring(ei + 1));
      s = s.substring(0, ei);
    }
    final dot = s.indexOf('.');
    if (dot >= 0) {
      exp -= s.length - dot - 1;
      s = s.replaceFirst('.', '');
    }
    final c = BigInt.parse(s);
    return _norm(neg ? -c : c, exp);
  }

  static _Decimal _norm(BigInt c, int e) {
    if (c == BigInt.zero) return zero;
    while (c.remainder(_ten) == BigInt.zero) {
      c = c ~/ _ten;
      e++;
    }
    return _Decimal._(c, e);
  }

  static _Decimal _pow10(int k) => _Decimal._(BigInt.one, k);

  static int _digits(BigInt c) => c.abs().toString().length;

  _Decimal _trunc() {
    final drop = _digits(c) - _precision;
    if (drop <= 0) return this;
    return _norm(c ~/ _ten.pow(drop), e + drop);
  }

  bool get isZero => c == BigInt.zero;

  _Decimal add(_Decimal y) {
    if (isZero) return y._trunc();
    if (y.isZero) return _trunc();
    final m = math.min(e, y.e);
    return _norm(c * _ten.pow(e - m) + y.c * _ten.pow(y.e - m), m)._trunc();
  }

  _Decimal sub(_Decimal y) => add(_Decimal._(-y.c, y.e));

  _Decimal mul(_Decimal y) => _norm(c * y.c, e + y.e)._trunc();

  _Decimal div(_Decimal y) {
    if (y.isZero) throw ArgumentError('[DecimalError] Division by zero');
    if (isZero) return zero;
    final k = math.max(0, _precision + 1 + _digits(y.c) - _digits(c));
    return _norm((c * _ten.pow(k)) ~/ y.c, e - y.e - k)._trunc();
  }

  /// `x.mod(y)`: x - trunc(x / y) * y, with the sign of x.
  _Decimal mod(_Decimal y) {
    if (y.isZero) throw ArgumentError('[DecimalError] NaN');
    if (isZero) return zero;
    final d = e - y.e;
    final n = d >= 0 ? (c * _ten.pow(d)) ~/ y.c : c ~/ (y.c * _ten.pow(-d));
    final m = math.min(e, y.e);
    return _norm(c * _ten.pow(e - m) - n * y.c * _ten.pow(y.e - m), m)._trunc();
  }

  _Decimal abs() => c.isNegative ? _Decimal._(-c, e) : this;

  int compareTo(_Decimal y) {
    final m = math.min(e, y.e);
    return (c * _ten.pow(e - m)).compareTo(y.c * _ten.pow(y.e - m));
  }

  bool lt(_Decimal y) => compareTo(y) < 0;
  bool lte(_Decimal y) => compareTo(y) <= 0;
  bool get isInt => e >= 0;

  /// `+decimal`: the decimal string parsed as a JS number.
  double toNumber() => double.parse('${c}e$e');

  /// `x.log(10)` for x > 0, truncated to 20 digits. Computed with 60-digit
  /// fixed point; decimal.js-light works with 25 digits and is within an
  /// ulp of the same truncation.
  _Decimal log10() {
    if (c <= BigInt.zero) throw ArgumentError('[DecimalError] NaN');
    final n = _digits(c);
    final k = n - 1 + e;
    if (c == BigInt.one) return _Decimal(k);
    final scale = _ten.pow(_fixed);
    // m = c / 10^(n-1) in [1, 10), as a fixed-point number.
    var m = c * scale ~/ _ten.pow(n - 1);
    var twos = 0;
    while (m >= scale * BigInt.two) {
      m = m ~/ BigInt.two;
      twos++;
    }
    final lnM = BigInt.from(twos) * _ln2 + _lnNear1(m);
    final log10M = lnM * scale ~/ _ln10;
    return _norm(BigInt.from(k) * scale + log10M, -_fixed)._trunc();
  }

  static const int _fixed = 60;
  static final BigInt _ln2 = _atanh2(_ten.pow(_fixed) ~/ BigInt.from(3));
  static final BigInt _ln10 = BigInt.from(3) * _ln2 + _atanh2(_ten.pow(_fixed) ~/ BigInt.from(9));

  /// ln(m) for fixed-point m in [1, 2).
  static BigInt _lnNear1(BigInt m) {
    final scale = _ten.pow(_fixed);
    return _atanh2((m - scale) * scale ~/ (m + scale));
  }

  /// 2 * atanh(z) for fixed-point z.
  static BigInt _atanh2(BigInt z) {
    final scale = _ten.pow(_fixed);
    final z2 = z * z ~/ scale;
    var term = z;
    var sum = z;
    for (var k = 3; term != BigInt.zero; k += 2) {
      term = term * z2 ~/ scale;
      sum += term ~/ BigInt.from(k);
    }
    return sum * BigInt.two;
  }

  @override
  String toString() => '${c}e$e';
}

/// `getDigitCount` from src/util/scale/util/arithmetic.ts.
int _getDigitCount(double value) {
  if (value == 0) return 1;
  return _Decimal(value).abs().log10().toNumber().floor() + 1;
}

/// `rangeStep` from src/util/scale/util/arithmetic.ts.
List<num> _rangeStep(_Decimal start, _Decimal end, _Decimal step) {
  var n = start;
  var i = 0;
  final result = <num>[];
  // magic number to prevent infinite loop
  while (n.lt(end) && i < 100000) {
    result.add(n.toNumber());
    n = n.add(step);
    i++;
  }
  return result;
}

typedef _StepFunction = _Decimal Function(_Decimal roughStep, bool allowDecimals, int correctionFactor);

_Decimal _getAdaptiveStep(_Decimal roughStep, bool allowDecimals, int correctionFactor) {
  if (roughStep.lte(_Decimal.zero)) return _Decimal.zero;

  final digitCount = _getDigitCount(roughStep.toNumber());
  final digitCountValue = _Decimal._pow10(digitCount);
  final stepRatio = roughStep.div(digitCountValue);
  final stepRatioScale = digitCount != 1 ? 0.05 : 0.1;
  final amendStepRatio = _Decimal(stepRatio.div(_Decimal(stepRatioScale)).toNumber().ceilToDouble())
      .add(_Decimal(correctionFactor))
      .mul(_Decimal(stepRatioScale));

  final formatStep = amendStepRatio.mul(digitCountValue);

  return allowDecimals ? _Decimal(formatStep.toNumber()) : _Decimal(formatStep.toNumber().ceilToDouble());
}

const List<double> _niceSteps = [1, 2, 2.5, 5];

_Decimal _getSnap125Step(_Decimal roughStep, bool allowDecimals, int correctionFactor) {
  if (roughStep.lte(_Decimal.zero)) return _Decimal.zero;

  final roughNum = roughStep.toNumber();
  final exponent = _Decimal(roughNum).abs().log10().toNumber().floor();
  var magnitude = _Decimal._pow10(exponent);

  final normalized = roughStep.div(magnitude).toNumber();

  var niceIdx = _niceSteps.indexWhere((s) => s >= normalized - 1e-10);
  if (niceIdx == -1) {
    magnitude = magnitude.mul(_Decimal(10));
    niceIdx = 0;
  }

  niceIdx += correctionFactor;
  if (niceIdx >= _niceSteps.length) {
    final extraMag = niceIdx ~/ _niceSteps.length;
    niceIdx %= _niceSteps.length;
    magnitude = magnitude.mul(_Decimal._pow10(extraMag));
  }

  final formatStep = _Decimal(_niceSteps[niceIdx]).mul(magnitude);

  return allowDecimals ? formatStep : _Decimal(formatStep.toNumber().ceilToDouble());
}

List<num> _getTickOfSingleValue(double value, int tickCount, bool allowDecimals) {
  var step = _Decimal(1);
  var middle = _Decimal(value);

  if (!middle.isInt && allowDecimals) {
    final absVal = value.abs();

    if (absVal < 1) {
      step = _Decimal._pow10(_getDigitCount(value) - 1);
      middle = _Decimal(middle.div(step).toNumber().floorToDouble()).mul(step);
    } else if (absVal > 1) {
      middle = _Decimal(value.floorToDouble());
    }
  } else if (value == 0) {
    middle = _Decimal(((tickCount - 1) / 2).floor());
  } else if (!allowDecimals) {
    middle = _Decimal(value.floorToDouble());
  }

  final middleIndex = ((tickCount - 1) / 2).floor();
  return <num>[
    for (var i = 0; i < tickCount; i++) middle.add(_Decimal(i - middleIndex).mul(step)).toNumber(),
  ];
}

({_Decimal step, _Decimal tickMin, _Decimal tickMax}) _calculateStep(
  double min,
  double max,
  int tickCount,
  bool allowDecimals,
  int correctionFactor,
  _StepFunction stepFn,
) {
  // dirty hack (for recharts' test)
  if (!((max - min) / (tickCount - 1)).isFinite) {
    return (step: _Decimal.zero, tickMin: _Decimal.zero, tickMax: _Decimal.zero);
  }

  final step = stepFn(_Decimal(max).sub(_Decimal(min)).div(_Decimal(tickCount - 1)), allowDecimals, correctionFactor);

  _Decimal middle;
  if (min <= 0 && max >= 0) {
    middle = _Decimal.zero;
  } else {
    middle = _Decimal(min).add(_Decimal(max)).div(_Decimal(2));
    middle = middle.sub(middle.mod(step));
  }

  var belowCount = middle.sub(_Decimal(min)).div(step).toNumber().ceil();
  var upCount = _Decimal(max).sub(middle).div(step).toNumber().ceil();
  final scaleCount = belowCount + upCount + 1;

  if (scaleCount > tickCount) {
    // In JS this recursion never ends for some inputs (tickCount 2 with min < 0 < max)
    // and throws RangeError on stack overflow; converging inputs need < 1300 levels.
    if (correctionFactor > 2000) throw StateError('Maximum call stack size exceeded');
    return _calculateStep(min, max, tickCount, allowDecimals, correctionFactor + 1, stepFn);
  }
  if (scaleCount < tickCount) {
    upCount = max > 0 ? upCount + (tickCount - scaleCount) : upCount;
    belowCount = max > 0 ? belowCount : belowCount + (tickCount - scaleCount);
  }

  return (
    step: step,
    tickMin: middle.sub(_Decimal(belowCount).mul(step)),
    tickMax: middle.add(_Decimal(upCount).mul(step)),
  );
}

_StepFunction _stepFn(NiceTicksAlgorithm mode) =>
    mode == NiceTicksAlgorithm.snap125 ? _getSnap125Step : _getAdaptiveStep;

/// `getNiceTickValues([min, max], tickCount, allowDecimals, niceTicksMode)`.
List<num> getNiceTickValues(
  List<num> domain, {
  int tickCount = 6,
  bool allowDecimals = true,
  NiceTicksAlgorithm niceTicksMode = NiceTicksAlgorithm.auto,
}) {
  final min = domain[0].toDouble(), max = domain[1].toDouble();
  final count = math.max(tickCount, 2);
  final cormin = min > max ? max : min, cormax = min > max ? min : max;

  if (cormin == double.negativeInfinity || cormax == double.infinity) {
    final values = cormax == double.infinity
        ? <num>[cormin, ...List.filled(tickCount - 1, double.infinity)]
        : <num>[...List.filled(tickCount - 1, double.negativeInfinity), cormax];
    return min > max ? values.reversed.toList() : values;
  }

  if (cormin == cormax) return _getTickOfSingleValue(cormin, tickCount, allowDecimals);

  final s = _calculateStep(cormin, cormax, count, allowDecimals, 0, _stepFn(niceTicksMode));
  final values = _rangeStep(s.tickMin, s.tickMax.add(_Decimal(0.1).mul(s.step)), s.step);

  return min > max ? values.reversed.toList() : values;
}

/// `getTickValuesFixedDomain([min, max], tickCount, allowDecimals, niceTicksMode)`.
List<num> getTickValuesFixedDomain(
  List<num> domain, {
  required int tickCount,
  bool allowDecimals = true,
  NiceTicksAlgorithm niceTicksMode = NiceTicksAlgorithm.auto,
}) {
  final min = domain[0].toDouble(), max = domain[1].toDouble();
  final cormin = min > max ? max : min, cormax = min > max ? min : max;

  if (cormin == double.negativeInfinity || cormax == double.infinity) return <num>[min, max];
  if (cormin == cormax) return <num>[cormin];

  final count = math.max(tickCount, 2);
  final step = _stepFn(niceTicksMode)(
    _Decimal(cormax).sub(_Decimal(cormin)).div(_Decimal(count - 1)),
    allowDecimals,
    0,
  );
  var values = <num>[..._rangeStep(_Decimal(cormin), _Decimal(cormax), step), cormax];

  if (!allowDecimals) {
    values = values.map((v) => jsRound(v.toDouble())).toList();
    final last = values.length - 1;
    if (last > 0 && values[last] == values[last - 1]) values = values.sublist(0, last);
  }

  return min > max ? values.reversed.toList() : values;
}
