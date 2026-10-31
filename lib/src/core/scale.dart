// Port of the d3-scale scales Recharts uses (via victory-vendor: d3-scale
// 4.0.2, d3-array 3.2.4), exposed through Recharts' own wrapper contract:
// src/util/scale/RechartsScale.ts. Sources: d3-scale/src/{continuous,linear,
// log,pow,band,ordinal}.js and d3-array/src/{ticks,bisector}.js.
// Scales are immutable: build a new one instead of mutating.

import 'dart:math' as math;

import 'js_math.dart';

/// Position within a band for banded scales. Ignored by non-banded scales.
enum BandPosition { start, middle, end }

/// Mirrors `RechartsScale` from src/util/scale/RechartsScale.ts.
abstract class RechartsScale {
  /// Categorical scales: the categories. Continuous scales: `[min, max]`.
  List<Object?> get domain;

  /// `[min(range), max(range)]`, like `rechartsScaleFactory` builds it.
  List<double> get range;

  double get rangeMin;
  double get rangeMax;
  bool isInRange(double value);

  /// Width of each band; `null` when the scale is not banded.
  double? get bandwidth;

  /// d3 `scale.ticks(count)`; `null` when the scale has no ticks (band/point).
  List<num>? ticks([int? count]);

  /// d3 `scale(input)` plus the band offset for [position].
  /// `null` when [input] is not in the domain (d3 returns undefined).
  double? map(Object? input, {BandPosition? position});
}

/// `range`, `rangeMin`, `rangeMax` and `isInRange` from `rechartsScaleFactory`.
mixin _RechartsRange {
  List<double> get rawRange;

  late final List<double> _minMax = [
    rawRange.reduce((a, b) => math.min(a, b)),
    rawRange.reduce((a, b) => math.max(a, b)),
  ];

  List<double> get range => _minMax;
  double get rangeMin => _minMax[0];
  double get rangeMax => _minMax[1];

  bool isInRange(double value) {
    final first = _minMax[0], last = _minMax[1];
    return first <= last ? value >= first && value <= last : value >= last && value <= first;
  }
}

// ---------------------------------------------------------------------------
// d3-array ticks

final double _e10 = math.sqrt(50), _e5 = math.sqrt(10), _e2 = math.sqrt(2);

(double, double, double) _tickSpec(double start, double stop, double count) {
  final step = (stop - start) / math.max(0, count),
      power = jsLog10(step).floorToDouble(),
      error = step / math.pow(10, power),
      factor = error >= _e10
          ? 10.0
          : error >= _e5
              ? 5.0
              : error >= _e2
                  ? 2.0
                  : 1.0;
  double i1, i2, inc;
  if (power < 0) {
    inc = math.pow(10, -power).toDouble() / factor;
    i1 = jsRound(start * inc);
    i2 = jsRound(stop * inc);
    if (i1 / inc < start) ++i1;
    if (i2 / inc > stop) --i2;
    inc = -inc;
  } else {
    inc = math.pow(10, power).toDouble() * factor;
    i1 = jsRound(start / inc);
    i2 = jsRound(stop / inc);
    if (i1 * inc < start) ++i1;
    if (i2 * inc > stop) --i2;
  }
  if (i2 < i1 && 0.5 <= count && count < 2) return _tickSpec(start, stop, count * 2);
  return (i1, i2, inc);
}

/// d3-array `ticks(start, stop, count)`.
List<num> _ticks(double start, double stop, double count) {
  if (!(count > 0)) return [];
  if (start == stop) return [start];
  final reverse = stop < start;
  final (i1, i2, inc) = reverse ? _tickSpec(stop, start, count) : _tickSpec(start, stop, count);
  if (!(i2 >= i1)) return [];
  final n = (i2 - i1 + 1).toInt();
  return <num>[
    for (var i = 0; i < n; ++i)
      reverse
          ? (inc < 0 ? (i2 - i) / -inc : (i2 - i) * inc)
          : (inc < 0 ? (i1 + i) / -inc : (i1 + i) * inc),
  ];
}

/// d3-array `tickIncrement(start, stop, count)`.
double _tickIncrement(double start, double stop, double count) => _tickSpec(start, stop, count).$3;

double _ascending(double a, double b) => a < b
    ? -1
    : a > b
        ? 1
        : a >= b
            ? 0
            : double.nan;

int _bisectRight(List<double> a, double x, int lo, int hi) {
  if (lo < hi) {
    if (_ascending(x, x) != 0) return hi;
    do {
      final mid = (lo + hi) >> 1;
      if (_ascending(a[mid], x) <= 0) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    } while (lo < hi);
  }
  return lo;
}

// ---------------------------------------------------------------------------
// d3-scale continuous

typedef _Fn = double Function(double x);

double _identity(double x) => x;

_Fn _interpolateNumber(double a, double b) => (t) => a * (1 - t) + b * t;

_Fn _normalize(double a, double b) {
  b -= a;
  if (b != 0 && !b.isNaN) return (x) => (x - a) / b;
  final c = b.isNaN ? double.nan : 0.5;
  return (_) => c;
}

_Fn _clamper(double a, double b) {
  if (a > b) (a, b) = (b, a);
  return (x) => math.max(a, math.min(b, x));
}

_Fn _bimap(List<double> domain, List<double> range) {
  final d0 = domain[0], d1 = domain[1], r0 = range[0], r1 = range[1];
  final n = d1 < d0 ? _normalize(d1, d0) : _normalize(d0, d1);
  final i = d1 < d0 ? _interpolateNumber(r1, r0) : _interpolateNumber(r0, r1);
  return (x) => i(n(x));
}

_Fn _polymap(List<double> domain, List<double> range) {
  final j = math.min(domain.length, range.length) - 1;
  if (domain[j] < domain[0]) {
    domain = domain.reversed.toList();
    range = range.reversed.toList();
  }
  final d = [for (var i = 0; i < j; i++) _normalize(domain[i], domain[i + 1])];
  final r = [for (var i = 0; i < j; i++) _interpolateNumber(range[i], range[i + 1])];
  final dom = domain;
  return (x) {
    final i = _bisectRight(dom, x, 1, j) - 1;
    return r[i](d[i](x));
  };
}

/// JS unary `+x` for the inputs a chart can hand a continuous scale.
// ponytail: no hex/octal/binary string literals; Recharts passes numbers or dates.
double _jsToNumber(Object x) {
  if (x is num) return x.toDouble();
  if (x is DateTime) return x.millisecondsSinceEpoch.toDouble();
  if (x is bool) return x ? 1 : 0;
  if (x is String) {
    final t = x.trim();
    return t.isEmpty ? 0 : double.tryParse(t) ?? double.nan;
  }
  return double.nan;
}

/// d3-scale `transformer()`: the shared core of linear, log and pow scales.
class _Continuous {
  _Continuous(this.domain, this.range, this.transform, this.untransform, bool clamp) {
    final n = math.min(domain.length, range.length);
    _clamp = clamp ? _clamper(domain[0], domain[n - 1]) : _identity;
    _piecewise = n > 2 ? _polymap : _bimap;
  }

  final List<double> domain;
  final List<double> range;
  final _Fn transform;
  final _Fn untransform;
  late final _Fn _clamp;
  late final _Fn Function(List<double>, List<double>) _piecewise;

  late final _Fn _output = _piecewise(domain.map(transform).toList(), range);
  late final _Fn _input = _piecewise(range, domain.map(transform).toList());

  double? call(Object? x) {
    if (x == null) return null;
    final v = _jsToNumber(x);
    if (v.isNaN) return null;
    return _output(transform(_clamp(v)));
  }

  double invert(double y) => _clamp(untransform(_input(y)));
}

List<double> _toDoubles(List<num> xs) => [for (final x in xs) x.toDouble()];

/// d3 `linearish(scale).nice(count)`; null when d3 leaves the domain as is.
List<double>? _linearNice(List<double> d, double count) {
  d = d.toList();
  var i0 = 0, i1 = d.length - 1;
  var start = d[i0], stop = d[i1];
  double? prestep;
  var maxIter = 10;

  if (stop < start) {
    (start, stop) = (stop, start);
    (i0, i1) = (i1, i0);
  }

  while (maxIter-- > 0) {
    final step = _tickIncrement(start, stop, count);
    if (step == prestep) {
      d[i0] = start;
      d[i1] = stop;
      return d;
    } else if (step > 0) {
      start = (start / step).floorToDouble() * step;
      stop = (stop / step).ceilToDouble() * step;
    } else if (step < 0) {
      start = (start * step).ceilToDouble() / step;
      stop = (stop * step).floorToDouble() / step;
    } else {
      break;
    }
    prestep = step;
  }
  return null;
}

/// d3 `scaleLinear()`.
class LinearScale with _RechartsRange implements RechartsScale {
  LinearScale({required List<num> domain, required List<double> range, this.clamp = false})
      : _domain = domain,
        _range = range;

  final List<num> _domain;
  final List<double> _range;
  final bool clamp;

  late final _Continuous _s = _Continuous(_toDoubles(_domain), _range, _identity, _identity, clamp);

  /// d3 `linear.nice(count)`.
  LinearScale nice([int count = 10]) {
    final d = _linearNice(_toDoubles(_domain), count.toDouble());
    return d == null ? this : LinearScale(domain: d, range: _range, clamp: clamp);
  }

  /// d3 `linear.invert(value)`.
  double invert(double value) => _s.invert(value);

  /// The range exactly as passed (may be descending, e.g. a y axis).
  @override
  List<double> get rawRange => _range;

  @override
  List<Object?> get domain => _domain;
  @override
  double? get bandwidth => null;
  @override
  List<num>? ticks([int? count]) =>
      _ticks(_domain.first.toDouble(), _domain.last.toDouble(), (count ?? 10).toDouble());
  @override
  double? map(Object? input, {BandPosition? position}) => _s(input);
}

double _transformLogn(double x) => -jsLog(-x);
double _transformExpn(double x) => -math.exp(-x);

/// d3-scale's `pow10`: `+("1e" + x)`, which is NaN for non-integer x.
double _pow10(double x) {
  if (!x.isFinite) return x < 0 ? 0 : x;
  if (x != x.truncateToDouble() || x.abs() >= 1e21) return double.nan;
  return double.parse('1e${x.toInt()}');
}

_Fn _powp(double base) => base == 10
    ? _pow10
    : base == math.e
        ? math.exp
        : (x) => math.pow(base, x).toDouble();

_Fn _logp(double base) {
  if (base == math.e) return jsLog;
  if (base == 10) return jsLog10;
  if (base == 2) return jsLog2;
  final lb = jsLog(base);
  return (x) => jsLog(x) / lb;
}

_Fn _reflect(_Fn f) => (x) => -f(-x);

/// d3 `scaleLog()` (base 10 unless [base] given).
class LogScale with _RechartsRange implements RechartsScale {
  LogScale({required List<num> domain, required List<double> range, this.base = 10, this.clamp = false})
      : _domain = domain,
        _range = range;

  final List<num> _domain;
  final List<double> _range;
  final num base;
  final bool clamp;

  late final bool _negative = _domain[0] < 0;
  late final _Fn _logs = _negative ? _reflect(_logp(base.toDouble())) : _logp(base.toDouble());
  late final _Fn _pows = _negative ? _reflect(_powp(base.toDouble())) : _powp(base.toDouble());
  late final _Continuous _s = _negative
      ? _Continuous(_toDoubles(_domain), _range, _transformLogn, _transformExpn, clamp)
      : _Continuous(_toDoubles(_domain), _range, jsLog, math.exp, clamp);

  LogScale nice() {
    final d = _toDoubles(_domain);
    var i0 = 0, i1 = d.length - 1;
    var x0 = d[i0], x1 = d[i1];
    if (x1 < x0) {
      (i0, i1) = (i1, i0);
      (x0, x1) = (x1, x0);
    }
    d[i0] = _pows(_logs(x0).floorToDouble());
    d[i1] = _pows(_logs(x1).ceilToDouble());
    return LogScale(domain: d, range: _range, base: base, clamp: clamp);
  }

  /// d3 `log.invert(value)`.
  double invert(double value) => _s.invert(value);

  @override
  List<double> get rawRange => _range;

  @override
  List<Object?> get domain => _domain;
  @override
  double? get bandwidth => null;

  @override
  List<num>? ticks([int? count]) {
    final base = this.base.toDouble();
    var u = _domain.first.toDouble();
    var v = _domain.last.toDouble();
    final r = v < u;
    if (r) (u, v) = (v, u);

    var i = _logs(u);
    var j = _logs(v);
    final n = (count ?? 10).toDouble();
    var z = <num>[];

    final baseMod1 = base.remainder(1);
    if ((baseMod1 == 0 || baseMod1.isNaN) && j - i < n) {
      i = i.floorToDouble();
      j = j.ceilToDouble();
      if (u > 0) {
        for (; i <= j; ++i) {
          for (var k = 1.0; k < base; ++k) {
            final t = i < 0 ? k / _pows(-i) : k * _pows(i);
            if (t < u) continue;
            if (t > v) break;
            z.add(t);
          }
        }
      } else {
        for (; i <= j; ++i) {
          for (var k = base - 1; k >= 1; --k) {
            final t = i > 0 ? k / _pows(-i) : k * _pows(i);
            if (t < u) continue;
            if (t > v) break;
            z.add(t);
          }
        }
      }
      if (z.length * 2 < n) z = _ticks(u, v, n);
    } else {
      z = <num>[for (final t in _ticks(i, j, math.min(j - i, n))) _pows(t.toDouble())];
    }
    return r ? z.reversed.toList() : z;
  }

  @override
  double? map(Object? input, {BandPosition? position}) => _s(input);
}

_Fn _transformPow(double exponent) => (x) => x < 0 ? -math.pow(-x, exponent).toDouble() : math.pow(x, exponent).toDouble();
double _transformSqrt(double x) => x < 0 ? -math.sqrt(-x) : math.sqrt(x);
double _transformSquare(double x) => x < 0 ? -x * x : x * x;

/// d3 `scalePow().exponent(e)`; `scaleSqrt()` is `PowScale(exponent: 0.5)`.
class PowScale with _RechartsRange implements RechartsScale {
  PowScale({required List<num> domain, required List<double> range, this.exponent = 1, this.clamp = false})
      : _domain = domain,
        _range = range;

  final List<num> _domain;
  final List<double> _range;
  final num exponent;
  final bool clamp;

  late final _Continuous _s = exponent == 1
      ? _Continuous(_toDoubles(_domain), _range, _identity, _identity, clamp)
      : exponent == 0.5
          ? _Continuous(_toDoubles(_domain), _range, _transformSqrt, _transformSquare, clamp)
          : _Continuous(_toDoubles(_domain), _range, _transformPow(exponent.toDouble()),
              _transformPow(1 / exponent), clamp);

  PowScale nice([int count = 10]) {
    final d = _linearNice(_toDoubles(_domain), count.toDouble());
    return d == null ? this : PowScale(domain: d, range: _range, exponent: exponent, clamp: clamp);
  }

  /// d3 `pow.invert(value)`.
  double invert(double value) => _s.invert(value);

  @override
  List<double> get rawRange => _range;

  @override
  List<Object?> get domain => _domain;
  @override
  double? get bandwidth => null;
  @override
  List<num>? ticks([int? count]) =>
      _ticks(_domain.first.toDouble(), _domain.last.toDouble(), (count ?? 10).toDouble());
  @override
  double? map(Object? input, {BandPosition? position}) => _s(input);
}

// ---------------------------------------------------------------------------
// d3-scale band / point

const Object _nanKey = Object();

/// d3-array InternMap's key: `valueOf()` for objects (dates), and NaN equal
/// to itself as in a JS Map.
Object? _internKey(Object? v) {
  if (v is DateTime) return v.millisecondsSinceEpoch;
  if (v is double && v.isNaN) return _nanKey;
  return v;
}

/// d3 `scaleBand()` state after `rescale()`.
class _Band {
  _Band(List<Object?> rawDomain, List<double> range, double paddingInner, double paddingOuter, double align,
      bool round) {
    for (final value in rawDomain) {
      final key = _internKey(value);
      if (index.containsKey(key)) continue;
      domain.add(value);
      index[key] = domain.length - 1;
    }
    paddingInner = math.min(1, paddingInner);
    align = math.max(0, math.min(1, align));

    final n = domain.length;
    final r0 = range[0], r1 = range[1];
    final reverse = r1 < r0;
    var start = reverse ? r1 : r0;
    final stop = reverse ? r0 : r1;
    var step = (stop - start) / math.max(1, n - paddingInner + paddingOuter * 2);
    if (round) step = step.floorToDouble();
    start += (stop - start - step * (n - paddingInner)) * align;
    var bandwidth = step * (1 - paddingInner);
    if (round) {
      start = jsRound(start);
      bandwidth = jsRound(bandwidth);
    }
    final values = [for (var i = 0; i < n; i++) start + step * i];
    this.values = reverse ? values.reversed.toList() : values;
    this.step = step;
    this.bandwidth = bandwidth;
  }

  final List<Object?> domain = [];
  final Map<Object?, int> index = {};
  late final List<double> values;
  late final double step;
  late final double bandwidth;

  double? call(Object? d) {
    final i = index[_internKey(d)];
    return i == null ? null : values[i % values.length];
  }

  double? map(Object? input, BandPosition? position) {
    final base = this(input);
    if (base == null) return null;
    return switch (position) {
      BandPosition.middle => base + bandwidth / 2,
      BandPosition.end => base + bandwidth,
      _ => base,
    };
  }
}

/// d3 `scaleBand()`.
class BandScale with _RechartsRange implements RechartsScale {
  BandScale({
    required List<Object?> domain,
    required List<double> range,
    this.paddingInner = 0,
    this.paddingOuter = 0,
    this.align = 0.5,
    this.round = false,
  })  : _domain = domain,
        _range = range;

  final List<Object?> _domain;
  final List<double> _range;
  final double paddingInner;
  final double paddingOuter;
  final double align;
  final bool round;

  late final _Band _b = _Band(_domain, _range, paddingInner, paddingOuter, align, round);

  /// d3 `band.step()`.
  double get step => _b.step;

  /// d3 `band.range()`: `[r0, r1]` as passed (may be descending).
  @override
  List<double> get rawRange => [_range[0], _range[1]];

  /// The de-duplicated domain, as d3 `band.domain()` returns it.
  @override
  List<Object?> get domain => _b.domain;
  @override
  double? get bandwidth => _b.bandwidth;
  @override
  List<num>? ticks([int? count]) => null;
  @override
  double? map(Object? input, {BandPosition? position}) => _b.map(input, position);
}

/// d3 `scalePoint()` (a band scale with zero bandwidth).
class PointScale with _RechartsRange implements RechartsScale {
  PointScale({
    required List<Object?> domain,
    required List<double> range,
    this.padding = 0,
    this.align = 0.5,
    this.round = false,
  })  : _domain = domain,
        _range = range;

  final List<Object?> _domain;
  final List<double> _range;
  final double padding;
  final double align;
  final bool round;

  late final _Band _b = _Band(_domain, _range, 1, padding, align, round);

  double get step => _b.step;

  /// d3 `point.range()`: `[r0, r1]` as passed (may be descending).
  @override
  List<double> get rawRange => [_range[0], _range[1]];

  /// The de-duplicated domain, as d3 `point.domain()` returns it.
  @override
  List<Object?> get domain => _b.domain;
  @override
  double? get bandwidth => _b.bandwidth;
  @override
  List<num>? ticks([int? count]) => null;
  @override
  double? map(Object? input, {BandPosition? position}) => _b.map(input, position);
}
