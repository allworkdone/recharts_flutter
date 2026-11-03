// Ports of src/cartesian/Funnel.tsx (computeFunnelTrapezoids,
// defaultFunnelAnimateItems), src/state/selectors/funnelSelectors.ts,
// src/shape/Trapezoid.tsx (getTrapezoidPath) and the funnel's tooltip entry
// (SetFunnelTooltipEntrySettings + combineTooltipPayload for the 'item' type).

import 'dart:math' as math;
import 'dart:ui';

import '../animation.dart';
import '../components.dart';
import '../util.dart';
import 'model.dart';
import '../css_color.dart';

/// `FunnelTrapezoidItem`.
class FunnelTrapezoid {
  const FunnelTrapezoid({
    required this.x,
    required this.y,
    required this.upperWidth,
    required this.lowerWidth,
    required this.height,
    required this.name,
    required this.val,
    required this.index,
    required this.tooltipPosition,
    required this.labelViewBox,
    required this.payload,
    required this.fill,
    required this.fillOpacity,
    required this.stroke,
    required this.strokeWidth,
    required this.parentViewBox,
  });
  final double x, y, upperWidth, lowerWidth, height;
  final String name;
  final double val;
  final int index;
  final Offset tooltipPosition;

  /// `labelViewBox` as a box (`width = max(upper, lower)`); the label position
  /// reads the widths from [upperWidth] / [lowerWidth] of the entry before animation.
  final Rect labelViewBox;
  final Object? payload;
  final Color fill;
  final double? fillOpacity;
  final Color? stroke;
  final double? strokeWidth;

  /// The plot area.
  final Rect parentViewBox;

  FunnelTrapezoid copyWith({double? x, double? y, double? upperWidth, double? lowerWidth, double? height}) =>
      FunnelTrapezoid(
        x: x ?? this.x,
        y: y ?? this.y,
        upperWidth: upperWidth ?? this.upperWidth,
        lowerWidth: lowerWidth ?? this.lowerWidth,
        height: height ?? this.height,
        name: name,
        val: val,
        index: index,
        tooltipPosition: tooltipPosition,
        labelViewBox: labelViewBox,
        payload: payload,
        fill: fill,
        fillOpacity: fillOpacity,
        stroke: stroke,
        strokeWidth: strokeWidth,
        parentViewBox: parentViewBox,
      );

  @override
  bool operator ==(Object other) =>
      other is FunnelTrapezoid &&
      other.x == x &&
      other.y == y &&
      other.upperWidth == upperWidth &&
      other.lowerWidth == lowerWidth &&
      other.height == height &&
      other.name == name &&
      other.val == val &&
      other.fill == fill &&
      other.stroke == stroke &&
      identical(other.payload, payload);
  @override
  int get hashCode => Object.hash(x, y, upperWidth, lowerWidth, height, name);
}

/// The corners `getTrapezoidPath` visits (each rounded like `roundTemplateLiteral`).
List<Offset> trapezoidPoints(double x, double y, double upperWidth, double lowerWidth, double height) {
  final widthGap = upperWidth - lowerWidth;
  Offset o(double px, double py) => Offset(round4(px), round4(py));
  return [
    o(x, y),
    o(x + upperWidth, y),
    o(x + upperWidth - widthGap / 2, y + height),
    o(x + upperWidth - widthGap / 2 - lowerWidth, y + height),
    o(x, y),
  ];
}

/// `getTrapezoidPath`.
Path trapezoidPath(double x, double y, double upperWidth, double lowerWidth, double height) {
  final p = trapezoidPoints(x, y, upperWidth, lowerWidth, height);
  final path = Path()..moveTo(p[0].dx, p[0].dy);
  for (final o in p.skip(1)) {
    path.lineTo(o.dx, o.dy);
  }
  return path..close();
}

/// Trapezoid.tsx renders nothing for non-numbers, no width at both ends or no height.
bool trapezoidVisible(FunnelTrapezoid t) =>
    t.x.isFinite &&
    t.y.isFinite &&
    t.upperWidth.isFinite &&
    t.lowerWidth.isFinite &&
    t.height.isFinite &&
    !(t.upperWidth == 0 && t.lowerWidth == 0) &&
    t.height != 0;

class FunnelModel {
  FunnelModel(this.id, this.settings, this.trapezoids);
  final String id;
  final Funnel settings;
  final List<FunnelTrapezoid> trapezoids;
}

/// `selectFunnelTrapezoids` + `computeFunnelTrapezoids`.
List<FunnelTrapezoid> computeFunnelTrapezoids(Funnel f, List<Object?> chartData, ChartOffset offset) {
  final source = f.data != null && f.data!.isNotEmpty ? f.data! : chartData;
  if (source.isEmpty) return const [];
  final cells = f.children.whereType<Cell>().toList();
  final displayed = source;
  final len = displayed.length;

  // The merged entry: `{...presentationProps, ...entry, ...cell.props}`.
  Color? colorOf(String key, int i, Color? Function(Cell c) fromCell, Color? fallback) {
    final c = i < cells.length ? fromCell(cells[i]) : null;
    if (c != null) return c;
    final e = displayed[i];
    final v = e is Map ? e[key] : null;
    return (key == 'stroke' ? cssStrokeOf(v) : cssFillOf(v)) ?? fallback;
  }

  double? numberOf(String key, int i, double? Function(Cell c) fromCell, double? fallback) {
    final c = i < cells.length ? fromCell(cells[i]) : null;
    if (c != null) return c;
    final e = displayed[i];
    final v = e is Map ? e[key] : null;
    return v is num ? v.toDouble() : fallback;
  }

  final realWidth = getPercentValue(f.width, offset.width, offset.width);
  final realHeight = offset.height, offsetX = offset.left, offsetY = offset.top;
  double numeric(Object? v) => v is num ? v.toDouble() : 0;
  final values = [for (final e in displayed) numeric(getValueByDataKey(e, f.dataKey, 0))];
  final maxValue = values.reduce(math.max);
  final rowHeight = realHeight / len;
  final parentViewBox = offset.plotArea;

  var out = <FunnelTrapezoid>[];
  for (var i = 0; i < len; i++) {
    final entry = displayed[i];
    final rawVal = getValueByDataKey(entry, f.dataKey, 0);
    final name = jsString(getValueByDataKey(entry, f.nameKey, i));
    var val = rawVal is num ? rawVal.toDouble() : double.nan;
    double? nextVal;
    if (i != len - 1) {
      final next = getValueByDataKey(displayed[i + 1], f.dataKey, 0);
      if (next is num) {
        nextVal = next.toDouble();
      } else if (next is List) {
        if (next.isNotEmpty && next[0] is num) val = (next[0] as num).toDouble();
        if (next.length > 1 && next[1] is num) nextVal = (next[1] as num).toDouble();
      }
    } else if (rawVal is List && rawVal.length == 2) {
      if (rawVal[0] is num) val = (rawVal[0] as num).toDouble();
      if (rawVal[1] is num) nextVal = (rawVal[1] as num).toDouble();
    } else if (f.lastShapeType == LastShapeType.rectangle) {
      nextVal = val;
    } else {
      nextVal = 0;
    }
    final x = maxValue == 0 ? offsetX : ((maxValue - val) * realWidth) / (2 * maxValue) + offsetX;
    final y = rowHeight * i + offsetY;
    final upperWidth = maxValue == 0 ? 0.0 : (val / maxValue) * realWidth;
    final lowerWidth = maxValue == 0 ? 0.0 : (nextVal == null ? double.nan : nextVal / maxValue * realWidth);
    final box = Rect.fromLTWH(x, y, math.max(upperWidth, lowerWidth), rowHeight);
    out.add(FunnelTrapezoid(
      x: x,
      y: y,
      upperWidth: upperWidth,
      lowerWidth: lowerWidth,
      height: rowHeight,
      name: name,
      val: val,
      index: i,
      tooltipPosition: Offset(x + upperWidth / 2, y + rowHeight / 2),
      labelViewBox: box,
      payload: entry,
      fill: colorOf('fill', i, (c) => c.fill, f.fill)!,
      fillOpacity: numberOf('fillOpacity', i, (c) => c.fillOpacity, f.fillOpacity),
      stroke: colorOf('stroke', i, (c) => c.stroke, f.stroke),
      strokeWidth: numberOf('strokeWidth', i, (c) => c.strokeWidth, f.strokeWidth),
      parentViewBox: parentViewBox,
    ));
  }

  if (f.reversed) {
    out = [
      for (final (index, e) in out.indexed)
        e._reversed(
          x: e.x - (e.lowerWidth - e.upperWidth) / 2,
          y: e.y - index * rowHeight + (len - 1 - index) * rowHeight,
          upperWidth: e.lowerWidth,
          lowerWidth: e.upperWidth,
          rowHeight: rowHeight,
        ),
    ];
  }
  return out;
}

extension on FunnelTrapezoid {
  FunnelTrapezoid _reversed(
      {required double x,
      required double y,
      required double upperWidth,
      required double lowerWidth,
      required double rowHeight}) {
    return FunnelTrapezoid(
      x: x,
      y: y,
      upperWidth: upperWidth,
      lowerWidth: lowerWidth,
      height: rowHeight,
      name: name,
      val: val,
      index: index,
      tooltipPosition: Offset(tooltipPosition.dx, y + rowHeight / 2),
      labelViewBox: Rect.fromLTWH(x, y, math.max(lowerWidth, upperWidth), rowHeight),
      payload: payload,
      fill: fill,
      fillOpacity: fillOpacity,
      stroke: stroke,
      strokeWidth: strokeWidth,
      parentViewBox: parentViewBox,
    );
  }
}

/// `defaultFunnelAnimateItems`.
List<FunnelTrapezoid> interpolateFunnelTrapezoids(List<AnimationItem<FunnelTrapezoid>>? items, double t) {
  if (items == null) return const [];
  if (t == 1) {
    return [
      for (final i in items)
        if (i is Matched<FunnelTrapezoid>) i.next else if (i is Added<FunnelTrapezoid>) i.next,
    ];
  }
  return [
    for (final i in items)
      switch (i) {
        Matched(:final prev, :final next) => next.copyWith(
            x: interpolate(prev.x, next.x, t),
            y: interpolate(prev.y, next.y, t),
            upperWidth: interpolate(prev.upperWidth, next.upperWidth, t),
            lowerWidth: interpolate(prev.lowerWidth, next.lowerWidth, t),
            height: interpolate(prev.height, next.height, t),
          ),
        Added(:final next) => next.copyWith(
            x: interpolate(next.x + next.upperWidth / 2, next.x, t),
            y: interpolate(next.y + next.height / 2, next.y, t),
            upperWidth: interpolate(0, next.upperWidth, t),
            lowerWidth: interpolate(0, next.lowerWidth, t),
            height: interpolate(0, next.height, t),
          ),
        Removed() => null,
      },
  ].nonNulls.toList();
}

/// The tooltip row of funnel [f] at data [index] (the 'item' event type reads by index).
TooltipPayloadEntry? funnelTooltipEntry(FunnelModel f, List<Object?> chartData, int index) {
  final s = f.settings;
  final data = s.data != null && s.data!.isNotEmpty ? s.data! : chartData;
  final payload = index >= 0 && index < data.length ? data[index] : null;
  final nameValue = getValueByDataKey(payload, s.nameKey);
  return TooltipPayloadEntry(
    dataKey: s.dataKey,
    name: nameValue != null ? jsString(nameValue) : (s.name != null ? jsString(s.name) : null),
    value: getValueByDataKey(payload, s.dataKey),
    payload: payload,
    color: s.fill,
    fill: s.fill,
    stroke: s.stroke,
    unit: '',
    hide: s.hide,
    type: s.tooltipType,
    formatter: s.formatter,
  );
}
