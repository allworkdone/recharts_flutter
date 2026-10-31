// Port of src/shape/Symbols.tsx (calculateAreaSize, Symbols' path) and the
// d3-shape 3.2.0 symbol types it registers: src/symbol/{circle,cross,diamond,
// square,star,triangle,wye}.js, drawn through d3-path 3.1.0 src/path.js with
// `digits = 3` (moveTo, lineTo, arc, rect, closePath). Symbols record into a
// [SymbolPathSink] so tests can compare the exact commands d3 emits.

import 'dart:math' as math;
import 'dart:ui';

import 'js_math.dart';

/// Recharts' `SymbolType`.
enum SymbolType { circle, cross, diamond, square, star, triangle, wye }

/// `sizeType` of Symbols: `size` is the area, or the diameter of the shape.
enum SymbolSizeType { area, diameter }

const _radian = math.pi / 180;

/// `calculateAreaSize(size, sizeType, type)`.
double calculateAreaSize(double size, SymbolSizeType sizeType, SymbolType type) {
  if (sizeType == SymbolSizeType.area) return size;
  switch (type) {
    case SymbolType.cross:
      return (5 * size * size) / 9;
    case SymbolType.diamond:
      return (0.5 * size * size) / math.sqrt(3);
    case SymbolType.square:
      return size * size;
    case SymbolType.star:
      const angle = 18 * _radian;
      return 1.25 * size * size * (math.tan(angle) - math.tan(angle * 2) * math.pow(math.tan(angle), 2));
    case SymbolType.triangle:
      return (math.sqrt(3) * size * size) / 4;
    case SymbolType.wye:
      return ((21 - 10 * math.sqrt(3)) * size * size) / 8;
    case SymbolType.circle:
      return (math.pi * size * size) / 4;
  }
}

/// The SVG commands d3-path writes for a symbol, already rounded. `rect`
/// arrives as its absolute equivalents (`M`, three `L`, `Z`).
abstract class SymbolPathSink {
  void moveTo(double x, double y);
  void lineTo(double x, double y);

  /// SVG `A rx,ry,0,largeArc,sweep,x,y`.
  void arcTo(double rx, double ry, bool largeArc, bool sweep, double x, double y);
  void closePath();
}

/// Writes into a Flutter [Path].
class FlutterSymbolSink implements SymbolPathSink {
  final Path path = Path();

  @override
  void moveTo(double x, double y) => path.moveTo(x, y);
  @override
  void lineTo(double x, double y) => path.lineTo(x, y);
  @override
  void arcTo(double rx, double ry, bool largeArc, bool sweep, double x, double y) =>
      path.arcToPoint(Offset(x, y), radius: Radius.elliptical(rx, ry), largeArc: largeArc, clockwise: sweep);
  @override
  void closePath() => path.close();
}

const _pi = math.pi, _tau = 2 * math.pi, _epsilon = 1e-6, _tauEpsilon = _tau - _epsilon;

/// d3-path `Path` with `digits = 3`, for the calls symbols make.
class _D3Path {
  _D3Path(this._sink);
  final SymbolPathSink _sink;
  double? _x0, _y0, _x1, _y1;

  static double _r(double v) => jsRound(v * 1000) / 1000;

  void moveTo(double x, double y) {
    _x0 = _x1 = x;
    _y0 = _y1 = y;
    _sink.moveTo(_r(x), _r(y));
  }

  void lineTo(double x, double y) {
    _x1 = x;
    _y1 = y;
    _sink.lineTo(_r(x), _r(y));
  }

  void closePath() {
    if (_x1 != null) {
      _x1 = _x0;
      _y1 = _y0;
      _sink.closePath();
    }
  }

  void arc(double x, double y, double r, double a0, double a1) {
    final dx = r * math.cos(a0), dy = r * math.sin(a0);
    final x0 = x + dx, y0 = y + dy;
    var da = a1 - a0;
    // d3 writes this M / L without moving its current point.
    if (_x1 == null) {
      _sink.moveTo(_r(x0), _r(y0));
    } else if ((_x1! - x0).abs() > _epsilon || (_y1! - y0).abs() > _epsilon) {
      _sink.lineTo(_r(x0), _r(y0));
    }
    if (r == 0 || r.isNaN) return;
    if (da < 0) da = da % _tau + _tau;
    final rr = _r(r);
    if (da > _tauEpsilon) {
      _sink.arcTo(rr, rr, true, true, _r(x - dx), _r(y - dy));
      _x1 = x0;
      _y1 = y0;
      _sink.arcTo(rr, rr, true, true, _r(x0), _r(y0));
    } else if (da > _epsilon) {
      _x1 = x + r * math.cos(a1);
      _y1 = y + r * math.sin(a1);
      _sink.arcTo(rr, rr, da >= _pi, true, _r(_x1!), _r(_y1!));
    }
  }

  /// `M x,y h w v h h -w Z`, each number rounded on its own.
  void rect(double x, double y, double w, double h) {
    _x0 = _x1 = x;
    _y0 = _y1 = y;
    final rx = _r(x), ry = _r(y), x1 = rx + _r(w), y1 = ry + _r(h);
    _sink
      ..moveTo(rx, ry)
      ..lineTo(x1, ry)
      ..lineTo(x1, y1)
      ..lineTo(x1 + _r(-w), y1)
      ..closePath();
  }
}

const _sqrt3 = 1.7320508075688772; // Math.sqrt(3)
final _tan30 = math.sqrt(1 / 3);
const _ka = 0.89081309152928522810;
final _kr = math.sin(_pi / 10) / math.sin(7 * _pi / 10);
final _kx = math.sin(_tau / 10) * _kr;
final _ky = -math.cos(_tau / 10) * _kr;
const _wc = -0.5;
final _ws = math.sqrt(3) / 2;
final _wk = 1 / math.sqrt(12);
final _wa = (_wk / 2 + 1) * 3;

/// d3 `symbol().type(symbolX).size(size)()` drawn into [sink]; [size] is the area.
void drawSymbol(SymbolPathSink sink, SymbolType type, double size) {
  final c = _D3Path(sink);
  switch (type) {
    case SymbolType.circle:
      final r = math.sqrt(size / _pi);
      c.moveTo(r, 0);
      c.arc(0, 0, r, 0, _tau);
    case SymbolType.cross:
      final r = math.sqrt(size / 5) / 2;
      c.moveTo(-3 * r, -r);
      c.lineTo(-r, -r);
      c.lineTo(-r, -3 * r);
      c.lineTo(r, -3 * r);
      c.lineTo(r, -r);
      c.lineTo(3 * r, -r);
      c.lineTo(3 * r, r);
      c.lineTo(r, r);
      c.lineTo(r, 3 * r);
      c.lineTo(-r, 3 * r);
      c.lineTo(-r, r);
      c.lineTo(-3 * r, r);
      c.closePath();
    case SymbolType.diamond:
      final y = math.sqrt(size / (_tan30 * 2));
      final x = y * _tan30;
      c.moveTo(0, -y);
      c.lineTo(x, 0);
      c.lineTo(0, y);
      c.lineTo(-x, 0);
      c.closePath();
    case SymbolType.square:
      final w = math.sqrt(size);
      final x = -w / 2;
      c.rect(x, x, w, w);
    case SymbolType.star:
      final r = math.sqrt(size * _ka);
      final x = _kx * r;
      final y = _ky * r;
      c.moveTo(0, -r);
      c.lineTo(x, y);
      for (var i = 1; i < 5; ++i) {
        final a = _tau * i / 5;
        final cs = math.cos(a);
        final s = math.sin(a);
        c.lineTo(s * r, -cs * r);
        c.lineTo(cs * x - s * y, s * x + cs * y);
      }
      c.closePath();
    case SymbolType.triangle:
      final y = -math.sqrt(size / (_sqrt3 * 3));
      c.moveTo(0, y * 2);
      c.lineTo(-_sqrt3 * y, -y);
      c.lineTo(_sqrt3 * y, -y);
      c.closePath();
    case SymbolType.wye:
      final r = math.sqrt(size / _wa);
      final x0 = r / 2, y0 = r * _wk;
      final x1 = x0, y1 = r * _wk + r;
      final x2 = -x1, y2 = y1;
      c.moveTo(x0, y0);
      c.lineTo(x1, y1);
      c.lineTo(x2, y2);
      c.lineTo(_wc * x0 - _ws * y0, _ws * x0 + _wc * y0);
      c.lineTo(_wc * x1 - _ws * y1, _ws * x1 + _wc * y1);
      c.lineTo(_wc * x2 - _ws * y2, _ws * x2 + _wc * y2);
      c.lineTo(_wc * x0 + _ws * y0, _wc * y0 - _ws * x0);
      c.lineTo(_wc * x1 + _ws * y1, _wc * y1 - _ws * x1);
      c.lineTo(_wc * x2 + _ws * y2, _wc * y2 - _ws * x2);
      c.closePath();
  }
}

/// The `d` of `<Symbols type size sizeType>` as a Flutter [Path] centered at
/// the origin (Symbols translates it to `cx, cy`).
Path symbolPath(SymbolType type, double size, {SymbolSizeType sizeType = SymbolSizeType.area}) {
  final sink = FlutterSymbolSink();
  drawSymbol(sink, type, calculateAreaSize(size, sizeType, type));
  return sink.path;
}
