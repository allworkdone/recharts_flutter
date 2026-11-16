// Port of src/component/Text.tsx (anchors, capHeight-based dy, getWordsByLines
// with width, breakAll, maxLines and scaleToFit, rotate(angle, x, y), textPath)
// and a TextPainter-based replacement for getStringSize in src/util/DOMUtils.ts.

import 'dart:math' as math;
import 'dart:ui' show PathMetric, PictureRecorder, Tangent;

import 'package:flutter/painting.dart';
import 'package:flutter/foundation.dart';

import '../components.dart';
import 'shapes.dart' show fillPaint, strokePaint;

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
  final words = breakAll ? _codePoints(text) : text.split(_breakingSpaces);
  return (
    [for (final w in words) (w, measureText(w, style, scaler).width)],
    breakAll ? 0.0 : measureText('\u00A0', style, scaler).width,
  );
}

/// `Array.from(text)`: code points, so a surrogate pair stays one character.
List<String> _codePoints(String text) => [for (final r in text.runes) String.fromCharCode(r)];

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
  if (maxLines == null || scaleToFit || original.isEmpty) return out(original);
  bool overflows(List<_Line> r) => r.length > maxLines || (width != null && _longest(r) > width);
  if (!overflows(original)) return out(original);

  final chars = _codePoints(text);
  (bool, List<_Line>) checkOverflow(int index) {
    // JS `text.slice(0, index)`: a negative index counts from the end.
    final end = index < 0 ? math.max(chars.length + index, 0) : math.min(index, chars.length);
    final r = _calculate(_wordWidths('${chars.sublist(0, end).join()}…', breakAll, style, scaler).$1, width, spaceWidth, false);
    return (overflows(r), r);
  }

  var start = 0, end = chars.length - 1, iterations = 0;
  List<_Line>? trimmed;
  while (start <= end && iterations <= chars.length - 1) {
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

/// Text.tsx's `resolveBackgroundPadding`: [TextBackground.padding] per direction.
({double x, double y}) resolveBackgroundPadding(Object? padding) {
  if (padding is num) return (x: padding.toDouble(), y: padding.toDouble());
  final p = padding is ({num? x, num? y}) ? padding : null;
  return (x: p?.x?.toDouble() ?? 4, y: p?.y?.toDouble() ?? 2);
}

/// Text.tsx's `getTextBackgroundRect`: [textBox] grown by the padding, or null for an empty box.
Rect? getTextBackgroundRect(Rect textBox, Object? padding) {
  if (textBox.width <= 0 || textBox.height <= 0) return null;
  final p = resolveBackgroundPadding(padding);
  return Rect.fromLTRB(textBox.left - p.x, textBox.top - p.y, textBox.right + p.x, textBox.bottom + p.y);
}

/// Text.tsx's `getTextPathBackgroundGeometry`: the stretch of the path the
/// background covers and its stroke width, or null when nothing is covered.
({double start, double length, double strokeWidth})? getTextPathBackgroundGeometry(
    ({double pathLength, double textLength, double textHeight, double startOffset}) metrics,
    Object? padding,
    TextAnchor textAnchor) {
  final (:pathLength, :textLength, :textHeight, :startOffset) = metrics;
  if (pathLength <= 0 || textLength <= 0 || textHeight <= 0) return null;
  final p = resolveBackgroundPadding(padding);
  final anchorOffset = switch (textAnchor) {
    TextAnchor.start => 0.0,
    TextAnchor.middle => textLength / 2,
    TextAnchor.end => textLength,
  };
  final start = (startOffset - anchorOffset - p.x).clamp(0.0, pathLength);
  final end = (startOffset - anchorOffset + textLength + p.x).clamp(0.0, pathLength);
  if (end <= start) return null;
  return (start: start, length: end - start, strokeWidth: textHeight + 2 * p.y);
}

/// `halo` of Text: `true` takes the defaults.
TextHalo? _halo(Object? halo) => switch (halo) {
      true => const TextHalo(),
      TextHalo h => h,
      _ => null,
    };

final _haloPaints = <(Color, double, StrokeJoin), Paint>{};

/// [style] stroking the letters as [halo] says; one Paint per look, so the painters stay cached.
TextStyle _haloStyle(TextStyle style, TextHalo halo) {
  final stroke = halo.stroke ?? const Color(0xFFFFFFFF);
  final key = (
    halo.strokeOpacity == null ? stroke : stroke.withValues(alpha: stroke.a * halo.strokeOpacity!),
    halo.strokeWidth ?? 3,
    halo.strokeLinejoin ?? StrokeJoin.round,
  );
  return style.copyWith(
      foreground: _haloPaints[key] ??= Paint()
        ..style = PaintingStyle.stroke
        ..color = key.$1
        ..strokeWidth = key.$2
        ..strokeJoin = key.$3);
}

/// Paints [text] at [at], over its halo first (`paint-order: stroke fill`).
void _paintRun(Canvas canvas, String text, Offset at, TextStyle style, TextStyle? haloStyle, TextScaler scaler) {
  if (haloStyle != null) textPainterFor(text, haloStyle, scaler).paint(canvas, at);
  textPainterFor(text, style, scaler).paint(canvas, at);
}

/// `background` of Text: `true` takes the defaults.
TextBackground? _background(Object? background) => switch (background) {
      true => const TextBackground(),
      TextBackground b => b,
      _ => null,
    };

Canvas? _labelBackgroundLayer;

/// Paints a label layer: what [paint] draws goes on top of [canvas], and the
/// backgrounds [paintSvgText] draws meanwhile go below all of it, as label
/// backgrounds render in their own zIndex layer under every label text
/// (src/zIndex/labelBackgroundZIndex.tsx). Text drawn outside a label layer
/// gets its background right before it.
void paintLabelLayer(Canvas canvas, void Function(Canvas canvas) paint) {
  final recorder = PictureRecorder();
  _labelBackgroundLayer = canvas;
  try {
    paint(Canvas(recorder));
  } finally {
    _labelBackgroundLayer = null;
  }
  final picture = recorder.endRecording();
  canvas.drawPicture(picture);
  picture.dispose();
}

/// Runs [draw] on the label background layer under [canvas]'s current transform, or on [canvas].
void _onBackgroundLayer(Canvas canvas, void Function(Canvas c) draw) {
  final layer = _labelBackgroundLayer;
  if (layer == null) return draw(canvas);
  layer.save();
  layer.transform(canvas.getTransform());
  draw(layer);
  layer.restore();
}

/// Blink's glyph cell above and below the baseline: the font's rounded ascent and descent.
({double ascent, double descent}) _cell(TextPainter tp) => (
      ascent: tp.computeDistanceToActualBaseline(TextBaseline.alphabetic).roundToDouble(),
      // An empty line has no line metrics.
      descent: (tp.computeLineMetrics().firstOrNull?.descent ?? 0).roundToDouble(),
    );

/// The background `<rect>`: fill, an optional stroke, rx (default 4) clamped like SVG's rx and ry.
void _paintBackgroundRect(Canvas canvas, Rect rect, TextBackground b) {
  final rx = b.rx ?? 4;
  final rrect = RRect.fromRectXY(rect, math.min(rx, rect.width / 2), math.min(rx, rect.height / 2));
  canvas.drawRRect(rrect, fillPaint(b.fill ?? const Color(0xFFFFFFFF), opacity: b.fillOpacity ?? 1));
  final strokeWidth = b.strokeWidth ?? 1;
  if (b.stroke != null && strokeWidth > 0) {
    canvas.drawRRect(rrect, strokePaint(b.stroke!, strokeWidth, opacity: b.strokeOpacity ?? 1));
  }
}

/// Draws `<Text x y textAnchor verticalAnchor angle width lineHeight>` with [style].
/// [lineHeight] is a number (px) or a CSS length, default '1em' as in Text.tsx.
/// Lines are measured with [measureStyle] (default [style]).
///
/// With [textPath] (`<Text textPath>`) the whole text runs along that path
/// instead: [startOffset] (px, or 'N%' of the path length) and [textAnchor]
/// place it, [centralBaseline] is `dominantBaseline="central"`, [angle] turns
/// it about the center of its box, and [boxes] collects the glyph cells' bounds.
/// x, y, width, breakAll, maxLines, lineHeight and verticalAnchor are ignored.
///
/// [background] (`true` or a [TextBackground]) draws a rounded rectangle
/// around the rendered lines, with the text's transform, or on a path a
/// round-capped stroke along the stretch the text covers, which [angle] does
/// not turn. Its unturned bounds go to [boxes] too. [halo] (`true` or a
/// [TextHalo]) strokes the letters under their fill, line by line or glyph
/// by glyph on a path.
// ponytail: scaleToFit is ignored on a path too; Text.tsx would still scale it.
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
  Path? textPath,
  Object? startOffset,
  bool centralBaseline = false,
  List<Rect>? boxes,
  Object? background,
  Object? halo,
}) {
  final h = _halo(halo);
  final haloStyle = h == null ? null : _haloStyle(style, h);
  if (textPath != null) {
    _paintTextOnPath(canvas, text, textPath, style, scaler, textAnchor, startOffset, centralBaseline, angle, boxes,
        _background(background), haloStyle);
    return;
  }
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
  // Painters are looked up again on use: a cache clear may dispose one held across lookups.
  final placed = [
    for (var i = 0; i < lines.length; i++)
      if (textPainterFor(lines[i], style, scaler).width case final width)
        (
          text: lines[i],
          width: width,
          baseline: y + startDy + i * lh,
          left: switch (textAnchor) {
            TextAnchor.start => x,
            TextAnchor.middle => x - width / 2,
            TextAnchor.end => x - width,
          },
        ),
  ];
  final bg = _background(background);
  if (bg != null) {
    // getBBox: the lines' glyph cells.
    final box = placed.map((l) {
      final cell = _cell(textPainterFor(l.text, style, scaler));
      return Rect.fromLTRB(l.left, l.baseline - cell.ascent, l.left + l.width, l.baseline + cell.descent);
    }).reduce((a, b) => a.expandToInclude(b));
    final rect = getTextBackgroundRect(box, bg.padding);
    if (rect != null) {
      _onBackgroundLayer(canvas, (c) => _paintBackgroundRect(c, rect, bg));
      if (angle == 0 && scale == null) boxes?.add(rect);
    }
  }
  for (final l in placed) {
    final ascent = textPainterFor(l.text, style, scaler).computeDistanceToActualBaseline(TextBaseline.alphabetic);
    _paintRun(canvas, l.text, Offset(l.left, l.baseline - ascent), style, haloStyle, scaler);
  }
  if (angle != 0 || scale != null) canvas.restore();
}

/// Text.tsx's `startOffset` of a textPath: px, or a percentage of [pathLength].
double _startOffsetPx(Object? startOffset, double pathLength) {
  if (startOffset is num) return startOffset.toDouble();
  if (startOffset is String) {
    final n = double.tryParse(RegExp(r'^\s*[-+]?(\d+\.?\d*|\.\d+)(e[-+]?\d+)?').stringMatch(startOffset) ?? '');
    if (n != null) return startOffset.trim().endsWith('%') ? n / 100 * pathLength : n;
  }
  return 0;
}

/// The point and tangent at [distance] along [metrics], walking subpaths in order.
Tangent? _tangentAt(List<PathMetric> metrics, double distance) {
  for (final m in metrics) {
    if (distance <= m.length) return m.getTangentForOffset(distance);
    distance -= m.length;
  }
  return null;
}

/// Bounds of [rect] turned by [radians] about the origin, then moved to [at].
Rect _turnedBounds(Rect rect, double radians, Offset at) {
  final c = math.cos(radians), s = math.sin(radians);
  final pts = [
    for (final p in [rect.topLeft, rect.topRight, rect.bottomRight, rect.bottomLeft])
      Offset(at.dx + p.dx * c - p.dy * s, at.dy + p.dx * s + p.dy * c),
  ];
  return Rect.fromLTRB(pts.map((p) => p.dx).reduce(math.min), pts.map((p) => p.dy).reduce(math.min),
      pts.map((p) => p.dx).reduce(math.max), pts.map((p) => p.dy).reduce(math.max));
}

/// `<text><textPath>` as Chrome lays it out: each glyph on the path at the
/// midpoint of its advance, turned to the tangent there; a glyph whose
/// midpoint falls off the path is not drawn.
void _paintTextOnPath(Canvas canvas, String text, Path path, TextStyle style, TextScaler scaler, TextAnchor textAnchor,
    Object? startOffset, bool centralBaseline, double angle, List<Rect>? boxes, TextBackground? bg, TextStyle? haloStyle) {
  final metrics = path.computeMetrics().toList();
  final pathLength = metrics.fold(0.0, (sum, m) => sum + m.length);
  if (!(pathLength > 0) || text.isEmpty) return;
  final textLength = textPainterFor(text, style, scaler).width;
  final offset = _startOffsetPx(startOffset, pathLength);
  final band = bg == null
      ? null
      : getTextPathBackgroundGeometry(
          (pathLength: pathLength, textLength: textLength, textHeight: scaler.scale(style.fontSize ?? 14), startOffset: offset),
          bg.padding,
          textAnchor);
  if (bg != null && band != null) {
    // A dash `length pathLength` offset by -start, which Skia restarts on every subpath.
    final stretch = Path();
    for (final m in metrics) {
      stretch.addPath(m.extractPath(band.start, band.start + band.length), Offset.zero);
    }
    final outline = math.max(0.0, bg.strokeWidth ?? 1);
    final hasOutline = bg.stroke != null && outline > 0;
    _onBackgroundLayer(canvas, (c) {
      if (hasOutline) {
        c.drawPath(stretch,
            strokePaint(bg.stroke!, band.strokeWidth + 2 * outline, opacity: bg.strokeOpacity ?? 1)..strokeCap = StrokeCap.round);
      }
      c.drawPath(stretch,
          strokePaint(bg.fill ?? const Color(0xFFFFFFFF), band.strokeWidth, opacity: bg.fillOpacity ?? 1)..strokeCap = StrokeCap.round);
    });
    boxes?.add(stretch.getBounds().inflate(band.strokeWidth / 2 + (hasOutline ? outline : 0)));
  }
  final start = offset -
      switch (textAnchor) {
        TextAnchor.start => 0,
        TextAnchor.middle => textLength / 2,
        TextAnchor.end => textLength,
      };
  final units = _codePoints(text);
  final first = textPainterFor(units.first, style, scaler);
  final ascent = first.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  // Blink's glyph cell: the rounded ascent and descent. dominant-baseline: central centers it on the
  // path, and Chrome draws the glyph from -floor(height / 2) (measured at 9-18px); the default puts the
  // baseline on the path.
  final cellAscent = ascent.roundToDouble();
  final cellHeight = cellAscent + first.computeLineMetrics().first.descent.roundToDouble();
  final cellTop = centralBaseline ? -cellHeight / 2 : -cellAscent;
  final paintTop = centralBaseline ? -(cellHeight / 2).floorToDouble() : -ascent;
  final glyphs = <({String unit, Offset at, double heading, Rect cell})>[];
  var prefix = '';
  var advance = 0.0;
  for (final unit in units) {
    prefix += unit;
    final end = textPainterFor(prefix, style, scaler).width;
    final mid = start + (advance + end) / 2;
    advance = end;
    if (mid < 0 || mid > pathLength) continue;
    final t = _tangentAt(metrics, mid);
    if (t == null) continue;
    final tp = textPainterFor(unit, style, scaler);
    glyphs.add((
      unit: unit,
      at: t.position,
      heading: math.atan2(t.vector.dy, t.vector.dx),
      cell: Rect.fromLTWH(-tp.width / 2, cellTop, tp.width, cellHeight),
    ));
  }
  if (glyphs.isEmpty) return;
  var cells = [for (final g in glyphs) _turnedBounds(g.cell, g.heading, g.at)];
  // CSS rotate(angle) with transform-box: fill-box and transform-origin: center.
  final pivot = cells.reduce((a, b) => a.expandToInclude(b)).center;
  final turn = angle * math.pi / 180;
  if (angle != 0) {
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(turn);
    canvas.translate(-pivot.dx, -pivot.dy);
    cells = [for (final r in cells) _turnedBounds(r.shift(-pivot), turn, pivot)];
  }
  for (final g in glyphs) {
    canvas.save();
    canvas.translate(g.at.dx, g.at.dy);
    canvas.rotate(g.heading);
    _paintRun(canvas, g.unit, Offset(g.cell.left, paintTop), style, haloStyle, scaler);
    canvas.restore();
  }
  if (angle != 0) canvas.restore();
  boxes?.addAll(cells);
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
