// JavaScript number semantics the ports need to match V8 bit for bit:
// Math.round, Math.log / Math.log10 (V8's fdlibm ports in
// src/base/ieee754.cc) and parseFloat.

import 'dart:math' as math;
import 'dart:typed_data';

/// JS `Math.round`: halves round towards +Infinity.
double jsRound(double x) {
  if (!x.isFinite) return x;
  final r = x.floorToDouble();
  return x - r >= 0.5 ? r + 1 : r;
}

final ByteData _buf = ByteData(8);

double _fromWords(int hi, int lo) => (_buf
      ..setUint32(0, hi)
      ..setUint32(4, lo))
    .getFloat64(0);

int _hi(double x) => (_buf..setFloat64(0, x)).getInt32(0);
int _lo(double x) => (_buf..setFloat64(0, x)).getUint32(4);

double _setHi(double x, int hi) => (_buf
      ..setFloat64(0, x)
      ..setInt32(0, hi))
    .getFloat64(0);

final double _ln2Hi = _fromWords(0x3fe62e42, 0xfee00000);
final double _ln2Lo = _fromWords(0x3dea39ef, 0x35793c76);
final double _two54 = _fromWords(0x43500000, 0x00000000);
final double _lg1 = _fromWords(0x3FE55555, 0x55555593);
final double _lg2 = _fromWords(0x3FD99999, 0x9997FA04);
final double _lg3 = _fromWords(0x3FD24924, 0x94229359);
final double _lg4 = _fromWords(0x3FCC71C5, 0x1D8E78AF);
final double _lg5 = _fromWords(0x3FC74664, 0x96CB03DE);
final double _lg6 = _fromWords(0x3FC39A09, 0xD078C69F);
final double _lg7 = _fromWords(0x3FC2F112, 0xDF3E5244);
final double _ivln10 = _fromWords(0x3FDBCB7B, 0x1526E50E);
final double _log10_2hi = _fromWords(0x3FD34413, 0x509F6000);
final double _log10_2lo = _fromWords(0x3D59FEF3, 0x11F12B36);

/// JS `Math.log` (fdlibm e_log.c).
double jsLog(double x) {
  var hx = _hi(x);
  final lx = _lo(x);
  var k = 0;
  if (hx < 0x00100000) {
    if (((hx & 0x7fffffff) | lx) == 0) return double.negativeInfinity;
    if (hx < 0) return double.nan;
    k -= 54;
    x *= _two54;
    hx = _hi(x);
  }
  if (hx >= 0x7ff00000) return x + x;
  k += (hx >> 20) - 1023;
  hx &= 0x000fffff;
  var i = (hx + 0x95f64) & 0x100000;
  x = _setHi(x, hx | (i ^ 0x3ff00000));
  k += i >> 20;
  final f = x - 1.0;
  if ((0x000fffff & (2 + hx)) < 3) {
    if (f == 0) {
      if (k == 0) return 0;
      final dk = k.toDouble();
      return dk * _ln2Hi + dk * _ln2Lo;
    }
    final r = f * f * (0.5 - 0.33333333333333333 * f);
    if (k == 0) return f - r;
    final dk = k.toDouble();
    return dk * _ln2Hi - ((r - dk * _ln2Lo) - f);
  }
  final s = f / (2.0 + f);
  final dk = k.toDouble();
  final z = s * s;
  i = hx - 0x6147a;
  final w = z * z;
  final j = 0x6b851 - hx;
  final t1 = w * (_lg2 + w * (_lg4 + w * _lg6));
  final t2 = z * (_lg1 + w * (_lg3 + w * (_lg5 + w * _lg7)));
  i |= j;
  final r = t2 + t1;
  if (i > 0) {
    final hfsq = 0.5 * f * f;
    if (k == 0) return f - (hfsq - s * (hfsq + r));
    return dk * _ln2Hi - ((hfsq - (s * (hfsq + r) + dk * _ln2Lo)) - f);
  }
  if (k == 0) return f - s * (f - r);
  return dk * _ln2Hi - ((s * (f - r) - dk * _ln2Lo) - f);
}

/// JS `Math.log10` (fdlibm e_log10.c; exact for powers of ten).
double jsLog10(double x) {
  var hx = _hi(x);
  var lx = _lo(x);
  var k = 0;
  if (hx < 0x00100000) {
    if (((hx & 0x7fffffff) | lx) == 0) return double.negativeInfinity;
    if (hx < 0) return double.nan;
    k -= 54;
    x *= _two54;
    hx = _hi(x);
    lx = _lo(x);
  }
  if (hx >= 0x7ff00000) return x + x;
  if (hx == 0x3ff00000 && lx == 0) return 0;
  k += (hx >> 20) - 1023;
  final i = k < 0 ? 1 : 0;
  hx = (hx & 0x000fffff) | ((0x3ff - i) << 20);
  final y = (k + i).toDouble();
  x = _setHi(x, hx);
  final z = y * _log10_2lo + _ivln10 * jsLog(x);
  return z + y * _log10_2hi;
}

/// JS `Math.log2`, exact for powers of two.
// ponytail: log/ln2 instead of a port of V8's log2; only base-2 log scales use it.
double jsLog2(double x) {
  if (x > 0 && x.isFinite) {
    final e = (_hi(x) >> 20) - 1023;
    if ((_hi(x) & 0x000fffff) == 0 && _lo(x) == 0 && e > -1023) return e.toDouble();
  }
  return jsLog(x) / math.ln2;
}

final RegExp _floatPrefix = RegExp(r'^[+-]?(Infinity|(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?)');

/// JS `parseFloat`: the longest numeric prefix after leading whitespace.
double jsParseFloat(String s) {
  final m = _floatPrefix.firstMatch(s.trimLeft());
  if (m == null) return double.nan;
  final t = m[0]!;
  if (t.endsWith('Infinity')) return t.startsWith('-') ? double.negativeInfinity : double.infinity;
  return double.parse(t);
}
