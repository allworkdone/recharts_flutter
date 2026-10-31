// Port of src/component/Text.tsx (anchors, capHeight-based dy, word wrapping
// by width, rotate(angle, x, y)) and a TextPainter-based replacement for
// getStringSize in src/util/DOMUtils.ts.

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

final _breakingSpaces = RegExp(r'[ \f\n\r\t\v  ]+');

/// `getWordsByLines` without `scaleToFit`/`maxLines`.
List<String> wordsByLines(String text, double? width, TextStyle style, TextScaler scaler) {
  if (width == null || width == 0) return [text];
  final words = text.split(_breakingSpaces);
  final spaceWidth = measureText(' ', style, scaler).width;
  final lines = <({List<String> words, double width})>[];
  for (final word in words) {
    final w = measureText(word, style, scaler).width;
    if (lines.isNotEmpty && lines.last.width + w + spaceWidth < width) {
      final last = lines.removeLast();
      lines.add((words: [...last.words, word], width: last.width + w + spaceWidth));
    } else {
      lines.add((words: [word], width: w));
    }
  }
  return [for (final l in lines) l.words.join(' ')];
}

/// Draws `<Text x y textAnchor verticalAnchor angle width>` with [style].
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
  TextScaler scaler = TextScaler.noScaling,
}) {
  if (!x.isFinite || !y.isFinite) return;
  final lines = wordsByLines(text, width, style, scaler);
  final em = scaler.scale(style.fontSize ?? 14);
  // capHeight '0.71em', lineHeight '1em' (textDefaultProps)
  final double startDy = switch (verticalAnchor) {
    TextVerticalAnchor.start => 0.71 * em,
    TextVerticalAnchor.middle => (lines.length - 1) / 2 * -em + 0.355 * em,
    TextVerticalAnchor.end => (lines.length - 1) * -em,
  };
  if (angle != 0) {
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(angle * math.pi / 180);
    canvas.translate(-x, -y);
  }
  for (var i = 0; i < lines.length; i++) {
    final tp = textPainterFor(lines[i], style, scaler);
    final baseline = y + startDy + i * em;
    final ascent = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final left = switch (textAnchor) {
      TextAnchor.start => x,
      TextAnchor.middle => x - tp.width / 2,
      TextAnchor.end => x - tp.width,
    };
    tp.paint(canvas, Offset(left, baseline - ascent));
  }
  if (angle != 0) canvas.restore();
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
