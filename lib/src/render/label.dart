// Ports of src/component/Label.tsx and LabelList.tsx for cartesian charts:
// getCartesianPosition (src/cartesian/getCartesianPosition.tsx, rectangles
// only), parseLabel / LabelListFromLabelProp, BarLabelListProvider,
// LineLabelListProvider and AreaLabelListProvider entries; plus getCalculatedYAxisWidth
// (src/util/YAxisUtils.tsx) and the updateYAxisWidth reducer
// (src/state/cartesianAxisSlice.ts) behind `YAxis(width: 'auto')`.

import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../components.dart';
import '../engine/model.dart';
import '../util.dart';
import 'svg_text.dart';

/// `CalculatedCartesianPosition`.
typedef CartesianLabelPosition = ({
  double x,
  double y,
  TextAnchor horizontalAnchor,
  TextVerticalAnchor verticalAnchor,
  double? width,
  double? height,
});

/// `getCartesianPosition` for a rectangle [viewBox] (width and height may be
/// negative). With [clamp] and a [parentViewBox], the size the text may wrap
/// in comes back as `width` / `height`.
CartesianLabelPosition getCartesianPosition(Rect viewBox, LabelPosition position, double offset,
    {Rect? parentViewBox, bool clamp = false}) {
  final x = viewBox.left, y = viewBox.top, width = viewBox.width, height = viewBox.height;
  final verticalSign = height >= 0 ? 1 : -1;
  final verticalOffset = verticalSign * offset;
  final verticalEnd = verticalSign > 0 ? TextVerticalAnchor.end : TextVerticalAnchor.start;
  final verticalStart = verticalSign > 0 ? TextVerticalAnchor.start : TextVerticalAnchor.end;
  final horizontalSign = width >= 0 ? 1 : -1;
  final horizontalOffset = horizontalSign * offset;
  final horizontalEnd = horizontalSign > 0 ? TextAnchor.end : TextAnchor.start;
  final horizontalStart = horizontalSign > 0 ? TextAnchor.start : TextAnchor.end;
  final p = clamp ? parentViewBox : null;

  CartesianLabelPosition at(double px, double py, TextAnchor h, TextVerticalAnchor v, {double? w, double? hh}) =>
      (x: px, y: py, horizontalAnchor: h, verticalAnchor: v, width: w, height: hh);

  switch (position) {
    case LabelPosition.top:
      return at(x + width / 2, y - verticalOffset, TextAnchor.middle, verticalEnd,
          w: p == null ? null : width, hh: p == null ? null : math.max(y - p.top, 0));
    case LabelPosition.bottom:
      return at(x + width / 2, y + height + verticalOffset, TextAnchor.middle, verticalStart,
          w: p == null ? null : width, hh: p == null ? null : math.max(p.top + p.height - (y + height), 0));
    case LabelPosition.left:
      final lx = x - horizontalOffset;
      return at(lx, y + height / 2, horizontalEnd, TextVerticalAnchor.middle,
          w: p == null ? null : math.max(lx - p.left, 0), hh: p == null ? null : height);
    case LabelPosition.right:
      final rx = x + width + horizontalOffset;
      return at(rx, y + height / 2, horizontalStart, TextVerticalAnchor.middle,
          w: p == null ? null : math.max(p.left + p.width - rx, 0), hh: p == null ? null : height);
    default:
  }
  final w = p == null ? null : width, h = p == null ? null : height;
  return switch (position) {
    LabelPosition.insideLeft => at(x + horizontalOffset, y + height / 2, horizontalStart, TextVerticalAnchor.middle, w: w, hh: h),
    LabelPosition.insideRight => at(x + width - horizontalOffset, y + height / 2, horizontalEnd, TextVerticalAnchor.middle, w: w, hh: h),
    LabelPosition.insideTop => at(x + width / 2, y + verticalOffset, TextAnchor.middle, verticalStart, w: w, hh: h),
    LabelPosition.insideBottom => at(x + width / 2, y + height - verticalOffset, TextAnchor.middle, verticalEnd, w: w, hh: h),
    LabelPosition.insideTopLeft => at(x + horizontalOffset, y + verticalOffset, horizontalStart, verticalStart, w: w, hh: h),
    LabelPosition.insideTopRight => at(x + width - horizontalOffset, y + verticalOffset, horizontalEnd, verticalStart, w: w, hh: h),
    LabelPosition.insideBottomLeft => at(x + horizontalOffset, y + height - verticalOffset, horizontalStart, verticalEnd, w: w, hh: h),
    LabelPosition.insideBottomRight => at(x + width - horizontalOffset, y + height - verticalOffset, horizontalEnd, verticalEnd, w: w, hh: h),
    _ => at(x + width / 2, y + height / 2, TextAnchor.middle, TextVerticalAnchor.middle, w: w, hh: h),
  };
}

/// `parseLabel`: the `label` prop of an axis or ReferenceLine.
Label? parseLabel(Object? label) => switch (label) {
      Label l => l,
      String() || num() => Label(value: label),
      LabelPainter p => Label(content: p),
      _ => null,
    };

/// The label text style: inherited font, `fill` (Text's default `#808080`), `fontSize`.
TextStyle labelTextStyle(Label label, TextStyle base) =>
    base.copyWith(color: label.fill ?? const Color(0xFF808080), fontSize: label.fontSize);

/// What `<Label>` hands to `<Text>`, or null when it renders no text.
typedef LabelLayout = ({
  String text,
  double x,
  double y,
  TextAnchor textAnchor,
  TextVerticalAnchor verticalAnchor,
  double? width,
});

LabelLayout? layoutLabel(Label label, Rect viewBox, {Rect? parentViewBox}) {
  if (label.value == null) return null;
  final value = label.formatter == null ? label.value : label.formatter!(label.value);
  if (value == null) return null;
  final pos = getCartesianPosition(viewBox, label.position, label.offset, parentViewBox: parentViewBox, clamp: true);
  return (
    text: jsString(value),
    x: pos.x,
    y: pos.y,
    textAnchor: label.textAnchor ?? pos.horizontalAnchor,
    verticalAnchor: pos.verticalAnchor,
    width: pos.width ?? label.width,
  );
}

/// Draws [label] in [viewBox] (`<Label viewBox>`); [baseStyle] is the inherited text style.
void paintLabel(Canvas canvas, Label? label, Rect viewBox,
    {Rect? parentViewBox, int? index, required TextStyle baseStyle, required TextScaler scaler}) {
  if (label == null) return;
  final style = labelTextStyle(label, baseStyle);
  if (label.content != null) {
    final pos = getCartesianPosition(viewBox, label.position, label.offset, parentViewBox: parentViewBox, clamp: true);
    label.content!(
      canvas,
      LabelProps(
        x: pos.x,
        y: pos.y,
        viewBox: viewBox,
        value: label.value,
        position: label.position,
        offset: label.offset,
        angle: label.angle,
        style: style,
        index: index,
      ),
    );
    return;
  }
  final l = layoutLabel(label, viewBox, parentViewBox: parentViewBox);
  if (l == null) return;
  paintSvgText(canvas, l.text, l.x, l.y,
      style: style,
      textAnchor: l.textAnchor,
      verticalAnchor: l.verticalAnchor,
      angle: label.angle,
      width: l.width,
      breakAll: label.textBreakAll,
      // getStringSize measures in the page font, not the fontSize attribute.
      measureStyle: baseStyle,
      scaler: scaler);
}

// ---------------------------------------------------------------- LabelList

/// `LabelListFromLabelProp` followed by `LabelList` children, in render order
/// (Bar renders the prop's list first, Line and Area last).
List<LabelList> seriesLabelLists(CartesianSeries series) {
  final (label, children) = switch (series) {
    Line l => (l.label, l.children),
    Bar b => (b.label, b.children),
    Area a => (a.label, a.children),
    _ => (false, const <RechartsElement>[]),
  };
  final fromProp = switch (label) {
    true => const LabelList(),
    LabelList l => l,
    LabelPainter p => LabelList(content: p),
    _ => null,
  };
  final lists = children.whereType<LabelList>();
  return series is Bar ? [?fromProp, ...lists] : [...lists, ?fromProp];
}

/// Entries of BarLabelListProvider (final rectangles, chart box as parent) or
/// Line/AreaLabelListProvider (zero-size boxes at the points, no parent; an
/// area point's value is its `[base, value]` pair).
List<LabelListEntry> labelListEntries(SeriesModel s, Size chartSize) => s.rects != null
    ? [
        for (final r in s.rects!)
          LabelListEntry(
            value: r.value,
            payload: r.payload,
            viewBox: Rect.fromLTWH(r.x, r.y, r.width, r.height),
            fill: r.cell?.fill,
            parentViewBox: Offset.zero & chartSize,
          ),
      ]
    : [
        for (final p in s.points ?? const <LinePoint>[])
          LabelListEntry(value: p.value, payload: p.payload, viewBox: Rect.fromLTWH(p.x ?? 0, p.y ?? 0, 0, 0)),
      ];

/// The `<Label>` LabelList renders for [entry]: the entry's svg props (its box
/// `width`, `fill`) under the list's props.
Label labelOfEntry(LabelList list, LabelListEntry entry, int index) {
  Object? value;
  if (list.dataKey != null) {
    value = getValueByDataKey(entry.payload, list.dataKey);
  } else if (list.valueAccessor != null) {
    value = list.valueAccessor!(entry, index);
  } else {
    // defaultAccessor
    final v = entry.value is List ? ((entry.value as List).isEmpty ? null : (entry.value as List).last) : entry.value;
    value = v is String || v is num || v is bool ? v : null;
  }
  return Label(
    value: value,
    position: list.position,
    offset: list.offset,
    angle: list.angle,
    fill: list.fill ?? entry.fill,
    fontSize: list.fontSize,
    width: entry.viewBox.width,
    textBreakAll: list.textBreakAll,
    formatter: list.formatter,
    content: list.content,
  );
}

void paintLabelLists(Canvas canvas, SeriesModel s, Size chartSize,
    {required TextStyle baseStyle, required TextScaler scaler}) {
  final lists = seriesLabelLists(s.item.element);
  if (lists.isEmpty) return;
  final entries = labelListEntries(s, chartSize);
  for (final list in lists) {
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      paintLabel(canvas, labelOfEntry(list, e, i), e.viewBox,
          parentViewBox: e.parentViewBox, index: i, baseStyle: baseStyle, scaler: scaler);
    }
  }
}

// ---------------------------------------------------------------- YAxis width 'auto'

/// Blink's SVG text line box: rounded ascent + rounded descent.
double _lineBoxHeight(TextStyle style, TextScaler scaler) {
  final tp = textPainterFor('x', style, scaler);
  final ascent = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  return (ascent + 0.5).floorToDouble() + (tp.height - ascent + 0.5).floorToDouble();
}

/// `getBoundingClientRect().width` of a `<text>`: its bbox (advance width by
/// line boxes 1em apart) rotated by [angle].
double _clientWidth(List<String> lines, TextStyle style, TextScaler scaler, double angle) {
  var w = 0.0;
  for (final l in lines) {
    w = math.max(w, measureText(l, style, scaler).width);
  }
  if (angle == 0) return w;
  final h = (lines.length - 1) * scaler.scale(style.fontSize ?? 14) + _lineBoxHeight(style, scaler);
  final a = angle * math.pi / 180;
  return (w * math.cos(a)).abs() + (h * math.sin(a)).abs();
}

/// `getCalculatedYAxisWidth`: widest rendered tick label + tickSize +
/// tickMargin, plus the label and a 5px gap when a label renders, rounded.
double getCalculatedYAxisWidth(AxisLayout a,
    {required TextStyle tickStyle, required TextStyle baseStyle, required TextScaler scaler}) {
  final s = a.settings;
  var maxTickWidth = 0.0;
  // Only the default tick (`.recharts-cartesian-axis-tick-value`) is measured.
  if (s.tick != false && s.tick is! TickPainter) {
    for (var i = 0; i < a.ticks.length; i++) {
      final t = a.ticks[i];
      final text = '${s.tickFormatter != null ? s.tickFormatter!(t.value, i) : jsString(t.value)}${s.unit ?? ''}';
      final lines = [for (final l in getWordsByLines(text, style: tickStyle, scaler: scaler)) l.words.join(' ')];
      maxTickWidth = math.max(maxTickWidth, _clientWidth(lines, tickStyle, scaler, s.angle));
    }
  }
  var labelWidth = 0.0;
  var hasLabel = false;
  final label = parseLabel(s.label);
  final l = label == null || label.content != null ? null : layoutLabel(label, a.rect);
  if (l != null) {
    hasLabel = true;
    final lines = [
      for (final w in getWordsByLines(l.text, width: l.width, breakAll: label!.textBreakAll, style: baseStyle, scaler: scaler))
        w.words.join(label.textBreakAll ? '' : ' '),
    ];
    labelWidth = _clientWidth(lines, labelTextStyle(label, baseStyle), scaler, label.angle);
  }
  return jsRound(maxTickWidth + s.tickSize + s.tickMargin + labelWidth + (hasLabel ? 5 : 0));
}

/// A `YAxis(width: 'auto')` entry of the axis state: the measured width and
/// `widthHistory`, reset whenever the axis settings are replaced.
class AutoYAxisWidth {
  AutoYAxisWidth(this.settings);
  final YAxis settings;
  double? width;
  List<double> history = const [];

  /// `updateYAxisWidth`: ignores a <= 1px A -> B -> A -> B oscillation.
  /// Returns whether the width changed.
  bool update(double next) {
    final h = history;
    if (h.length == 3 && h[0] == h[2] && next == h[1] && next != width && (next - h[0]).abs() <= 1) return false;
    history = [...h, next].skip(math.max(0, h.length + 1 - 3)).toList();
    final changed = next != width;
    width = next;
    return changed;
  }
}
