// Port of the d3-shape line generator and curve factories Recharts uses
// (src/shape/Curve.tsx). Curves draw into a [PathSink] so tests can record
// the exact commands d3 would emit, while charts draw straight into a
// Flutter [Path].
// Sources: d3-shape 3.2.0 src/line.js and src/curve/{linear,linearClosed,
// step,basis,basisClosed,basisOpen,natural,monotone,bump}.js; d3-path 3.1.0
// src/path.js (coordinates rounded to 3 digits, d3-shape's default).

import 'dart:math' as math;
import 'dart:ui';

import 'js_math.dart';

/// `CurveType` from src/shape/Curve.tsx (minus the custom-factory variant).
enum CurveType {
  basis,
  basisClosed,
  basisOpen,
  bumpX,
  bumpY,
  bump,
  linear,
  linearClosed,
  natural,
  monotoneX,
  monotoneY,
  monotone,
  step,
  stepBefore,
  stepAfter,
}

/// Recharts' chart layout; `monotone` and `bump` resolve to their X variant
/// for horizontal and their Y variant for vertical (`getCurveFactory`).
enum ChartLayout { horizontal, vertical }

/// The subset of d3-path's CanvasPath context that d3-shape curves call.
abstract class PathSink {
  void moveTo(double x, double y);
  void lineTo(double x, double y);
  void bezierCurveTo(double x1, double y1, double x2, double y2, double x, double y);
  void closePath();
}

/// Writes into a Flutter [Path].
class FlutterPathSink implements PathSink {
  FlutterPathSink([Path? path]) : path = path ?? Path();
  final Path path;

  @override
  void moveTo(double x, double y) => path.moveTo(x, y);
  @override
  void lineTo(double x, double y) => path.lineTo(x, y);
  @override
  void bezierCurveTo(double x1, double y1, double x2, double y2, double x, double y) =>
      path.cubicTo(x1, y1, x2, y2, x, y);
  @override
  void closePath() => path.close();
}

/// d3 `line().x(p => p.x).y(p => p.y).defined(isWellBehaved).curve(factory)`
/// applied to [points]. A null point, or one with a non-finite coordinate,
/// splits the line exactly as d3's `defined` does. With [connectNulls]
/// Recharts filters undefined points out first instead.
void drawLine(
  PathSink sink,
  List<Offset?> points,
  CurveType type, {
  ChartLayout layout = ChartLayout.horizontal,
  bool connectNulls = false,
}) {
  final output = _getCurveFactory(type, layout)(_D3Path(sink));
  final data = connectNulls ? points.where(_defined).toList() : points;
  final n = data.length;
  var defined0 = false;

  for (var i = 0; i <= n; ++i) {
    final d = i < n ? data[i] : null;
    if (!(i < n && _defined(d)) == defined0) {
      defined0 = !defined0;
      if (defined0) {
        output.lineStart();
      } else {
        output.lineEnd();
      }
    }
    if (defined0) output.point(d!.dx, d.dy);
  }
}

/// Convenience: [drawLine] into a fresh Flutter [Path].
Path linePath(
  List<Offset?> points,
  CurveType type, {
  ChartLayout layout = ChartLayout.horizontal,
  bool connectNulls = false,
}) {
  final sink = FlutterPathSink();
  drawLine(sink, points, type, layout: layout, connectNulls: connectNulls);
  return sink.path;
}

/// Recharts `getPath` with a `baseLine` (src/shape/Curve.tsx), drawn with the
/// d3-shape `area()` generator. [baseLine] is either a number (the constant
/// y0 in horizontal layout, x0 in vertical) or a `List<Offset?>` paired with
/// [points] by index; a pair is drawn only when both ends are defined.
/// [connectNulls] filters exactly as getPath does.
void drawArea(
  PathSink sink,
  List<Offset?> points,
  Object baseLine,
  CurveType type, {
  ChartLayout layout = ChartLayout.horizontal,
  bool connectNulls = false,
}) {
  final vertical = layout == ChartLayout.vertical;
  final isArray = baseLine is List;
  // A NaN number baseLine is not isNumber() in Curve.tsx: plain line.
  if (!isArray && (baseLine as num).isNaN) {
    return drawLine(sink, points, type, layout: layout, connectNulls: connectNulls);
  }
  // Each entry: the point and its paired base (y0 horizontal, x0 vertical).
  final bases = isArray ? baseLine as List<Offset?> : null;
  final num0 = isArray ? 0.0 : (baseLine as num).toDouble();
  var items = <(Offset?, Offset?)>[
    for (var i = 0; i < points.length; i++) (points[i], isArray && i < bases!.length ? bases[i] : null),
  ];
  bool defined((Offset?, Offset?) e) => _defined(e.$1) && (!isArray || _defined(e.$2));
  if (connectNulls) items = items.where(defined).toList();

  final output = _getCurveFactory(type, layout)(_D3Path(sink));
  final n = items.length;
  final x0z = List<double>.filled(n, 0), y0z = List<double>.filled(n, 0);
  var defined0 = false;
  var j = 0;

  for (var i = 0; i <= n; ++i) {
    final d = i < n ? items[i] : null;
    if (!(i < n && defined(d!)) == defined0) {
      defined0 = !defined0;
      if (defined0) {
        j = i;
        output.areaStart();
        output.lineStart();
      } else {
        output.lineEnd();
        output.lineStart();
        for (var k = i - 1; k >= j; --k) {
          output.point(x0z[k], y0z[k]);
        }
        output.lineEnd();
        output.areaEnd();
      }
    }
    if (defined0) {
      final p = d!.$1!;
      if (vertical) {
        x0z[i] = isArray ? d.$2!.dx : num0;
        y0z[i] = p.dy;
      } else {
        x0z[i] = p.dx;
        y0z[i] = isArray ? d.$2!.dy : num0;
      }
      output.point(p.dx, p.dy);
    }
  }
}

/// Convenience: [drawArea] into a fresh Flutter [Path].
Path areaPath(
  List<Offset?> points,
  Object baseLine,
  CurveType type, {
  ChartLayout layout = ChartLayout.horizontal,
  bool connectNulls = false,
}) {
  final sink = FlutterPathSink();
  drawArea(sink, points, baseLine, type, layout: layout, connectNulls: connectNulls);
  return sink.path;
}

/// Curve.tsx `defined`: both coordinates are finite numbers.
bool _defined(Offset? p) => p != null && p.dx.isFinite && p.dy.isFinite;

typedef _CurveFactory = _Curve Function(PathSink context);

/// Curve.tsx `getCurveFactory`.
_CurveFactory _getCurveFactory(CurveType type, ChartLayout layout) => switch (type) {
      CurveType.basis => _Basis.new,
      CurveType.basisClosed => _BasisClosed.new,
      CurveType.basisOpen => _BasisOpen.new,
      CurveType.bumpX => (c) => _Bump(c, true),
      CurveType.bumpY => (c) => _Bump(c, false),
      CurveType.bump => (c) => _Bump(c, layout != ChartLayout.vertical),
      CurveType.linear => _Linear.new,
      CurveType.linearClosed => _LinearClosed.new,
      CurveType.natural => _Natural.new,
      CurveType.monotoneX => _MonotoneX.new,
      CurveType.monotoneY => _MonotoneY.new,
      CurveType.monotone => layout == ChartLayout.vertical ? _MonotoneY.new : _MonotoneX.new,
      CurveType.step => (c) => _Step(c, 0.5),
      CurveType.stepBefore => (c) => _Step(c, 0),
      CurveType.stepAfter => (c) => _Step(c, 1),
    };

/// d3-path `Path` with `digits = 3`: rounds every coordinate like
/// `Math.round(x * 1000) / 1000`, and drops `closePath` on an empty path.
class _D3Path implements PathSink {
  _D3Path(this._sink);
  final PathSink _sink;
  bool _empty = true;

  static double _r(double v) => jsRound(v * 1000) / 1000;

  @override
  void moveTo(double x, double y) {
    _empty = false;
    _sink.moveTo(_r(x), _r(y));
  }

  @override
  void lineTo(double x, double y) {
    _empty = false;
    _sink.lineTo(_r(x), _r(y));
  }

  @override
  void bezierCurveTo(double x1, double y1, double x2, double y2, double x, double y) {
    _empty = false;
    _sink.bezierCurveTo(_r(x1), _r(y1), _r(x2), _r(y2), _r(x), _r(y));
  }

  @override
  void closePath() {
    if (!_empty) _sink.closePath();
  }
}

/// JS truthiness of a number.
bool _truthy(double v) => v != 0 && !v.isNaN;

abstract class _Curve {
  void areaStart();
  void areaEnd();
  void lineStart();
  void lineEnd();
  void point(double x, double y);
}

// `_line` stays NaN (JS undefined) for lines; only area generators set it.

class _Linear implements _Curve {
  _Linear(this._context);
  final PathSink _context;
  double _line = double.nan;

  @override
  void areaStart() => _line = 0;
  @override
  void areaEnd() => _line = double.nan;
  int _point = 0;

  @override
  void lineStart() => _point = 0;

  @override
  void lineEnd() {
    if (_truthy(_line) || (_line != 0 && _point == 1)) _context.closePath();
    _line = 1 - _line;
  }

  @override
  void point(double x, double y) {
    switch (_point) {
      case 0:
        _point = 1;
        _truthy(_line) ? _context.lineTo(x, y) : _context.moveTo(x, y);
      case 1:
        _point = 2;
        _context.lineTo(x, y);
      default:
        _context.lineTo(x, y);
    }
  }
}

class _LinearClosed implements _Curve {
  _LinearClosed(this._context);
  final PathSink _context;

  @override
  void areaStart() {}
  @override
  void areaEnd() {}
  int _point = 0;

  @override
  void lineStart() => _point = 0;

  @override
  void lineEnd() {
    if (_point != 0) _context.closePath();
  }

  @override
  void point(double x, double y) {
    if (_point != 0) {
      _context.lineTo(x, y);
    } else {
      _point = 1;
      _context.moveTo(x, y);
    }
  }
}

class _Step implements _Curve {
  _Step(this._context, this._t);
  final PathSink _context;
  double _t;
  double _line = double.nan;

  @override
  void areaStart() => _line = 0;
  @override
  void areaEnd() => _line = double.nan;
  int _point = 0;
  double _x = double.nan, _y = double.nan;

  @override
  void lineStart() {
    _x = _y = double.nan;
    _point = 0;
  }

  @override
  void lineEnd() {
    if (0 < _t && _t < 1 && _point == 2) _context.lineTo(_x, _y);
    if (_truthy(_line) || (_line != 0 && _point == 1)) _context.closePath();
    if (_line >= 0) {
      _t = 1 - _t;
      _line = 1 - _line;
    }
  }

  @override
  void point(double x, double y) {
    if (_point == 0) {
      _point = 1;
      _truthy(_line) ? _context.lineTo(x, y) : _context.moveTo(x, y);
    } else {
      if (_point == 1) _point = 2;
      if (_t <= 0) {
        _context.lineTo(_x, y);
        _context.lineTo(x, y);
      } else {
        final x1 = _x * (1 - _t) + x * _t;
        _context.lineTo(x1, _y);
        _context.lineTo(x1, y);
      }
    }
    _x = x;
    _y = y;
  }
}

/// basis.js `point(that, x, y)` plus the state the basis curves share.
abstract class _BasisBase implements _Curve {
  _BasisBase(this._context);
  final PathSink _context;
  double _line = double.nan;

  @override
  void areaStart() => _line = 0;
  @override
  void areaEnd() => _line = double.nan;
  int _point = 0;
  double _x0 = double.nan, _x1 = double.nan, _y0 = double.nan, _y1 = double.nan;

  void _bezier(double x, double y) {
    _context.bezierCurveTo(
      (2 * _x0 + _x1) / 3,
      (2 * _y0 + _y1) / 3,
      (_x0 + 2 * _x1) / 3,
      (_y0 + 2 * _y1) / 3,
      (_x0 + 4 * _x1 + x) / 6,
      (_y0 + 4 * _y1 + y) / 6,
    );
  }

  void _shift(double x, double y) {
    _x0 = _x1;
    _x1 = x;
    _y0 = _y1;
    _y1 = y;
  }

  @override
  void lineStart() {
    _x0 = _x1 = _y0 = _y1 = double.nan;
    _point = 0;
  }
}

class _Basis extends _BasisBase {
  _Basis(super.context);

  @override
  void lineEnd() {
    switch (_point) {
      case 3:
        _bezier(_x1, _y1);
        _context.lineTo(_x1, _y1);
      case 2:
        _context.lineTo(_x1, _y1);
    }
    if (_truthy(_line) || (_line != 0 && _point == 1)) _context.closePath();
    _line = 1 - _line;
  }

  @override
  void point(double x, double y) {
    switch (_point) {
      case 0:
        _point = 1;
        _truthy(_line) ? _context.lineTo(x, y) : _context.moveTo(x, y);
      case 1:
        _point = 2;
      case 2:
        _point = 3;
        _context.lineTo((5 * _x0 + _x1) / 6, (5 * _y0 + _y1) / 6);
        _bezier(x, y);
      default:
        _bezier(x, y);
    }
    _shift(x, y);
  }
}

class _BasisClosed extends _BasisBase {
  _BasisClosed(super.context);

  @override
  void areaStart() {}
  @override
  void areaEnd() {}
  double _x2 = double.nan, _x3 = double.nan, _x4 = double.nan;
  double _y2 = double.nan, _y3 = double.nan, _y4 = double.nan;

  @override
  void lineStart() {
    super.lineStart();
    _x2 = _x3 = _x4 = _y2 = _y3 = _y4 = double.nan;
  }

  @override
  void lineEnd() {
    switch (_point) {
      case 1:
        _context.moveTo(_x2, _y2);
        _context.closePath();
      case 2:
        _context.moveTo((_x2 + 2 * _x3) / 3, (_y2 + 2 * _y3) / 3);
        _context.lineTo((_x3 + 2 * _x2) / 3, (_y3 + 2 * _y2) / 3);
        _context.closePath();
      case 3:
        point(_x2, _y2);
        point(_x3, _y3);
        point(_x4, _y4);
    }
  }

  @override
  void point(double x, double y) {
    switch (_point) {
      case 0:
        _point = 1;
        _x2 = x;
        _y2 = y;
      case 1:
        _point = 2;
        _x3 = x;
        _y3 = y;
      case 2:
        _point = 3;
        _x4 = x;
        _y4 = y;
        _context.moveTo((_x0 + 4 * _x1 + x) / 6, (_y0 + 4 * _y1 + y) / 6);
      default:
        _bezier(x, y);
    }
    _shift(x, y);
  }
}

class _BasisOpen extends _BasisBase {
  _BasisOpen(super.context);

  @override
  void lineEnd() {
    if (_truthy(_line) || (_line != 0 && _point == 3)) _context.closePath();
    _line = 1 - _line;
  }

  @override
  void point(double x, double y) {
    switch (_point) {
      case 0:
        _point = 1;
      case 1:
        _point = 2;
      case 2:
        _point = 3;
        final x0 = (_x0 + 4 * _x1 + x) / 6, y0 = (_y0 + 4 * _y1 + y) / 6;
        _truthy(_line) ? _context.lineTo(x0, y0) : _context.moveTo(x0, y0);
      case 3:
        _point = 4;
        _bezier(x, y);
      default:
        _bezier(x, y);
    }
    _shift(x, y);
  }
}

class _Natural implements _Curve {
  _Natural(this._context);
  final PathSink _context;
  double _line = double.nan;

  @override
  void areaStart() => _line = 0;
  @override
  void areaEnd() => _line = double.nan;
  List<double> _x = [], _y = [];

  @override
  void lineStart() {
    _x = [];
    _y = [];
  }

  @override
  void lineEnd() {
    final x = _x, y = _y, n = x.length;

    if (n > 0) {
      _truthy(_line) ? _context.lineTo(x[0], y[0]) : _context.moveTo(x[0], y[0]);
      if (n == 2) {
        _context.lineTo(x[1], y[1]);
      } else if (n > 2) {
        final px = _controlPoints(x), py = _controlPoints(y);
        for (var i0 = 0, i1 = 1; i1 < n; ++i0, ++i1) {
          _context.bezierCurveTo(px.$1[i0], py.$1[i0], px.$2[i0], py.$2[i0], x[i1], y[i1]);
        }
      }
    }

    if (_truthy(_line) || (_line != 0 && n == 1)) _context.closePath();
    _line = 1 - _line;
  }

  @override
  void point(double x, double y) {
    _x.add(x);
    _y.add(y);
  }

  // See https://www.particleincell.com/2012/bezier-splines/ for derivation.
  static (List<double>, List<double>) _controlPoints(List<double> x) {
    final n = x.length - 1;
    final a = List<double>.filled(n, 0), b = List<double>.filled(n, 0), r = List<double>.filled(n, 0);
    a[0] = 0;
    b[0] = 2;
    r[0] = x[0] + 2 * x[1];
    for (var i = 1; i < n - 1; ++i) {
      a[i] = 1;
      b[i] = 4;
      r[i] = 4 * x[i] + 2 * x[i + 1];
    }
    a[n - 1] = 2;
    b[n - 1] = 7;
    r[n - 1] = 8 * x[n - 1] + x[n];
    for (var i = 1; i < n; ++i) {
      final m = a[i] / b[i - 1];
      b[i] -= m;
      r[i] -= m * r[i - 1];
    }
    a[n - 1] = r[n - 1] / b[n - 1];
    for (var i = n - 2; i >= 0; --i) {
      a[i] = (r[i] - a[i + 1]) / b[i];
    }
    b[n - 1] = (x[n] + a[n - 1]) / 2;
    for (var i = 0; i < n - 1; ++i) {
      b[i] = 2 * x[i + 1] - a[i + 1];
    }
    return (a, b);
  }
}

double _sign(double x) => x < 0 ? -1 : 1;

class _MonotoneX implements _Curve {
  _MonotoneX(this._context);
  final PathSink _context;
  double _line = double.nan;

  @override
  void areaStart() => _line = 0;
  @override
  void areaEnd() => _line = double.nan;
  int _point = 0;
  double _x0 = double.nan, _x1 = double.nan, _y0 = double.nan, _y1 = double.nan, _t0 = double.nan;

  // Steffen, M. 1990. A Simple Method for Monotonic Interpolation in One
  // Dimension. Astronomy and Astrophysics, Vol. 239, NO. NOV(II), P. 443.
  double _slope3(double x2, double y2) {
    final h0 = _x1 - _x0,
        h1 = x2 - _x1,
        s0 = (_y1 - _y0) / (_truthy(h0) ? h0 : (h1 < 0 ? -0.0 : 0.0)),
        s1 = (y2 - _y1) / (_truthy(h1) ? h1 : (h0 < 0 ? -0.0 : 0.0)),
        p = (s0 * h1 + s1 * h0) / (h0 + h1);
    final r = (_sign(s0) + _sign(s1)) * math.min(math.min(s0.abs(), s1.abs()), 0.5 * p.abs());
    return _truthy(r) ? r : 0;
  }

  double _slope2(double t) {
    final h = _x1 - _x0;
    return _truthy(h) ? (3 * (_y1 - _y0) / h - t) / 2 : t;
  }

  void _hermite(double t0, double t1) {
    final x0 = _x0, y0 = _y0, x1 = _x1, y1 = _y1, dx = (x1 - x0) / 3;
    _context.bezierCurveTo(x0 + dx, y0 + dx * t0, x1 - dx, y1 - dx * t1, x1, y1);
  }

  @override
  void lineStart() {
    _x0 = _x1 = _y0 = _y1 = _t0 = double.nan;
    _point = 0;
  }

  @override
  void lineEnd() {
    switch (_point) {
      case 2:
        _context.lineTo(_x1, _y1);
      case 3:
        _hermite(_t0, _slope2(_t0));
    }
    if (_truthy(_line) || (_line != 0 && _point == 1)) _context.closePath();
    _line = 1 - _line;
  }

  @override
  void point(double x, double y) {
    var t1 = double.nan;

    if (x == _x1 && y == _y1) return; // Ignore coincident points.
    switch (_point) {
      case 0:
        _point = 1;
        _truthy(_line) ? _context.lineTo(x, y) : _context.moveTo(x, y);
      case 1:
        _point = 2;
      case 2:
        _point = 3;
        t1 = _slope3(x, y);
        _hermite(_slope2(t1), t1);
      default:
        t1 = _slope3(x, y);
        _hermite(_t0, t1);
    }

    _x0 = _x1;
    _x1 = x;
    _y0 = _y1;
    _y1 = y;
    _t0 = t1;
  }
}

class _MonotoneY extends _MonotoneX {
  _MonotoneY(PathSink context) : super(_ReflectContext(context));

  @override
  void point(double x, double y) => super.point(y, x);
}

class _ReflectContext implements PathSink {
  _ReflectContext(this._context);
  final PathSink _context;

  @override
  void moveTo(double x, double y) => _context.moveTo(y, x);
  @override
  void closePath() => _context.closePath();
  @override
  void lineTo(double x, double y) => _context.lineTo(y, x);
  @override
  void bezierCurveTo(double x1, double y1, double x2, double y2, double x, double y) =>
      _context.bezierCurveTo(y1, x1, y2, x2, y, x);
}

class _Bump implements _Curve {
  _Bump(this._context, this._x);
  final PathSink _context;
  final bool _x;
  double _line = double.nan;

  @override
  void areaStart() => _line = 0;
  @override
  void areaEnd() => _line = double.nan;
  int _point = 0;
  double _x0 = double.nan, _y0 = double.nan;

  @override
  void lineStart() => _point = 0;

  @override
  void lineEnd() {
    if (_truthy(_line) || (_line != 0 && _point == 1)) _context.closePath();
    _line = 1 - _line;
  }

  @override
  void point(double x, double y) {
    if (_point == 0) {
      _point = 1;
      _truthy(_line) ? _context.lineTo(x, y) : _context.moveTo(x, y);
    } else {
      if (_point == 1) _point = 2;
      if (_x) {
        _x0 = (_x0 + x) / 2;
        _context.bezierCurveTo(_x0, _y0, _x0, y, x, y);
      } else {
        _y0 = (_y0 + y) / 2;
        _context.bezierCurveTo(_x0, _y0, x, _y0, x, y);
      }
    }
    _x0 = x;
    _y0 = y;
  }
}
