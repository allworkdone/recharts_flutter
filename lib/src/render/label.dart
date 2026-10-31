// Ports of src/component/Label.tsx and LabelList.tsx for cartesian charts:
// getCartesianPosition (src/cartesian/getCartesianPosition.tsx, rectangles
// only), parseLabel / LabelListFromLabelProp, BarLabelListProvider and
// LineLabelListProvider entries.

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
/// (Bar renders the prop's list first, Line last).
List<LabelList> seriesLabelLists(CartesianSeries series) {
  final (label, children) = switch (series) {
    Line l => (l.label, l.children),
    Bar b => (b.label, b.children),
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
/// LineLabelListProvider (zero-size boxes at the points, no parent).
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
