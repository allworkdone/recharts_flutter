// A CSS color string reader for the `fill` and `stroke` Recharts takes from
// data entries and `<Cell>`: #rgb, #rgba, #rrggbb, #rrggbbaa, rgb()/rgba() and
// hsl()/hsla() (comma or space separated, percentages, `/ alpha`), the CSS
// named colors, `transparent` and `none`.

import 'dart:math' as math;
import 'dart:ui' show Color;

/// The color a CSS string names; null for `none` and for anything that is not
/// a color (SVG then ignores the attribute).
Color? parseCssColor(String input) {
  final s = input.trim().toLowerCase();
  if (s == 'none') return null;
  if (s == 'transparent') return const Color(0x00000000);
  final named = _named[s];
  if (named != null) return Color(named);
  if (s.startsWith('#')) return _hex(s.substring(1));
  final m = RegExp(r'^(rgba?|hsla?)\(\s*([^)]*?)\s*\)$').firstMatch(s);
  if (m == null) return null;
  final parts = m[2]!.split(RegExp(r'\s*[,/]\s*|\s+'));
  if (parts.length < 3 || parts.length > 4) return null;
  final alpha = parts.length == 4 ? _alpha(parts[3]) : 1.0;
  if (alpha == null) return null;
  final a = (alpha.clamp(0.0, 1.0) * 255).round();
  if (m[1]!.startsWith('rgb')) {
    final c = [for (final p in parts.take(3)) _channel(p)];
    return c.contains(null) ? null : Color.fromARGB(a, c[0]!, c[1]!, c[2]!);
  }
  final h = _hue(parts[0]), sat = _percent(parts[1]), l = _percent(parts[2]);
  if (h == null || sat == null || l == null) return null;
  return _hsl(h, sat.clamp(0.0, 1.0), l.clamp(0.0, 1.0), a);
}

/// A data entry's `fill` or `stroke`: a [Color] as it is, a CSS string parsed;
/// `none` is a transparent color (nothing painted), other values are null.
Color? cssColorOf(Object? v) => v is Color ? v : (v is String ? (v.trim().toLowerCase() == 'none' ? const Color(0x00000000) : parseCssColor(v)) : null);

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
  final n = v.endsWith('%') ? _percent(v) : double.tryParse(v);
  if (n == null) return null;
  return (v.endsWith('%') ? n * 255 : n).clamp(0, 255).round();
}

/// '50%' as 0.5.
double? _percent(String v) {
  if (!v.endsWith('%')) return null;
  final n = double.tryParse(v.substring(0, v.length - 1));
  return n == null ? null : n / 100;
}

double? _alpha(String v) => v.endsWith('%') ? _percent(v) : double.tryParse(v);

/// Hue in degrees (deg, grad, rad, turn or unitless).
double? _hue(String v) {
  final m = RegExp(r'^([-+]?(?:\d+\.?\d*|\.\d+)(?:e[-+]?\d+)?)(deg|grad|rad|turn)?$').firstMatch(v);
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
  h = ((h % 360) + 360) % 360;
  double f(int n) {
    final k = (n + h / 30) % 12;
    return l - s * math.min(l, 1 - l) * math.max(-1, math.min(math.min(k - 3, 9 - k), 1));
  }

  int c(double v) => (v * 255).round();
  return Color.fromARGB(a, c(f(0)), c(f(8)), c(f(4)));
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
