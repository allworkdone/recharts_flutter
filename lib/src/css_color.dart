// A CSS color string reader for the `fill` and `stroke` Recharts takes from
// data entries and `<Cell>`: #rgb, #rgba, #rrggbb, #rrggbbaa, rgb()/rgba() and
// hsl()/hsla() (comma or space separated, percentages, `/ alpha`), hwb(),
// lab(), lch(), oklab() and oklch() (space separated, CSS Color 4
// conversions to sRGB), the CSS named colors, `transparent` and `none`.

import 'dart:math' as math;
import 'dart:ui' show Color;

/// A `Color` that paints nothing: CSS `none`. It is transparent wherever it is
/// painted, but unlike `transparent` it is not hit-testable, and legend and
/// tooltip text drop it and keep the inherited text color (`color: none` is
/// invalid CSS). Compare with [isCssNone], not `==`.
class CssNone extends Color {
  const CssNone() : super(0x00000000);
}

const Color cssNone = CssNone();

bool isCssNone(Color? c) => c is CssNone;

/// The text color a legend or tooltip row takes from a series color: null
/// (inherit) for `none`.
Color? textColorOf(Color? c) => isCssNone(c) ? null : c;

/// The color a CSS string names; null for `none` and for anything that is not
/// a color. Use [cssFillOf] / [cssStrokeOf] for data entries, which tell `none`
/// and invalid strings apart.
///
/// ponytail: color() and color-mix() are not parsed (null). Colors outside
/// sRGB are clipped per channel, as Chrome paints them on an sRGB canvas.
Color? parseCssColor(String input) {
  final s = input.trim().toLowerCase();
  if (s == 'none') return null;
  if (s == 'transparent') return const Color(0x00000000);
  // ponytail: no CSS color inheritance here, so currentColor is the default text color, black.
  if (s == 'currentcolor') return const Color(0xFF000000);
  final named = _named[s];
  if (named != null) return Color(named);
  if (s.startsWith('#')) return _hex(s.substring(1));
  final m = RegExp(r'^(rgba?|hsla?|hwb|lab|lch|oklab|oklch)\(\s*([^)]*?)\s*\)$').firstMatch(s);
  if (m == null) return null;
  final legacy = m[2]!.contains(',');
  // The color functions after hsl() have no comma syntax.
  if (legacy && !m[1]!.startsWith('rgb') && !m[1]!.startsWith('hsl')) return null;
  final parts = _functionArguments(m[2]!);
  if (parts == null) return null;
  final alpha = parts.length == 4 ? _alpha(parts[3]) : 1.0;
  if (alpha == null) return null;
  final a = (alpha.clamp(0.0, 1.0) * 255).round();
  switch (m[1]) {
    case 'hwb':
      final (h, w, b) = (_hue(parts[0]), _unitInterval(parts[1], requirePercent: false), _unitInterval(parts[2], requirePercent: false));
      return h == null || w == null || b == null ? null : _hwb(h, w.clamp(0.0, 1.0), b.clamp(0.0, 1.0), a);
    case 'lab' || 'oklab':
      final ok = m[1] == 'oklab';
      // L: lab 0..100 (100% = 100), oklab 0..1 (100% = 1); a and b: 100% = 125 (lab) or 0.4 (oklab).
      final l = _scaled(parts[0], ok ? 0.01 : 1), x = _scaled(parts[1], ok ? 0.004 : 1.25), y = _scaled(parts[2], ok ? 0.004 : 1.25);
      if (l == null || x == null || y == null) return null;
      return ok ? _oklab(l.clamp(0.0, 1.0), x, y, a) : _lab(l.clamp(0.0, 100.0), x, y, a);
    case 'lch' || 'oklch':
      final ok = m[1] == 'oklch';
      // C: 100% = 150 (lch) or 0.4 (oklch), never negative.
      final l = _scaled(parts[0], ok ? 0.01 : 1), c = _scaled(parts[1], ok ? 0.004 : 1.5), h = _hue(parts[2]);
      if (l == null || c == null || h == null) return null;
      final r = math.max(0.0, c), rad = h * math.pi / 180;
      final (x, y) = (r * math.cos(rad), r * math.sin(rad));
      return ok ? _oklab(l.clamp(0.0, 1.0), x, y, a) : _lab(l.clamp(0.0, 100.0), x, y, a);
  }
  if (m[1]!.startsWith('rgb')) {
    final c = [for (final p in parts.take(3)) _channel(p)];
    if (c.contains(null)) return null;
    // The comma syntax takes three numbers or three percentages, never a mix.
    if (legacy && parts.take(3).any((p) => p.endsWith('%')) && !parts.take(3).every((p) => p.endsWith('%'))) return null;
    return Color.fromARGB(a, c[0]!, c[1]!, c[2]!);
  }
  final h = _hue(parts[0]);
  final sat = _unitInterval(parts[1], requirePercent: legacy), l = _unitInterval(parts[2], requirePercent: legacy);
  if (h == null || sat == null || l == null) return null;
  return _hsl(h, sat.clamp(0.0, 1.0), l.clamp(0.0, 1.0), a);
}

/// A data entry's `fill`: a [Color] as it is, `none` as [cssNone], a CSS string
/// parsed. An unparseable string is ignored by SVG, so the fill inherits the
/// default black; null for anything that is not a string or a Color (absent).
Color? cssFillOf(Object? v) => _entryColor(v, const Color(0xFF000000));

/// A data entry's `stroke`: like [cssFillOf], but an unparseable string leaves
/// no stroke ([cssNone]).
Color? cssStrokeOf(Object? v) => _entryColor(v, cssNone);

Color? _entryColor(Object? v, Color invalid) {
  if (v is Color) return v;
  if (v is! String) return null;
  if (v.trim().toLowerCase() == 'none') return cssNone;
  return parseCssColor(v) ?? invalid;
}

/// The 3 or 4 arguments of rgb()/hsl(): comma separated (3 or 4, no `/`) or
/// space separated with `/` before the alpha; null when the shape is invalid.
List<String>? _functionArguments(String body) {
  if (body.contains(',')) {
    if (body.contains('/')) return null;
    final parts = [for (final p in body.split(',')) p.trim()];
    return (parts.length == 3 || parts.length == 4) && !parts.contains('none') ? parts : null;
  }
  final halves = body.split('/');
  if (halves.length > 2) return null;
  final head = halves[0].trim().split(RegExp(r'\s+'));
  if (head.length != 3) return null;
  if (halves.length == 1) return head;
  final alpha = halves[1].trim();
  return alpha.isEmpty || alpha.contains(RegExp(r'\s')) ? null : [...head, alpha];
}

final _number = r'[+-]?(?:\d+(?:\.\d+)?|\.\d+)(?:e[+-]?\d+)?';
final _numberPattern = RegExp('^$_number\$');
final _percentPattern = RegExp('^($_number)%\$');

/// A plain number, or a percentage as its value; the `none` keyword is 0.
({double value, bool percent})? _component(String v) {
  if (v == 'none') return (value: 0, percent: false);
  if (_numberPattern.hasMatch(v)) return (value: double.parse(v), percent: false);
  final m = _percentPattern.firstMatch(v);
  return m == null ? null : (value: double.parse(m[1]!), percent: true);
}

Color? _hex(String hex) {
  if (!RegExp(r'^[0-9a-f]+$').hasMatch(hex)) return null;
  if (hex.length == 3 || hex.length == 4) hex = hex.split('').map((c) => '$c$c').join();
  if (hex.length == 6) return Color(0xFF000000 | int.parse(hex, radix: 16));
  if (hex.length == 8) {
    final v = int.parse(hex, radix: 16);
    return Color(((v & 0xFF) << 24) | (v >> 8));
  }
  return null;
}

int? _channel(String v) {
  final c = _component(v);
  return c == null ? null : (c.percent ? c.value * 255 / 100 : c.value).clamp(0, 255).round();
}

/// hsl() saturation and lightness: a percentage, or (space syntax) a bare number read as a percentage.
double? _unitInterval(String v, {required bool requirePercent}) {
  final c = _component(v);
  if (c == null || (requirePercent && !c.percent)) return null;
  return c.value / 100;
}

double? _alpha(String v) {
  final c = _component(v);
  return c == null ? null : (c.percent ? c.value / 100 : c.value);
}

/// Hue in degrees (deg, grad, rad, turn or unitless); `none` is 0.
double? _hue(String v) {
  if (v == 'none') return 0;
  final m = RegExp('^($_number)(deg|grad|rad|turn)?\$').firstMatch(v);
  if (m == null) return null;
  final n = double.parse(m[1]!);
  return switch (m[2]) {
    'grad' => n * 0.9,
    'rad' => n * 180 / math.pi,
    'turn' => n * 360,
    _ => n,
  };
}

Color _hsl(double h, double s, double l, int a) {
  final (r, g, b) = _hslRgb(h, s, l);
  return _rgb(r, g, b, a);
}

(double, double, double) _hslRgb(double h, double s, double l) {
  h = ((h % 360) + 360) % 360;
  double f(int n) {
    final k = (n + h / 30) % 12;
    return l - s * math.min(l, 1 - l) * math.max(-1, math.min(math.min(k - 3, 9 - k), 1));
  }

  return (f(0), f(8), f(4));
}

/// Gamma-encoded sRGB in 0..1, clipped.
Color _rgb(double r, double g, double b, int a) {
  int c(double v) => (v.clamp(0.0, 1.0) * 255).round();
  return Color.fromARGB(a, c(r), c(g), c(b));
}

/// A lab()/oklab() component: a number, or a percentage times [percent]; `none` is 0.
double? _scaled(String v, double percent) {
  final c = _component(v);
  return c == null ? null : (c.percent ? c.value * percent : c.value);
}

/// hwbToRgb: the pure hue mixed with white and black; past 100% they make a gray.
Color _hwb(double h, double w, double b, int a) {
  if (w + b >= 1) {
    final gray = w / (w + b);
    return _rgb(gray, gray, gray, a);
  }
  final (r, g, bl) = _hslRgb(h, 1, 0.5);
  double mix(double v) => v * (1 - w - b) + w;
  return _rgb(mix(r), mix(g), mix(bl), a);
}

/// Linear-light sRGB to gamma-encoded (gam_sRGB).
double _gamma(double v) {
  final abs = v.abs();
  return abs > 0.0031308 ? v.sign * (1.055 * math.pow(abs, 1 / 2.4) - 0.055) : 12.92 * v;
}

/// CIE Lab (D50 white) to sRGB: Lab_to_XYZ, D50_to_D65 (Bradford), XYZ_to_lin_sRGB, gam_sRGB.
Color _lab(double l, double a, double b, int alpha) {
  const k = 24389 / 27, e = 216 / 24389;
  final fy = (l + 16) / 116, fx = a / 500 + fy, fz = fy - b / 200;
  double inv(double f) => f * f * f > e ? f * f * f : (116 * f - 16) / k;
  final x50 = inv(fx) * 0.3457 / 0.3585, y50 = l > k * e ? fy * fy * fy : l / k, z50 = inv(fz) * (1 - 0.3457 - 0.3585) / 0.3585;
  final x = 0.955473421488075 * x50 - 0.02309845494876471 * y50 + 0.06325924320057072 * z50;
  final y = -0.0283697093338637 * x50 + 1.0099953980813041 * y50 + 0.021041441191917323 * z50;
  final z = 0.012314014864481998 * x50 - 0.020507649298898964 * y50 + 1.330365926242124 * z50;
  return _rgb(
    _gamma(12831 / 3959 * x - 329 / 214 * y - 1974 / 3959 * z),
    _gamma(-851781 / 878810 * x + 1648619 / 878810 * y + 36519 / 878810 * z),
    _gamma(705 / 12673 * x - 2585 / 12673 * y + 705 / 667 * z),
    alpha,
  );
}

/// OKLab to sRGB (Ottosson's OKLab to linear sRGB, then gam_sRGB).
Color _oklab(double l, double a, double b, int alpha) {
  double cube(double v) => v * v * v;
  final lms = (
    cube(l + 0.3963377774 * a + 0.2158037573 * b),
    cube(l - 0.1055613458 * a - 0.0638541728 * b),
    cube(l - 0.0894841775 * a - 1.2914855480 * b),
  );
  return _rgb(
    _gamma(4.0767416621 * lms.$1 - 3.3077115913 * lms.$2 + 0.2309699292 * lms.$3),
    _gamma(-1.2684380046 * lms.$1 + 2.6097574011 * lms.$2 - 0.3413193965 * lms.$3),
    _gamma(-0.0041960863 * lms.$1 - 0.7034186147 * lms.$2 + 1.7076147010 * lms.$3),
    alpha,
  );
}

const _named = <String, int>{
  'aliceblue': 0xFFF0F8FF,
  'antiquewhite': 0xFFFAEBD7,
  'aqua': 0xFF00FFFF,
  'aquamarine': 0xFF7FFFD4,
  'azure': 0xFFF0FFFF,
  'beige': 0xFFF5F5DC,
  'bisque': 0xFFFFE4C4,
  'black': 0xFF000000,
  'blanchedalmond': 0xFFFFEBCD,
  'blue': 0xFF0000FF,
  'blueviolet': 0xFF8A2BE2,
  'brown': 0xFFA52A2A,
  'burlywood': 0xFFDEB887,
  'cadetblue': 0xFF5F9EA0,
  'chartreuse': 0xFF7FFF00,
  'chocolate': 0xFFD2691E,
  'coral': 0xFFFF7F50,
  'cornflowerblue': 0xFF6495ED,
  'cornsilk': 0xFFFFF8DC,
  'crimson': 0xFFDC143C,
  'cyan': 0xFF00FFFF,
  'darkblue': 0xFF00008B,
  'darkcyan': 0xFF008B8B,
  'darkgoldenrod': 0xFFB8860B,
  'darkgray': 0xFFA9A9A9,
  'darkgreen': 0xFF006400,
  'darkgrey': 0xFFA9A9A9,
  'darkkhaki': 0xFFBDB76B,
  'darkmagenta': 0xFF8B008B,
  'darkolivegreen': 0xFF556B2F,
  'darkorange': 0xFFFF8C00,
  'darkorchid': 0xFF9932CC,
  'darkred': 0xFF8B0000,
  'darksalmon': 0xFFE9967A,
  'darkseagreen': 0xFF8FBC8F,
  'darkslateblue': 0xFF483D8B,
  'darkslategray': 0xFF2F4F4F,
  'darkslategrey': 0xFF2F4F4F,
  'darkturquoise': 0xFF00CED1,
  'darkviolet': 0xFF9400D3,
  'deeppink': 0xFFFF1493,
  'deepskyblue': 0xFF00BFFF,
  'dimgray': 0xFF696969,
  'dimgrey': 0xFF696969,
  'dodgerblue': 0xFF1E90FF,
  'firebrick': 0xFFB22222,
  'floralwhite': 0xFFFFFAF0,
  'forestgreen': 0xFF228B22,
  'fuchsia': 0xFFFF00FF,
  'gainsboro': 0xFFDCDCDC,
  'ghostwhite': 0xFFF8F8FF,
  'gold': 0xFFFFD700,
  'goldenrod': 0xFFDAA520,
  'gray': 0xFF808080,
  'green': 0xFF008000,
  'greenyellow': 0xFFADFF2F,
  'grey': 0xFF808080,
  'honeydew': 0xFFF0FFF0,
  'hotpink': 0xFFFF69B4,
  'indianred': 0xFFCD5C5C,
  'indigo': 0xFF4B0082,
  'ivory': 0xFFFFFFF0,
  'khaki': 0xFFF0E68C,
  'lavender': 0xFFE6E6FA,
  'lavenderblush': 0xFFFFF0F5,
  'lawngreen': 0xFF7CFC00,
  'lemonchiffon': 0xFFFFFACD,
  'lightblue': 0xFFADD8E6,
  'lightcoral': 0xFFF08080,
  'lightcyan': 0xFFE0FFFF,
  'lightgoldenrodyellow': 0xFFFAFAD2,
  'lightgray': 0xFFD3D3D3,
  'lightgreen': 0xFF90EE90,
  'lightgrey': 0xFFD3D3D3,
  'lightpink': 0xFFFFB6C1,
  'lightsalmon': 0xFFFFA07A,
  'lightseagreen': 0xFF20B2AA,
  'lightskyblue': 0xFF87CEFA,
  'lightslategray': 0xFF778899,
  'lightslategrey': 0xFF778899,
  'lightsteelblue': 0xFFB0C4DE,
  'lightyellow': 0xFFFFFFE0,
  'lime': 0xFF00FF00,
  'limegreen': 0xFF32CD32,
  'linen': 0xFFFAF0E6,
  'magenta': 0xFFFF00FF,
  'maroon': 0xFF800000,
  'mediumaquamarine': 0xFF66CDAA,
  'mediumblue': 0xFF0000CD,
  'mediumorchid': 0xFFBA55D3,
  'mediumpurple': 0xFF9370DB,
  'mediumseagreen': 0xFF3CB371,
  'mediumslateblue': 0xFF7B68EE,
  'mediumspringgreen': 0xFF00FA9A,
  'mediumturquoise': 0xFF48D1CC,
  'mediumvioletred': 0xFFC71585,
  'midnightblue': 0xFF191970,
  'mintcream': 0xFFF5FFFA,
  'mistyrose': 0xFFFFE4E1,
  'moccasin': 0xFFFFE4B5,
  'navajowhite': 0xFFFFDEAD,
  'navy': 0xFF000080,
  'oldlace': 0xFFFDF5E6,
  'olive': 0xFF808000,
  'olivedrab': 0xFF6B8E23,
  'orange': 0xFFFFA500,
  'orangered': 0xFFFF4500,
  'orchid': 0xFFDA70D6,
  'palegoldenrod': 0xFFEEE8AA,
  'palegreen': 0xFF98FB98,
  'paleturquoise': 0xFFAFEEEE,
  'palevioletred': 0xFFDB7093,
  'papayawhip': 0xFFFFEFD5,
  'peachpuff': 0xFFFFDAB9,
  'peru': 0xFFCD853F,
  'pink': 0xFFFFC0CB,
  'plum': 0xFFDDA0DD,
  'powderblue': 0xFFB0E0E6,
  'purple': 0xFF800080,
  'rebeccapurple': 0xFF663399,
  'red': 0xFFFF0000,
  'rosybrown': 0xFFBC8F8F,
  'royalblue': 0xFF4169E1,
  'saddlebrown': 0xFF8B4513,
  'salmon': 0xFFFA8072,
  'sandybrown': 0xFFF4A460,
  'seagreen': 0xFF2E8B57,
  'seashell': 0xFFFFF5EE,
  'sienna': 0xFFA0522D,
  'silver': 0xFFC0C0C0,
  'skyblue': 0xFF87CEEB,
  'slateblue': 0xFF6A5ACD,
  'slategray': 0xFF708090,
  'slategrey': 0xFF708090,
  'snow': 0xFFFFFAFA,
  'springgreen': 0xFF00FF7F,
  'steelblue': 0xFF4682B4,
  'tan': 0xFFD2B48C,
  'teal': 0xFF008080,
  'thistle': 0xFFD8BFD8,
  'tomato': 0xFFFF6347,
  'turquoise': 0xFF40E0D0,
  'violet': 0xFFEE82EE,
  'wheat': 0xFFF5DEB3,
  'white': 0xFFFFFFFF,
  'whitesmoke': 0xFFF5F5F5,
  'yellow': 0xFFFFFF00,
  'yellowgreen': 0xFF9ACD32,
};
