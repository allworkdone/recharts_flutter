// Port of src/component/Text.tsx (anchors, capHeight-based dy, getWordsByLines
// with width, breakAll, maxLines and scaleToFit, rotate(angle, x, y)) and a
// TextPainter-based replacement for getStringSize in src/util/DOMUtils.ts.

import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter/foundation.dart';

import '../components.dart';

/// Replaces TextPainter measurement, e.g. with `(_, _) => Size.zero` to mirror
/// jsdom, where Recharts' own specs measure every string as 0x0.
@visibleForTesting
Size Function(String text, TextStyle style)? debugTextMeasurerOverride;

final Map<(String, TextStyle, TextScaler), TextPainter> _cache = {};

TextPainter textPainterFor(String text, TextStyle style, TextScaler scaler) {
  final key = (text, style, scaler);
  final cached = _cache[key];
  if (cached != null) return cached;
  if (_cache.length > 2000) {
    for (final p in _cache.values) {
      p.dispose();
    }
    _cache.clear();
  }
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
  )..layout();
  return _cache[key] = tp;
}

/// Drops cached layouts, e.g. after fonts finish loading.
void clearTextCache() {
  for (final p in _cache.values) {
    p.dispose();
  }
  _cache.clear();
}

/// `getStringSize(text, style)`: the size of an inline span with `white-space: pre`.
Size measureText(String text, TextStyle style, [TextScaler scaler = TextScaler.noScaling]) {
  final override = debugTextMeasurerOverride;
  if (override != null) return override(text, style);
  final tp = textPainterFor(text, style, scaler);
  return Size(tp.width, tp.height);
}

final _breakingSpaces = RegExp('[ \f\n\r\t\v\u2028\u2029]+');

/// One line of `getWordsByLines`; [width] is null when nothing was measured.
typedef TextLineWords = ({List<String> words, double? width});

class _Line {
  _Line(this.words, this.width);
  final List<String> words;
  double width;
}

/// `calculateWordWidths`: [style] stands in for the measurement span's CSS
/// (the page font plus Text's `style` prop, not its `fontSize` attribute).
(List<(String, double)>, double) _wordWidths(String text, bool breakAll, TextStyle style, TextScaler scaler) {
  final words = breakAll ? text.split('') : text.split(_breakingSpaces);
  return (
    [for (final w in words) (w, measureText(w, style, scaler).width)],
    breakAll ? 0.0 : measureText('\u00A0', style, scaler).width,
  );
}

List<_Line> _calculate(List<(String, double)> words, double? lineWidth, double spaceWidth, bool scaleToFit) {
  final result = <_Line>[];
  for (final (word, width) in words) {
    final current = result.isEmpty ? null : result.last;
    if (current != null && (lineWidth == null || scaleToFit || current.width + width + spaceWidth < lineWidth)) {
      current.words.add(word);
      current.width += width + spaceWidth;
    } else {
      result.add(_Line([word], width));
    }
  }
  return result;
}

double _longest(List<_Line> lines) => lines.fold(lines.first.width, (a, b) => a > b.width ? a : b.width);

/// `getWordsByLines`: words split on breaking spaces (or per character with
/// [breakAll]), wrapped at [width], truncated with an ellipsis to [maxLines].
List<TextLineWords> getWordsByLines(
  String text, {
  double? width,
  bool scaleToFit = false,
  bool breakAll = false,
  int? maxLines,
  required TextStyle style,
  TextScaler scaler = TextScaler.noScaling,
}) {
  final hasWidth = width != null && width != 0 && !width.isNaN;
  if (!hasWidth && !scaleToFit) return [(words: text.split(_breakingSpaces), width: null)];
  final (words, spaceWidth) = _wordWidths(text, breakAll, style, scaler);
  List<TextLineWords> out(List<_Line> lines) => [for (final l in lines) (words: l.words, width: l.width)];
  final original = _calculate(words, width, spaceWidth, scaleToFit);
  if (maxLines == null || scaleToFit) return out(original);
  bool overflows(List<_Line> r) => r.length > maxLines || (width != null && _longest(r) > width);
  if (!overflows(original)) return out(original);

  (bool, List<_Line>) checkOverflow(int index) {
    // JS `text.slice(0, index)`: a negative index counts from the end.
    final end = index < 0 ? math.max(text.length + index, 0) : math.min(index, text.length);
    final r = _calculate(_wordWidths('${text.substring(0, end)}…', breakAll, style, scaler).$1, width, spaceWidth, false);
    return (overflows(r), r);
  }

  var start = 0, end = text.length - 1, iterations = 0;
  List<_Line>? trimmed;
  while (start <= end && iterations <= text.length - 1) {
    final middle = ((start + end) / 2).floor();
    final (prevOverflows, result) = checkOverflow(middle - 1);
    final (middleOverflows, _) = checkOverflow(middle);
    if (!prevOverflows && !middleOverflows) start = middle + 1;
    if (prevOverflows && middleOverflows) end = middle - 1;
    if (!prevOverflows && middleOverflows) {
      trimmed = result;
      break;
    }
    iterations++;
  }
  return out(trimmed ?? original);
}

const _absoluteUnitPx = {'px': 1.0, 'cm': 96 / 2.54, 'mm': 96 / 25.4, 'pt': 96 / 72, 'pc': 96 / 6, 'in': 96.0, 'Q': 96 / (2.54 * 40)};

/// Text's `lineHeight` (a number of px, or a CSS length such as '1.2em') in px;
/// null when it is not a length SVG accepts for `dy`.
// ponytail: '%', vh/vw, ex and ch lengths are not converted (null, dy 0); add them when a fixture needs one.
double? _lineHeightPx(Object lineHeight, double em) {
  if (lineHeight is num) return lineHeight.toDouble();
  final m = RegExp(r'^\s*(-?(?:\d+(?:\.\d+)?|\.\d+))([a-zA-Z%]*)\s*$').firstMatch('$lineHeight');
  if (m == null) return null;
  final n = double.parse(m[1]!);
  return switch (m[2]!) {
    '' => n,
    'em' => n * em,
    'rem' => n * 16,
    final u when _absoluteUnitPx.containsKey(u) => n * _absoluteUnitPx[u]!,
    _ => null,
  };
}

/// Draws `<Text x y textAnchor verticalAnchor angle width lineHeight>` with [style].
/// [lineHeight] is a number (px) or a CSS length, default '1em' as in Text.tsx.
/// Lines are measured with [measureStyle] (default [style]).
void paintSvgText(
  Canvas canvas,
  String text,
  double x,
  double y, {
  required TextStyle style,
  TextAnchor textAnchor = TextAnchor.start,
  TextVerticalAnchor verticalAnchor = TextVerticalAnchor.end,
  double angle = 0,
  double? width,
  bool breakAll = false,
  bool scaleToFit = false,
  int? maxLines,
  Object lineHeight = '1em',
  TextStyle? measureStyle,
  TextScaler scaler = TextScaler.noScaling,
}) {
  if (!x.isFinite || !y.isFinite) return;
  final wordLines = getWordsByLines(text,
      width: width,
      scaleToFit: scaleToFit,
      breakAll: breakAll,
      maxLines: maxLines,
      style: measureStyle ?? style,
      scaler: scaler);
  if (wordLines.isEmpty) return;
  final lines = [for (final l in wordLines) l.words.join(breakAll ? '' : ' ')];
  final em = scaler.scale(style.fontSize ?? 14);
  // capHeight '0.71em' (textDefaultProps). A lineHeight that is not a length leaves dy invalid: 0.
  final lh = _lineHeightPx(lineHeight, em) ?? 0;
  // `calc(k * -lineHeight + (capHeight / 2))` only reduces when lineHeight is in em: otherwise NaN, dy 0.
  final lhIsEm = lineHeight is String && lineHeight.trim().endsWith('em') && !lineHeight.trim().endsWith('rem');
  final double startDy = switch (verticalAnchor) {
    TextVerticalAnchor.start => 0.71 * em,
    TextVerticalAnchor.middle => lhIsEm ? (lines.length - 1) / 2 * -lh + 0.355 * em : 0,
    TextVerticalAnchor.end => (lines.length - 1) * -lh,
  };
  final firstWidth = wordLines.first.width;
  final scale = scaleToFit ? (width != null && firstWidth != null ? width / firstWidth : 1.0) : null;
  if (angle != 0 || scale != null) {
    canvas.save();
    // transform="scale(k) rotate(angle, x, y)"
    if (scale != null) canvas.scale(scale);
    canvas.translate(x, y);
    canvas.rotate(angle * math.pi / 180);
    canvas.translate(-x, -y);
  }
  for (var i = 0; i < lines.length; i++) {
    final tp = textPainterFor(lines[i], style, scaler);
    final baseline = y + startDy + i * lh;
    final ascent = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final left = switch (textAnchor) {
      TextAnchor.start => x,
      TextAnchor.middle => x - tp.width / 2,
      TextAnchor.end => x - tp.width,
    };
    tp.paint(canvas, Offset(left, baseline - ascent));
  }
  if (angle != 0 || scale != null) canvas.restore();
}

/// CSS `line-height: normal` as Blink computes it: rounded ascent + rounded
/// descent. Applied to HTML-side text (tooltip) so line boxes match Chrome.
TextStyle withCssNormalLineHeight(TextStyle style, TextScaler scaler) {
  if (style.height != null) return style;
  final tp = textPainterFor('x', style, scaler);
  final ascent = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  final lineHeight = (ascent + 0.5).floorToDouble() + (tp.height - ascent + 0.5).floorToDouble();
  final fontSize = scaler.scale(style.fontSize ?? 14);
  return style.copyWith(height: lineHeight / fontSize, leadingDistribution: TextLeadingDistribution.even);
}
