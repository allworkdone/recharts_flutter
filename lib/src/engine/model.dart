// The cartesian chart "store": everything Recharts derives in its selectors,
// computed eagerly for one frame. Ports:
//   src/state/selectors/selectChartOffsetInternal.ts (+ appendOffsetOfLegend, brush height)
//   src/state/selectors/brushSelectors.ts, dataSelectors.ts (Brush data slice; panorama)
//   src/state/selectors/axisSelectors.ts (axis positions, ranges, padding)
//   src/state/selectors/barSelectors.ts, combiners/combineBarSizeList.ts,
//     combineAllBarPositions.ts, combineBarPosition.ts; computeBarRectangles (Bar.tsx)
//   src/state/selectors/lineSelectors.ts; computeLinePoints (Line.tsx)
//   CartesianGrid.tsx coordinate generators; ReferenceLine.tsx getEndPoints
//   src/state/selectors/tooltipSelectors.ts, selectors.ts (combineActiveProps),
//     src/util/getActiveCoordinate.ts, combineActiveTooltipIndex.ts,
//     combineTooltipPayload.ts, src/util/cursor/getCursorRectangle.ts, getCursorPoints.ts

import 'dart:math' as math;
import 'dart:ui';

import '../components.dart';
import '../core/curve.dart';
import '../core/scale.dart';
import '../util.dart';
import 'axis.dart';
import 'get_ticks.dart';

class ChartOffset {
  const ChartOffset({
    required this.top,
    required this.right,
    required this.bottom,
    required this.left,
    required this.width,
    required this.height,
  });
  final double top, right, bottom, left, width, height;
  Rect get plotArea => Rect.fromLTWH(left, top, width, height);
}

/// A rendered axis (`XAxisImpl` / `YAxisImpl` -> CartesianAxis props).
class AxisLayout {
  AxisLayout(this.runtime, this.rect, this.ticks);
  final AxisRuntime runtime;

  /// `{x, y, width, height}` passed to CartesianAxis.
  final Rect rect;

  /// Ticks after `getTicks` (only the visible ones, with `tickCoord`).
  final List<TickItem> ticks;
  CartesianAxisElement get settings => runtime.settings;
}

/// `BarRectangleItem`.
class BarRect {
  BarRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.value,
    required this.payload,
    required this.background,
    required this.stackedBarStart,
    required this.originalDataIndex,
    this.cell,
  });
  final double x, y, width, height;
  final Object? value;
  final Object? payload;
  final Rect? background;
  final double stackedBarStart;
  final int originalDataIndex;
  final Cell? cell;

  Offset get tooltipPosition => Offset(x + width / 2, y + height / 2);

  BarRect copyWith({double? x, double? y, double? width, double? height}) => BarRect(
        x: x ?? this.x,
        y: y ?? this.y,
        width: width ?? this.width,
        height: height ?? this.height,
        value: value,
        payload: payload,
        background: background,
        stackedBarStart: stackedBarStart,
        originalDataIndex: originalDataIndex,
        cell: cell,
      );

  @override
  bool operator ==(Object other) =>
      other is BarRect &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height &&
      identical(other.payload, payload) &&
      other.cell == cell;
  @override
  int get hashCode => Object.hash(x, y, width, height);
}

/// `LinePointItem`.
class LinePoint {
  const LinePoint(this.x, this.y, this.value, this.payload);
  final double? x, y;
  final Object? value;
  final Object? payload;

  @override
  bool operator ==(Object other) =>
      other is LinePoint && other.x == x && other.y == y && identical(other.payload, payload);
  @override
  int get hashCode => Object.hash(x, y);
}

class SeriesModel {
  SeriesModel(this.item, {this.rects, this.points});
  final GraphicalItem item;
  final List<BarRect>? rects;
  final List<LinePoint>? points;
}

class GridModel {
  GridModel(this.settings, this.rect, this.horizontalPoints, this.verticalPoints);
  final CartesianGrid settings;
  final Rect rect;
  final List<double> horizontalPoints;
  final List<double> verticalPoints;
}

class ReferenceLineModel {
  ReferenceLineModel(this.settings, this.p1, this.p2);
  final ReferenceLine settings;
  final Offset p1, p2;
}

class CartesianModel {
  CartesianModel({
    required this.size,
    required this.layout,
    required this.chartName,
    required this.chartData,
    required this.offset,
    required this.axes,
    required this.series,
    required this.grid,
    required this.referenceLines,
    required this.tooltipAxis,
    required this.tooltipTicks,
    required this.tooltipSettings,
    required this.items,
    this.dataStartIndex = 0,
    this.dataEndIndex = 0,
    this.brushRect,
  });
  final Size size;
  final ChartLayout layout;
  final String chartName;
  final List<Object?> chartData;
  final ChartOffset offset;

  /// Rendered (explicit, not hidden) axes.
  final List<AxisLayout> axes;
  final List<SeriesModel> series;
  final GridModel? grid;
  final List<ReferenceLineModel> referenceLines;
  final AxisRuntime tooltipAxis;
  final List<TickItem> tooltipTicks;
  final Tooltip? tooltipSettings;
  final List<GraphicalItem> items;

  /// `state.chartData.dataStartIndex` / `dataEndIndex`, set by the Brush.
  final int dataStartIndex, dataEndIndex;

  /// `selectBrushDimensions` (before `dy`), null without a Brush.
  final Rect? brushRect;

  /// `selectChartDataSliceWithIndexes`.
  late final List<Object?> displayedData = jsSlice(chartData, dataStartIndex, dataEndIndex + 1);

  /// `selectChartViewBox`.
  Rect get viewBox => offset.plotArea;

  /// `useTooltipAxisBandSize`.
  double get tooltipAxisBandSize => getBandSizeOfAxis(tooltipAxis.scale, tooltipTicks) ?? 0;
}

/// Stable ids for graphical items: explicit `id`, else type + position.
List<GraphicalItem> collectItems(List<RechartsElement> children, {String prefix = ''}) {
  final items = <GraphicalItem>[];
  var i = 0;
  for (final c in children) {
    if (c is CartesianSeries) {
      items.add(GraphicalItem('$prefix${c.id ?? '${c is Bar ? 'bar' : 'line'}-$i'}', c));
      i++;
    }
  }
  return items;
}

/// `computeLegendPayloadFromBarData` / `computeLegendPayloadFromAreaData` +
/// `selectLegendPayload` (sorted by Legend `itemSorter`).
List<LegendPayload> legendPayloadOf(List<GraphicalItem> items, Legend legend) {
  final payload = [
    for (final i in items)
      LegendPayload(
        value: i.element.name != null ? jsString(i.element.name) : (i.dataKey is String ? i.dataKey as String : null),
        type: i.element.legendType,
        color: i.element is Line ? (i.element as Line).stroke : (i.element as Bar).fill,
        dataKey: i.dataKey,
        inactive: i.hide,
        strokeDasharray: i.element is Line ? (i.element as Line).strokeDasharray : null,
      ),
  ];
  final sorter = legend.itemSorter;
  if (sorter == 'value') return sortByKey(payload, (p) => p.value);
  if (sorter == 'dataKey') return sortByKey(payload, (p) => p.dataKey is Function ? null : p.dataKey);
  if (sorter is Object? Function(LegendPayload)) return sortByKey(payload, sorter);
  return payload;
}

/// `appendOffsetOfLegend` (legends without `position`).
({double top, double right, double bottom, double left}) appendOffsetOfLegend(
    ({double top, double right, double bottom, double left}) offset, Legend? legend, Size legendSize) {
  if (legend == null) return offset;
  final layout = legend.layout ?? ChartLayout.horizontal;
  final align = legend.align, verticalAlign = legend.verticalAlign;
  if ((layout == ChartLayout.vertical || (layout == ChartLayout.horizontal && verticalAlign == VerticalAlign.middle)) &&
      align != HorizontalAlign.center) {
    return align == HorizontalAlign.left
        ? (top: offset.top, right: offset.right, bottom: offset.bottom, left: offset.left + legendSize.width)
        : (top: offset.top, right: offset.right + legendSize.width, bottom: offset.bottom, left: offset.left);
  }
  if ((layout == ChartLayout.horizontal || (layout == ChartLayout.vertical && align == HorizontalAlign.center)) &&
      verticalAlign != VerticalAlign.middle) {
    return verticalAlign == VerticalAlign.top
        ? (top: offset.top + legendSize.height, right: offset.right, bottom: offset.bottom, left: offset.left)
        : (top: offset.top, right: offset.right, bottom: offset.bottom + legendSize.height, left: offset.left);
  }
  return offset;
}

int _compareIds(Object a, Object b) => compareAscending(a, b);

/// Recharts' state keeps axes in an object keyed by id.
Map<Object, T> _byId<T extends CartesianAxisElement>(Iterable<T> axes) => {for (final a in axes) a.id: a};

CartesianModel computeCartesianModel({
  required String chartName,
  required Size size,
  required List<Object?> data,
  required List<RechartsElement> children,
  ChartLayout layout = ChartLayout.horizontal,
  Margin margin = const Margin.all(5),
  Object barCategoryGap = '10%',
  Object barGap = 4,
  Object? barSize,
  double? maxBarSize,
  StackOffset stackOffset = StackOffset.none,
  bool reverseStackOrder = false,
  Size legendSize = Size.zero,
  required StringMeasurer Function(CartesianAxisElement? axis) measureFor,
  int dataStartIndex = 0,
  int? dataEndIndex,
  List<RechartsElement> sharedChildren = const [],
  bool panorama = false,
  ChartOffset? rootOffset,
  Size? rootSize,
  Map<Object, double> yAxisWidths = const {},
}) {
  final chartWidth = size.width, chartHeight = size.height;
  final xAxes = _byId(children.whereType<XAxis>());
  final yAxes = _byId(children.whereType<YAxis>());
  final items = collectItems(children);
  // The panorama and the main chart share one store: their items meet in axis domains.
  final domainItems = [...items, ...collectItems(sharedChildren, prefix: 'shared-')];
  final refLines = children.whereType<ReferenceLine>().toList();
  final tooltip = panorama ? null : children.whereType<Tooltip>().firstOrNull;
  final legend = panorama ? null : children.whereType<Legend>().firstOrNull;
  final brush = panorama ? null : children.whereType<Brush>().firstOrNull;
  final gridSettings = children.whereType<CartesianGrid>().firstOrNull;
  final dataEnd = dataEndIndex ?? (data.isEmpty ? 0 : data.length - 1);
  final displayedData = jsSlice(data, dataStartIndex, dataEnd + 1);

  // YAxis width: a number, or the measured 'auto' width (DEFAULT_Y_AXIS_WIDTH until measured).
  double yWidth(YAxis a) => a.width is num ? (a.width as num).toDouble() : yAxisWidths[a.id] ?? 60;

  // selectChartOffsetInternal; the panorama's viewBox is the brush minus its padding.
  double sumY(AxisOrientation o) => yAxes.values
      .where((a) => a.orientation == o && !a.mirror && !a.hide)
      .fold(0.0, (r, a) => r + yWidth(a));
  double sumX(AxisOrientation o) => xAxes.values
      .where((a) => a.orientation == o && !a.mirror && !a.hide)
      .fold(0.0, (r, a) => r + a.height);
  var off = panorama
      ? (top: margin.top, right: margin.right, bottom: margin.bottom, left: margin.left)
      : (
          top: margin.top + sumX(AxisOrientation.top),
          right: margin.right + sumY(AxisOrientation.right),
          bottom: margin.bottom + sumX(AxisOrientation.bottom),
          left: margin.left + sumY(AxisOrientation.left),
        );
  final brushBottom = off.bottom;
  off = (top: off.top, right: off.right, bottom: off.bottom + (brush?.height ?? 0), left: off.left);
  off = appendOffsetOfLegend(off, legend, legendSize);
  final offset = ChartOffset(
    top: off.top,
    right: off.right,
    bottom: off.bottom,
    left: off.left,
    width: math.max(chartWidth - off.left - off.right, 0),
    height: math.max(chartHeight - off.top - off.bottom, 0),
  );

  XAxis xSettings(Object id) => xAxes[id] ?? XAxis(xAxisId: id, hide: true);
  YAxis ySettings(Object id) => yAxes[id] ?? YAxis(yAxisId: id, hide: true);
  final tooltipAxisId = tooltip?.axisId ?? 0;
  final CartesianAxisElement tooltipAxisSettings =
      layout == ChartLayout.horizontal ? xSettings(tooltipAxisId) : ySettings(tooltipAxisId);

  final ctx = ChartContext(
    layout: layout,
    chartName: chartName,
    chartData: displayedData,
    fullChartData: data,
    dataStartIndex: dataStartIndex,
    dataEndIndex: dataEnd,
    items: domainItems,
    referenceLines: refLines,
    stackOffset: stackOffset,
    reverseStackOrder: reverseStackOrder,
    barCategoryGap: barCategoryGap,
    tooltipAxis: tooltipAxisSettings,
  );

  // Every axis anyone reads: explicit ones, the ones items point at, the tooltip axis.
  final xIds = {
    ...xAxes.keys,
    for (final i in domainItems) i.xAxisId,
    for (final r in refLines) r.xAxisId,
    ?gridSettings?.xAxisId,
    if (layout == ChartLayout.horizontal) tooltipAxisId,
  };
  final yIds = {
    ...yAxes.keys,
    for (final i in domainItems) i.yAxisId,
    for (final r in refLines) r.yAxisId,
    ?gridSettings?.yAxisId,
    if (layout == ChartLayout.vertical) tooltipAxisId,
  };
  final runtimes = <(bool, Object), AxisRuntime>{};
  for (final id in xIds) {
    final s = xSettings(id);
    runtimes[(true, id)] = AxisRuntime(settings: s, isX: true, type: evaluatedAxisType(layout, s));
  }
  for (final id in yIds) {
    final s = ySettings(id);
    runtimes[(false, id)] = AxisRuntime(settings: s, isX: false, type: evaluatedAxisType(layout, s));
  }

  final rangeWidth = layout == ChartLayout.vertical ? offset.height : offset.width;
  for (final axis in runtimes.values) {
    computeAxisDomain(axis, ctx);
    final p = axis.settings.padding;
    final calculated = p.mode == null ? 0.0 : calculatedPadding(axis, p.mode!, rangeWidth, barCategoryGap);
    final List<double> range;
    if (panorama) {
      // selectXAxisRange / selectYAxisRange with isPanorama: no axis padding.
      range = axis.isX ? [offset.left, offset.left + offset.width] : [offset.top + offset.height, offset.top];
    } else if (axis.isX) {
      final left = p.mode == null ? p.left + calculated : calculated;
      final right = p.mode == null ? p.right + calculated : calculated;
      range = [offset.left + left, offset.left + offset.width - right];
    } else {
      final top = p.mode == null ? p.top + calculated : calculated;
      final bottom = p.mode == null ? p.bottom + calculated : calculated;
      range = layout == ChartLayout.horizontal
          ? [offset.top + offset.height - bottom, offset.top + top]
          : [offset.top + top, offset.top + offset.height - bottom];
    }
    axis.range = range;
    final withReverse = axis.settings.reversed ? [range[1], range[0]] : range;
    axis.scale = buildScale(axis.realScaleType, axis.domainWithNiceTicks, withReverse);
    axis.ticksOfAxis = combineAxisTicks(axis);
    axis.itemTicks = combineGraphicalItemTicks(axis);
  }
  AxisRuntime xRt(Object id) => runtimes[(true, id)]!;
  AxisRuntime yRt(Object id) => runtimes[(false, id)]!;

  // Axis positions: selectAllXAxesOffsetSteps / selectAllYAxesOffsetSteps.
  final axisViewBox = Rect.fromLTWH(0, 0, chartWidth, chartHeight);
  final axes = <AxisLayout>[];
  Map<Object, double> steps<T extends CartesianAxisElement>(Iterable<T> all, AxisOrientation o, bool mirror,
      double start, bool needSpace, double Function(T) size) {
    final sorted = all.where((a) => a.orientation == o && a.mirror == mirror).toList()
      ..sort((a, b) => _compareIds(a.id, b.id));
    final out = <Object, double>{};
    var position = start;
    for (final a in sorted) {
      out[a.id] = position - (needSpace ? size(a) : 0);
      position += (needSpace ? -1 : 1) * size(a);
    }
    return out;
  }

  for (final a in xAxes.values) {
    final start = a.orientation == AxisOrientation.top ? offset.top : chartHeight - offset.bottom;
    final needSpace =
        (a.orientation == AxisOrientation.top && !a.mirror) || (a.orientation == AxisOrientation.bottom && a.mirror);
    final y = steps<XAxis>(xAxes.values, a.orientation, a.mirror, start, needSpace, (x) => x.height)[a.id] ?? 0;
    if (a.hide || panorama) continue;
    final rect = Rect.fromLTWH(offset.left, y, offset.width, a.height);
    axes.add(AxisLayout(xRt(a.id), rect, _visibleTicks(xRt(a.id), axisViewBox, measureFor(a))));
  }
  for (final a in yAxes.values) {
    final start = a.orientation == AxisOrientation.left ? offset.left : chartWidth - offset.right;
    final needSpace =
        (a.orientation == AxisOrientation.left && !a.mirror) || (a.orientation == AxisOrientation.right && a.mirror);
    final x = steps<YAxis>(yAxes.values, a.orientation, a.mirror, start, needSpace, yWidth)[a.id] ?? 0;
    if (a.hide || panorama) continue;
    final rect = Rect.fromLTWH(x, offset.top, yWidth(a), offset.height);
    axes.add(AxisLayout(yRt(a.id), rect, _visibleTicks(yRt(a.id), axisViewBox, measureFor(a))));
  }

  final off0 = offset, axisViewBox0 = axisViewBox;

  // Graphical items.
  final series = <SeriesModel>[];
  for (final item in items) {
    final xa = xRt(item.xAxisId), ya = yRt(item.yAxisId);
    if (item.isBar) {
      series.add(SeriesModel(item,
          rects: _barRectangles(item, items, xa, ya, layout, offset, displayedData, dataStartIndex, barSize,
              maxBarSize, barGap, barCategoryGap)));
    } else {
      series.add(SeriesModel(item, points: _linePoints(item, xa, ya, layout, displayedData)));
    }
  }

  // CartesianGrid: a panorama's grid reads the main chart's offset and size
  // (useOffsetInternal, useChartWidth/Height), with the panorama's axes.
  GridModel? grid;
  if (gridSettings != null) {
    final g = gridSettings;
    final offset = rootOffset ?? off0;
    final axisViewBox = rootSize == null ? axisViewBox0 : Offset.zero & rootSize;
    final rect = Rect.fromLTWH(g.x ?? offset.left, g.y ?? offset.top, g.width ?? offset.width, g.height ?? offset.height);
    var horizontalPoints = g.horizontalPoints;
    var verticalPoints = g.verticalPoints;
    final measure = measureFor(null);
    if (horizontalPoints.isEmpty) {
      final ya = yRt(g.yAxisId);
      final hasValues = g.horizontalValues != null && g.horizontalValues!.isNotEmpty;
      final ticks = _gridTicks(ya, g.horizontalValues, axisViewBox, measure);
      horizontalPoints =
          getCoordinatesOfGrid(ticks, offset.top, offset.top + offset.height, hasValues ? true : g.syncWithTicks);
    }
    if (verticalPoints.isEmpty) {
      final xa = xRt(g.xAxisId);
      final hasValues = g.verticalValues != null && g.verticalValues!.isNotEmpty;
      final ticks = _gridTicks(xa, g.verticalValues, axisViewBox, measure);
      verticalPoints =
          getCoordinatesOfGrid(ticks, offset.left, offset.left + offset.width, hasValues ? true : g.syncWithTicks);
    }
    if (rect.width > 0 && rect.height > 0) grid = GridModel(g, rect, horizontalPoints, verticalPoints);
  }

  // ReferenceLine getEndPoints
  final refModels = <ReferenceLineModel>[];
  for (final r in refLines) {
    final xa = runtimes[(true, r.xAxisId)], ya = runtimes[(false, r.yAxisId)];
    final xs = xa?.scale, ys = ya?.scale;
    if (xs == null || ys == null) continue;
    final vb = offset.plotArea;
    if (isNumOrStr(r.y)) {
      final coord = ys.map(r.y, position: r.position);
      if (!isWellBehavedNumber(coord)) continue;
      if (r.ifOverflow == IfOverflow.discard && !ys.isInRange(coord!)) continue;
      final pts = [Offset(vb.right, coord!), Offset(vb.left, coord)];
      final o = ya!.settings.orientation == AxisOrientation.left ? pts.reversed.toList() : pts;
      refModels.add(ReferenceLineModel(r, o[0], o[1]));
    } else if (isNumOrStr(r.x)) {
      final coord = xs.map(r.x, position: r.position);
      if (!isWellBehavedNumber(coord)) continue;
      if (r.ifOverflow == IfOverflow.discard && !xs.isInRange(coord!)) continue;
      final pts = [Offset(coord!, vb.bottom), Offset(coord, vb.top)];
      final o = xa!.settings.orientation == AxisOrientation.top ? pts.reversed.toList() : pts;
      refModels.add(ReferenceLineModel(r, o[0], o[1]));
    }
  }

  // Tooltip axis ticks (combineTicksOfTooltipAxis).
  final tooltipAxis = layout == ChartLayout.horizontal ? xRt(tooltipAxisId) : yRt(tooltipAxisId);
  final tooltipTicks = _tooltipTicks(tooltipAxis);

  return CartesianModel(
    size: size,
    layout: layout,
    chartName: chartName,
    chartData: data,
    offset: offset,
    axes: axes,
    series: series,
    grid: grid,
    referenceLines: refModels,
    tooltipAxis: tooltipAxis,
    tooltipTicks: tooltipTicks,
    tooltipSettings: tooltip,
    items: items,
    dataStartIndex: dataStartIndex,
    dataEndIndex: dataEnd,
    brushRect: brush == null
        ? null
        : Rect.fromLTWH(
            brush.x ?? offset.left,
            brush.y ?? offset.top + offset.height + brushBottom - margin.bottom,
            brush.width ?? offset.width,
            brush.height,
          ),
  );
}

List<TickItem> _visibleTicks(AxisRuntime axis, Rect viewBox, StringMeasurer measure) {
  final s = axis.settings;
  return getTicks(
    tick: s.tick,
    ticks: axis.ticksOfAxis,
    viewBox: viewBox,
    minTickGap: s.minTickGap,
    orientation: s.orientation,
    interval: s.interval,
    tickFormatter: s.tickFormatter,
    unit: s.unit,
    angle: s.angle,
    measure: measure,
  );
}

List<TickItem> _gridTicks(AxisRuntime axis, List<Object>? valuesOverride, Rect viewBox, StringMeasurer measure) {
  final s = axis.settings;
  return getTicks(
    tick: s.tick,
    ticks: getTicksOfAxisForGrid(axis, valuesOverride != null && valuesOverride.isNotEmpty ? valuesOverride : null),
    viewBox: viewBox,
    minTickGap: s.minTickGap,
    orientation: s.orientation,
    interval: s.interval,
    tickFormatter: s.tickFormatter,
    unit: s.unit,
    angle: s.angle,
    measure: measure,
  );
}

List<TickItem> _tooltipTicks(AxisRuntime axis) {
  final scale = axis.scale;
  if (scale == null) return const [];
  final bw = scale.bandwidth;
  final offset = axis.type == AxisDomainType.category && bw != null ? bw / 2 : 0.0;
  final out = <TickItem>[];
  if (axis.isCategorical && axis.categoricalDomain != null) {
    final d = axis.categoricalDomain!;
    for (var i = 0; i < d.length; i++) {
      final scaled = scale.map(d[i]);
      if (!isWellBehavedNumber(scaled)) continue;
      out.add(TickItem(coordinate: scaled! + offset, value: d[i], index: i, offset: offset));
    }
    return out;
  }
  final dom = scale.domain;
  final dup = axis.duplicateDomain;
  for (var i = 0; i < dom.length; i++) {
    final scaled = scale.map(dom[i]);
    if (!isWellBehavedNumber(scaled)) continue;
    final e = dom[i];
    final value = dup != null && e is int && e >= 0 && e < dup.length ? dup[e] : e;
    out.add(TickItem(coordinate: scaled! + offset, value: value, index: i, offset: offset));
  }
  return out;
}

// ---------------------------------------------------------------------------
// Bars

class _BarCategory {
  _BarCategory(this.stackId, this.dataKeys, this.barSize);
  final String? stackId;
  final List<Object> dataKeys;
  final double? barSize;
}

class _BarPosition {
  _BarPosition(this.stackId, this.dataKeys, this.offset, this.size);
  final String? stackId;
  final List<Object> dataKeys;
  final double offset, size;
}

bool _isArrayIndex(String k) => RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(k) && int.parse(k) < 4294967295;

/// `combineBarSizeList`.
List<_BarCategory> _barSizeList(List<GraphicalItem> allBars, Object? globalSize, double totalSize) {
  double? barSizeOf(Object? self) {
    final s = self ?? globalSize;
    return s == null ? null : getPercentValue(s, totalSize, 0);
  }

  final groups = <String, List<GraphicalItem>>{};
  for (final b in allBars.where((b) => b.stackId != null)) {
    groups.putIfAbsent(b.stackId!, () => []).add(b);
  }
  // JS object key order: integer-like keys first, ascending.
  final keys = groups.keys.toList();
  final intKeys = keys.where(_isArrayIndex).toList()..sort((a, b) => int.parse(a).compareTo(int.parse(b)));
  final ordered = [...intKeys, ...keys.where((k) => !_isArrayIndex(k))];
  return [
    for (final k in ordered)
      _BarCategory(k, [for (final b in groups[k]!) b.dataKey], barSizeOf((groups[k]!.first.element as Bar).barSize)),
    for (final b in allBars.where((b) => b.stackId == null))
      _BarCategory(null, [b.dataKey], barSizeOf((b.element as Bar).barSize)),
  ];
}

/// `getBarPositions` (combineAllBarPositions.ts).
List<_BarPosition>? _getBarPositions(
    Object barGap, Object barCategoryGap, double bandSize, List<_BarCategory> sizeList, double? maxBarSize) {
  final len = sizeList.length;
  if (len < 1) return null;
  var realBarGap = getPercentValue(barGap, bandSize, 0, true);
  final result = <_BarPosition>[];
  if (isWellBehavedNumber(sizeList[0].barSize)) {
    var useFull = false;
    var fullBarSize = bandSize / len;
    var sum = sizeList.fold<double>(0, (r, e) => r + (e.barSize ?? 0));
    sum += (len - 1) * realBarGap;
    if (sum >= bandSize) {
      sum -= (len - 1) * realBarGap;
      realBarGap = 0;
    }
    if (sum >= bandSize && fullBarSize > 0) {
      useFull = true;
      fullBarSize *= 0.9;
      sum = len * fullBarSize;
    }
    final offset = jsRound((bandSize - sum) / 2);
    var prevOffset = offset - realBarGap, prevSize = 0.0;
    for (final entry in sizeList) {
      final pos = _BarPosition(
          entry.stackId, entry.dataKeys, prevOffset + prevSize + realBarGap, useFull ? fullBarSize : (entry.barSize ?? 0));
      result.add(pos);
      prevOffset = pos.offset;
      prevSize = pos.size;
    }
  } else {
    final offset = getPercentValue(barCategoryGap, bandSize, 0, true);
    if (bandSize - 2 * offset - (len - 1) * realBarGap <= 0) realBarGap = 0;
    var originalSize = (bandSize - 2 * offset - (len - 1) * realBarGap) / len;
    if (originalSize > 1) originalSize = jsRound(originalSize);
    final size = isWellBehavedNumber(maxBarSize) ? math.min(originalSize, maxBarSize!) : originalSize;
    for (var i = 0; i < len; i++) {
      final entry = sizeList[i];
      result.add(_BarPosition(entry.stackId, entry.dataKeys,
          offset + (len * (originalSize - size)) / 2 + (size + realBarGap) * i, size));
    }
  }
  return result;
}

double _minPointSizeOf(Object minPointSize, Object? value, int index) {
  if (minPointSize is num) return minPointSize.toDouble();
  if (minPointSize is Function && (value == null || value is num)) {
    return ((minPointSize as dynamic)(value, index) as num).toDouble();
  }
  return 0;
}

List<BarRect>? _barRectangles(GraphicalItem item, List<GraphicalItem> items, AxisRuntime xAxis, AxisRuntime yAxis,
    ChartLayout layout, ChartOffset offset, List<Object?> chartData, int dataStartIndex, Object? rootBarSize,
    double? rootMaxBarSize, Object barGap, Object barCategoryGap) {
  final bar = item.element as Bar;
  final horizontal = layout == ChartLayout.horizontal;
  final cateAxis = horizontal ? xAxis : yAxis;
  final numericAxis = horizontal ? yAxis : xAxis;
  final xScale = xAxis.scale, yScale = yAxis.scale;
  if (xScale == null || yScale == null || xAxis.itemTicks == null || yAxis.itemTicks == null) return null;

  // selectAllVisibleBars + selectBarSizeList
  final allBars = items
      .where((i) => horizontal ? i.xAxisId == item.xAxisId : i.yAxisId == item.yAxisId)
      .where((i) => !i.hide && i.isBar)
      .toList();
  final totalSize = horizontal ? offset.width : offset.height;
  final sizeList = _barSizeList(allBars, rootBarSize, totalSize);

  final maxBarSize = bar.maxBarSize ?? rootMaxBarSize;
  final barBandSize = getBandSizeOfAxis(cateAxis.scale, cateAxis.itemTicks, true) ?? maxBarSize ?? 0;
  final bandSize = getBandSizeOfAxis(cateAxis.scale, cateAxis.itemTicks);
  if (bandSize == null) return null;

  // combineAllBarPositions
  var positions =
      _getBarPositions(barGap, barCategoryGap, barBandSize != bandSize ? barBandSize : bandSize, sizeList, maxBarSize);
  if (barBandSize != bandSize && positions != null) {
    positions = [for (final p in positions) _BarPosition(p.stackId, p.dataKeys, p.offset - barBandSize / 2, p.size)];
  }
  final pos = positions?.where((p) => p.stackId == item.stackId && p.dataKeys.contains(item.dataKey)).firstOrNull;
  if (pos == null) return null;

  // selectStackedDataOfItem
  final stackedData = item.stackId == null ? null : numericAxis.stackGroups?[item.stackId]?.stackedData[item.id];

  // computeBarRectangles
  final numericScale = numericAxis.scale!;
  final dom = numericScale.domain;
  final Object? baseValue;
  if (numericAxis.type == AxisDomainType.number) {
    final a = jsNumber(dom[0]), b = jsNumber(dom[1]);
    final minValue = math.min(a, b), maxValue = math.max(a, b);
    baseValue = minValue <= 0 && maxValue >= 0 ? 0 : (maxValue < 0 ? maxValue : minValue);
  } else {
    baseValue = dom.isEmpty ? null : dom[0];
  }
  final stackedBarStart = numericScale.map(baseValue) ?? double.nan;

  double? cateCoordinate(AxisRuntime axis, Object? entry, int index) {
    if (axis.type == AxisDomainType.category) {
      final ticks = axis.itemTicks!;
      return index < ticks.length ? ticks[index].coordinate + pos.offset : null;
    }
    final d = axis.scale!.domain;
    final value = getValueByDataKey(entry, axis.settings.dataKey, index < d.length ? d[index] : null);
    if (value == null) return null;
    final scaled = axis.scale!.map(value);
    if (!isNumber(scaled)) return null;
    return scaled! - bandSize / 2 + pos.offset;
  }

  final cells = bar.cells;
  final rects = <BarRect>[];
  for (var index = 0; index < chartData.length; index++) {
    final entry = chartData[index];
    List<Object?> value;
    if (stackedData != null) {
      // stackedData spans the whole chart data; the slice starts at dataStartIndex.
      final i = index + dataStartIndex;
      if (i < 0 || i >= stackedData.length) continue;
      value = _truncateByDomain(stackedData[i], dom);
    } else {
      final v = getValueByDataKey(entry, bar.dataKey);
      value = v is List ? v : [baseValue, v];
    }
    final minPointSize = _minPointSizeOf(bar.minPointSize, value.length > 1 ? value[1] : null, index);
    double? x, y;
    double width, height;
    Rect? background;
    if (horizontal) {
      final baseValueScale = yScale.map(value[0]);
      final currentValueScale = yScale.map(value[1]);
      if (baseValueScale == null || currentValueScale == null) continue;
      x = cateCoordinate(xAxis, entry, index);
      y = currentValueScale;
      width = pos.size;
      final computedHeight = baseValueScale - currentValueScale;
      height = computedHeight.isNaN ? 0 : computedHeight;
      if (x != null) background = Rect.fromLTWH(x, offset.top, width, offset.height);
      if (minPointSize.abs() > 0 && height.abs() < minPointSize.abs()) {
        final delta = mathSign(height != 0 ? height : minPointSize) * (minPointSize.abs() - height.abs());
        y -= delta;
        height += delta;
      }
    } else {
      final baseValueScale = xScale.map(value[0]);
      final currentValueScale = xScale.map(value[1]);
      if (baseValueScale == null || currentValueScale == null) continue;
      x = baseValueScale;
      y = cateCoordinate(yAxis, entry, index);
      width = currentValueScale - baseValueScale;
      height = pos.size;
      if (y != null) background = Rect.fromLTWH(offset.left, y, offset.width, height);
      if (minPointSize.abs() > 0 && width.abs() < minPointSize.abs()) {
        final delta = mathSign(width != 0 ? width : minPointSize) * (minPointSize.abs() - width.abs());
        width += delta;
      }
    }
    if (x == null || y == null || width == 0 || height == 0) continue;
    rects.add(BarRect(
      x: x,
      y: y,
      width: width,
      height: height,
      value: stackedData != null ? value : value[1],
      payload: entry,
      background: background,
      stackedBarStart: stackedBarStart,
      originalDataIndex: index,
      cell: index < cells.length ? cells[index] : null,
    ));
  }
  return rects;
}

/// `truncateByDomain`.
List<Object?> _truncateByDomain(List<double> value, List<Object?> domain) {
  if (domain.length != 2 || !isNumber(domain[0]) || !isNumber(domain[1])) return value;
  final a = (domain[0] as num).toDouble(), b = (domain[1] as num).toDouble();
  final minValue = math.min(a, b), maxValue = math.max(a, b);
  final result = [value[0], value[1]];
  if (value[0].isNaN || value[0] < minValue) result[0] = minValue;
  if (value[1].isNaN || value[1] > maxValue) result[1] = maxValue;
  if (result[0] > maxValue) result[0] = maxValue;
  if (result[1] < minValue) result[1] = minValue;
  return result;
}

// ---------------------------------------------------------------------------
// Lines

List<LinePoint>? _linePoints(
    GraphicalItem item, AxisRuntime xAxis, AxisRuntime yAxis, ChartLayout layout, List<Object?> chartData) {
  final xTicks = xAxis.itemTicks, yTicks = yAxis.itemTicks;
  if (xAxis.scale == null || yAxis.scale == null || xTicks == null || yTicks == null) return null;
  if (xTicks.isEmpty || yTicks.isEmpty) return null;
  final cate = isCategoricalAxis(layout, true) ? xAxis : yAxis;
  final bandSize = getBandSizeOfAxis(cate.scale, cate.itemTicks) ?? 0;
  final displayed = (item.data != null && item.data!.isNotEmpty) ? item.data! : chartData;

  double? cateCoordinate(AxisRuntime axis, List<TickItem> ticks, Object? entry, int index) {
    final s = axis.settings;
    if (axis.type == AxisDomainType.category) {
      if (!s.allowDuplicatedCategory && s.dataKey != null) {
        final v = getValueByDataKey(entry, s.dataKey);
        if (v != null) {
          final matched = ticks.where((t) => t.value == v).firstOrNull;
          if (matched != null) return matched.coordinate + bandSize / 2;
        }
      }
      return index < ticks.length ? ticks[index].coordinate + bandSize / 2 : null;
    }
    final scaled = axis.scale!.map(getValueByDataKey(entry, s.dataKey));
    return isNumber(scaled) ? scaled : null;
  }

  final points = <LinePoint>[];
  for (var index = 0; index < displayed.length; index++) {
    final entry = displayed[index];
    final value = getValueByDataKey(entry, item.dataKey);
    if (layout == ChartLayout.horizontal) {
      final x = cateCoordinate(xAxis, xTicks, entry, index);
      final y = value == null ? null : yAxis.scale!.map(value);
      points.add(LinePoint(x, y, value, entry));
    } else {
      final x = value == null ? null : xAxis.scale!.map(value);
      final y = cateCoordinate(yAxis, yTicks, entry, index);
      if (x == null || y == null) continue;
      points.add(LinePoint(x, y, value, entry));
    }
  }
  return points;
}

// ---------------------------------------------------------------------------
// Tooltip

/// `ActiveTooltipProps`.
class ActiveProps {
  const ActiveProps(this.activeIndex, this.activeCoordinate);
  final int activeIndex;
  final Offset activeCoordinate;
}

/// `calculateActiveTickIndex` for ticks in a single direction.
int calculateActiveTickIndex(double? coordinate, List<TickItem> ticks) {
  final len = ticks.length;
  if (len <= 1 || coordinate == null) return 0;
  for (var i = 0; i < len; i++) {
    final curr = ticks[i];
    final next = i + 1 < len ? ticks[i + 1] : null;
    final prev = i > 0 ? ticks[i - 1] : null;
    if (i == 0 && next != null && coordinate <= (curr.coordinate + next.coordinate) / 2) return curr.index;
    if (i == len - 1 && prev != null && coordinate > (curr.coordinate + prev.coordinate) / 2) return curr.index;
    if (i > 0 &&
        i < len - 1 &&
        prev != null &&
        next != null &&
        coordinate > (curr.coordinate + prev.coordinate) / 2 &&
        coordinate <= (curr.coordinate + next.coordinate) / 2) {
      return curr.index;
    }
  }
  return -1;
}

/// `combineActiveCartesianProps`. [pointer] is relative to the chart and is
/// rounded like `getRelativeCoordinate`.
ActiveProps? activePropsFromPointer(CartesianModel m, Offset pointer) {
  final rx = jsRound(pointer.dx), ry = jsRound(pointer.dy);
  final o = m.offset;
  if (!(rx >= o.left && rx <= o.left + o.width && ry >= o.top && ry <= o.top + o.height)) return null;
  if (m.tooltipAxis.scale == null) return null;
  final pos = m.layout == ChartLayout.horizontal ? rx : ry;
  final ordered = sortByKey(m.tooltipTicks, (t) => t.coordinate);
  final activeIndex = calculateActiveTickIndex(pos, ordered);
  final entry = m.tooltipTicks.where((t) => t.index == activeIndex).firstOrNull;
  Offset coordinate = Offset.zero;
  if (entry != null) {
    coordinate = m.layout == ChartLayout.horizontal ? Offset(entry.coordinate, ry) : Offset(rx, entry.coordinate);
  }
  return ActiveProps(activeIndex, coordinate);
}

/// `selectTooltipDisplayedData`.
List<Object?> tooltipDisplayedData(CartesianModel m) {
  final s = m.tooltipAxis.settings;
  final items = m.items.where((i) => (m.layout == ChartLayout.horizontal ? i.xAxisId : i.yAxisId) == s.id);
  final itemData = [
    for (final i in items.where((i) => s.includeHidden || !i.hide)) ...?i.data,
  ];
  return itemData.isNotEmpty ? itemData : m.displayedData;
}

/// `combineActiveTooltipIndex`.
int? combineActiveTooltipIndex(CartesianModel m, int? desiredIndex) {
  if (desiredIndex == null) return null;
  final data = tooltipDisplayedData(m);
  final upperLimit = data.isNotEmpty ? data.length - 1 : 1 << 30;
  final clamped = math.max(0, math.min(desiredIndex, upperLimit));
  if (clamped >= data.length) return clamped;
  final entry = data[clamped];
  final dataKey = m.tooltipAxis.settings.dataKey;
  final domain = m.tooltipAxis.domain;
  if (domain != null && dataKey != null) {
    final value = getValueByDataKey(entry, dataKey);
    if (value != null &&
        domain.length == 2 &&
        isWellBehavedNumber(domain[0]) &&
        isWellBehavedNumber(domain[1])) {
      final n = jsNumber(value);
      if (!n.isFinite) return null;
      final a = (domain[0] as num).toDouble(), b = (domain[1] as num).toDouble();
      if (n < math.min(a, b) || n > math.max(a, b)) return null;
    }
  }
  return clamped;
}

/// `combineActiveLabel`.
Object? activeLabelOf(CartesianModel m, int? activeIndex) {
  if (activeIndex == null || activeIndex < 0) return null;
  return activeIndex < m.tooltipTicks.length ? m.tooltipTicks[activeIndex].value : null;
}

/// `combineTooltipPayload` for the 'axis' event type.
List<TooltipPayloadEntry> tooltipPayloadOf(CartesianModel m, int? activeIndex) {
  if (activeIndex == null) return const [];
  final axisDataKey = m.tooltipAxis.settings.dataKey;
  final activeLabel = activeLabelOf(m, activeIndex);
  final out = <TooltipPayloadEntry>[];
  for (final item in m.items) {
    final el = item.element;
    final finalData = getSliced(item.data ?? m.chartData, m.dataStartIndex, m.dataEndIndex);
    Object? payload;
    if (axisDataKey != null) {
      payload = finalData.where((e) => getValueByDataKey(e, axisDataKey) == activeLabel).firstOrNull;
      payload ??= activeIndex >= 0 && activeIndex < finalData.length ? finalData[activeIndex] : null;
    } else {
      payload = activeIndex >= 0 && activeIndex < finalData.length ? finalData[activeIndex] : null;
    }
    final name = el.name != null ? jsString(el.name) : (el.dataKey is String ? el.dataKey as String : null);
    out.add(TooltipPayloadEntry(
      dataKey: el.dataKey,
      name: name,
      value: getValueByDataKey(payload, el.dataKey),
      payload: payload,
      color: el.tooltipColor,
      fill: el is Line ? el.fill : (el as Bar).fill,
      stroke: el is Line ? el.stroke : (el as Bar).stroke,
      unit: el.unit,
      hide: el.hide,
      type: el.tooltipType,
      formatter: el.formatter,
    ));
  }
  return out;
}

/// `getCursorRectangle`.
Rect cursorRectangle(ChartLayout layout, Offset activeCoordinate, ChartOffset offset, double bandSize) {
  final half = bandSize / 2;
  return layout == ChartLayout.horizontal
      ? Rect.fromLTWH(activeCoordinate.dx - half, offset.top + 0.5, bandSize, offset.height - 1)
      : Rect.fromLTWH(offset.left + 0.5, activeCoordinate.dy - half, offset.width - 1, bandSize);
}

/// `getCursorPoints` for cartesian layouts.
List<Offset> cursorPoints(ChartLayout layout, Offset activeCoordinate, ChartOffset offset) =>
    layout == ChartLayout.horizontal
        ? [Offset(activeCoordinate.dx, offset.top), Offset(activeCoordinate.dx, offset.top + offset.height)]
        : [Offset(offset.left, activeCoordinate.dy), Offset(offset.left + offset.width, activeCoordinate.dy)];

/// The scale of a numeric/categorical axis, exposed for tests.
RechartsScale? axisScaleOf(CartesianModel m, {required bool isX, Object id = 0}) =>
    m.axes.where((a) => a.runtime.isX == isX && a.settings.id == id).firstOrNull?.runtime.scale;
