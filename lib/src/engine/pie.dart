// The polar chart "store" for Pie: the polar offset (selectChartOffsetInternal
// without axes or brush), src/state/selectors/pieSelectors.ts
// (selectDisplayedData, selectPieLegend), computePieSectors and
// parseCoordinateOfPie (src/polar/Pie.tsx), the Pie's tooltip entry settings
// (SetPieTooltipEntrySettings), combineTooltipPayload for item tooltips,
// combineDisplayedData for the tooltip data, and defaultPieAnimateItems.

import 'dart:math' as math;
import 'dart:ui';

import '../animation.dart';
import '../components.dart';
import '../core/polar_utils.dart';
import '../polar_components.dart';
import '../util.dart';
import 'model.dart' show ChartOffset, appendOffsetOfLegend;
import 'polar_axis.dart' show PolarLayout, PolarOptions;
import 'polar_scene.dart' show PolarScene, computePolarScene;
import '../css_color.dart';

/// `PieSectorDataItem`: one sector with its data entry.
class PieSector {
  PieSector({
    required this.cx,
    required this.cy,
    required this.innerRadius,
    required this.outerRadius,
    required this.maxRadius,
    required this.startAngle,
    required this.endAngle,
    required this.midAngle,
    required this.middleRadius,
    required this.percent,
    required this.paddingAngle,
    required this.cornerRadius,
    required this.name,
    required this.value,
    required this.entry,
    required this.payload,
    required this.dataKey,
    required this.cell,
    required this.fill,
    required this.fillOpacity,
    required this.stroke,
    required this.strokeWidth,
    required this.strokeOpacity,
    required this.tooltipPosition,
    required this.tooltipPayload,
  });
  final double cx, cy, innerRadius, outerRadius, maxRadius;
  final double startAngle, endAngle, midAngle, middleRadius, percent, paddingAngle;
  final double? cornerRadius;

  /// `getValueByDataKey(entry, nameKey, index)`.
  final Object? name;

  /// The raw value at `dataKey` (0 when missing).
  final Object? value;

  /// The data entry as given.
  final Object? entry;

  /// The entry with its [Cell]'s props merged in (`entryWithCellInfo`).
  final Object? payload;
  final Object dataKey;
  final Cell? cell;
  final Color? fill;
  final double? fillOpacity;
  final Color? stroke;
  final double? strokeWidth;
  final double? strokeOpacity;
  final Offset tooltipPosition;

  /// The sector's one tooltip row (`tooltipPayload`).
  final TooltipPayloadEntry tooltipPayload;

  PieSector withAngles(double startAngle, double endAngle) => PieSector(
        cx: cx,
        cy: cy,
        innerRadius: innerRadius,
        outerRadius: outerRadius,
        maxRadius: maxRadius,
        startAngle: startAngle,
        endAngle: endAngle,
        midAngle: midAngle,
        middleRadius: middleRadius,
        percent: percent,
        paddingAngle: paddingAngle,
        cornerRadius: cornerRadius,
        name: name,
        value: value,
        entry: entry,
        payload: payload,
        dataKey: dataKey,
        cell: cell,
        fill: fill,
        fillOpacity: fillOpacity,
        stroke: stroke,
        strokeWidth: strokeWidth,
        strokeOpacity: strokeOpacity,
        tooltipPosition: tooltipPosition,
        tooltipPayload: tooltipPayload,
      );

  @override
  bool operator ==(Object other) =>
      other is PieSector &&
      other.cx == cx &&
      other.cy == cy &&
      other.innerRadius == innerRadius &&
      other.outerRadius == outerRadius &&
      other.startAngle == startAngle &&
      other.endAngle == endAngle &&
      other.cornerRadius == cornerRadius &&
      other.fill == fill &&
      other.stroke == stroke &&
      other.cell == cell &&
      identical(other.entry, entry);
  @override
  int get hashCode => Object.hash(cx, cy, innerRadius, outerRadius, startAngle, endAngle);
}

/// A Pie as the store sees it.
class PieModel {
  PieModel(this.id, this.settings, this.displayedData, this.sectors);
  final String id;
  final Pie settings;

  /// `selectDisplayedData`: the Pie's own data, else the chart's, else its Cells.
  final List<Object?>? displayedData;

  /// `selectPieSectors`: null without data or when every value is 0.
  final List<PieSector>? sectors;
}

class PolarModel {
  PolarModel({
    required this.size,
    required this.chartName,
    required this.chartData,
    required this.offset,
    required this.pies,
    required this.tooltipSettings,
    this.scene,
    this.dataStartIndex = 0,
    this.endIndexOverride,
  });
  final Size size;
  final String chartName;
  final List<Object?> chartData;
  final ChartOffset offset;
  final List<PieModel> pies;
  final Tooltip? tooltipSettings;

  /// Radars, RadialBars and polar axes; null for a chart without polar options.
  final PolarScene? scene;

  /// `selectChartViewBox`.
  Rect get viewBox => offset.plotArea;

  /// `chartDataSlice` indexes: the whole chart data.
  final int dataStartIndex;
  /// The Brush end index when it was set; else the last datum.
  final int? endIndexOverride;
  int get dataEndIndex => endIndexOverride ?? (chartData.isEmpty ? 0 : chartData.length - 1);

  /// `selectTooltipDisplayedData` (combineDisplayedData): every item's own
  /// data, concatenated, else the chart data.
  late final List<Object?> tooltipDisplayedData = () {
    final itemsData = [for (final p in pies) ...?p.settings.data];
    return itemsData.isNotEmpty ? itemsData : jsSlice(chartData, dataStartIndex, dataEndIndex + 1);
  }();
}

/// Stable ids for Pies: explicit `id`, else position among the chart's Pies.
List<(String, Pie)> collectPies(List<RechartsElement> children) {
  var i = 0;
  return [
    for (final c in children)
      if (c is Pie) (c.id ?? 'recharts-pie-${i++}', c),
  ];
}

PolarModel computePolarModel({
  required String chartName,
  required Size size,
  required List<Object?> data,
  required List<RechartsElement> children,
  Margin margin = const Margin.all(5),
  Size legendSize = Size.zero,
  PolarLayout layout = PolarLayout.radial,
  PolarOptions? options,
  StackOffset stackOffset = StackOffset.none,
  bool reverseStackOrder = false,
  Object barGap = 4,
  Object barCategoryGap = '10%',
  Object? barSize,
  double? maxBarSize,
  int dataStartIndex = 0,
  int? dataEndIndex,
}) {
  final legend = children.whereType<Legend>().firstOrNull;
  final off = appendOffsetOfLegend(
      (top: margin.top, right: margin.right, bottom: margin.bottom, left: margin.left), legend, legendSize);
  final offset = ChartOffset(
    top: off.top,
    right: off.right,
    bottom: off.bottom,
    left: off.left,
    width: math.max(size.width - off.left - off.right, 0),
    height: math.max(size.height - off.top - off.bottom, 0),
  );
  return PolarModel(
    size: size,
    chartName: chartName,
    chartData: data,
    offset: offset,
    tooltipSettings: children.whereType<Tooltip>().firstOrNull,
    dataStartIndex: dataStartIndex,
    endIndexOverride: dataEndIndex,
    scene: options == null
        ? null
        : computePolarScene(
            chartName: chartName,
            data: data,
            children: children,
            layout: layout,
            options: options,
            size: size,
            offset: off,
            stackOffset: stackOffset,
            reverseStackOrder: reverseStackOrder,
            barGap: barGap,
            barCategoryGap: barCategoryGap,
            barSize: barSize,
            maxBarSize: maxBarSize,
            dataStartIndex: dataStartIndex,
            dataEndIndex: dataEndIndex),
    pies: [
      for (final (id, pie) in collectPies(children))
        () {
          final displayed = pieDisplayedData(pie, data);
          return PieModel(
            id,
            pie,
            displayed,
            displayed == null ? null : computePieSectors(pie, displayed, pie.cells, offset, id: id),
          );
        }(),
    ],
  );
}

/// `selectDisplayedData`.
List<Object?>? pieDisplayedData(Pie pie, List<Object?> chartData) {
  List<Object?> displayed = pie.data != null && pie.data!.isNotEmpty ? pie.data! : chartData;
  final cells = pie.cells;
  if (displayed.isEmpty && cells.isNotEmpty) displayed = [for (final c in cells) _cellProps(c)];
  return displayed;
}

Map<String, Object> _cellProps(Cell c) => {
      'fill': ?c.fill,
      'fillOpacity': ?c.fillOpacity,
      'stroke': ?c.stroke,
      'strokeWidth': ?c.strokeWidth,
    };

/// `parseCoordinateOfPie`.
({double cx, double cy, double innerRadius, double outerRadius, double maxRadius}) parseCoordinateOfPie(
    Pie pie, ChartOffset offset, Object? dataPoint) {
  final width = offset.width, height = offset.height;
  final maxPieRadius = pie.maxRadius ?? getMaxRadius(width, height);
  final outer = pie.outerRadius;
  return (
    cx: offset.left + getPercentValue(pie.cx, width, width / 2),
    cy: offset.top + getPercentValue(pie.cy, height, height / 2),
    innerRadius: getPercentValue(pie.innerRadius, maxPieRadius, 0),
    outerRadius: getPercentValue(
        outer is Function ? (outer as dynamic)(dataPoint) : outer, maxPieRadius, maxPieRadius * 0.8),
    maxRadius: pie.maxRadius ?? math.sqrt(width * width + height * height) / 2,
  );
}

/// `parseDeltaAngle`.
double parseDeltaAngle(double startAngle, double endAngle) =>
    mathSign(endAngle - startAngle) * math.min((endAngle - startAngle).abs(), 360);

Object? _prop(Object? entry, String key) => entry is Map ? entry[key] : null;

/// `computePieSectors`.
List<PieSector>? computePieSectors(Pie pie, List<Object?> displayedData, List<Cell> cells, ChartOffset offset,
    {required String id}) {
  final dataKey = pie.dataKey, nameKey = pie.nameKey;
  final minAngle = pie.minAngle.abs();
  final deltaAngle = parseDeltaAngle(pie.startAngle, pie.endAngle);
  final absDeltaAngle = deltaAngle.abs();
  // A null value counts as 0, like a missing one.
  bool notZero(Object? v) => isNumber(v) && v != 0;
  final values = [for (final e in displayedData) getValueByDataKey(e, dataKey, 0)];
  final notZeroItemCount = values.where(notZero).length;
  final paddingAngle = notZeroItemCount <= 1 ? 0.0 : pie.paddingAngle;
  final firstNonZeroIndex = values.indexWhere(notZero);
  final totalPaddingAngle = (absDeltaAngle >= 360 ? notZeroItemCount : notZeroItemCount - 1) * paddingAngle;
  final sum = values.fold<double>(0, (r, v) => r + (isNumber(v) ? (v as num).toDouble() : 0));
  double numberOr0(Object? v) => isNumber(v) ? (v as num).toDouble() : 0;
  final needsMinAngleAdjustment = minAngle > 0 &&
      sum > 0 &&
      values.any((v) => notZero(v) && numberOr0(v) / sum * absDeltaAngle < minAngle);
  final effectiveMinAngle = needsMinAngleAdjustment ? minAngle : 0.0;
  final realTotalAngle = absDeltaAngle - notZeroItemCount * effectiveMinAngle - totalPaddingAngle;
  if (!(sum > 0)) return null;

  final sign = mathSign(deltaAngle);
  final cornerRadius = switch (pie.cornerRadius) {
    final num n => n.toDouble(),
    final String s => double.tryParse(RegExp(r'^\s*[-+]?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?').stringMatch(s) ?? '') ?? double.nan,
    _ => null,
  };
  final sectors = <PieSector>[];
  for (var i = 0; i < displayedData.length; i++) {
    final entry = displayedData[i];
    final val = values[i];
    final name = getValueByDataKey(entry, nameKey, i);
    final coordinate = parseCoordinateOfPie(pie, offset, entry);
    final percent = numberOr0(val) / sum;
    final cell = i < cells.length ? cells[i] : null;
    final payload = cell == null || entry is! Map ? entry : {...entry, ..._cellProps(cell)};
    final entryFill = _prop(payload, 'fill');
    final sectorColor = cssFillOf(entryFill) ?? pie.fill;
    // Leading zero values take no space, so the first visible sector gets no padding in front of it.
    final hasPadding = notZero(val) && !(i > 0 && i == firstNonZeroIndex);
    final startAngle = i == 0 ? pie.startAngle : sectors.last.endAngle + sign * paddingAngle * (hasPadding ? 1 : 0);
    final endAngle = startAngle + sign * ((notZero(val) ? effectiveMinAngle : 0) + percent * realTotalAngle);
    final midAngle = (startAngle + endAngle) / 2;
    final middleRadius = (coordinate.innerRadius + coordinate.outerRadius) / 2;
    final entryStroke = _prop(payload, 'stroke');
    double? num2(String k, double? fallback) => switch (_prop(payload, k)) { final num n => n.toDouble(), _ => fallback };
    sectors.add(PieSector(
      cx: coordinate.cx,
      cy: coordinate.cy,
      innerRadius: coordinate.innerRadius,
      outerRadius: coordinate.outerRadius,
      maxRadius: coordinate.maxRadius,
      startAngle: startAngle,
      endAngle: endAngle,
      midAngle: midAngle,
      middleRadius: middleRadius,
      percent: percent,
      paddingAngle: hasPadding ? sign * paddingAngle : 0,
      cornerRadius: cornerRadius,
      name: name,
      value: val,
      entry: entry,
      payload: payload,
      dataKey: dataKey,
      cell: cell,
      fill: cssFillOf(entryFill) ?? pie.fill,
      fillOpacity: num2('fillOpacity', pie.fillOpacity),
      stroke: cssStrokeOf(entryStroke) ?? pie.stroke,
      strokeWidth: num2('strokeWidth', pie.strokeWidth),
      strokeOpacity: num2('strokeOpacity', pie.strokeOpacity),
      tooltipPosition: polarToCartesian(coordinate.cx, coordinate.cy, middleRadius, midAngle),
      tooltipPayload: TooltipPayloadEntry(
        dataKey: dataKey,
        name: name == null ? null : jsString(name),
        value: getValueByDataKey(payload, dataKey),
        payload: payload,
        color: sectorColor,
        fill: sectorColor,
        stroke: pie.stroke,
        hide: pie.hide,
        type: pie.tooltipType,
        formatter: pie.formatter,
      ),
    ));
  }
  return sectors;
}

/// `defaultPieAnimateItems`: sectors grow from the first one's start angle,
/// each placed after the previous one.
List<PieSector> interpolatePieSectors(List<AnimationItem<PieSector>>? items, double t) {
  if (items == null) return const [];
  final out = <PieSector>[];
  final first = items.where((i) => i is! Removed<PieSector>).firstOrNull;
  var curAngle = switch (first) {
    Matched(:final next) || Added(:final next) => next.startAngle,
    _ => 0.0,
  };
  for (var index = 0; index < items.length; index++) {
    final item = items[index];
    switch (item) {
      case Removed():
        continue;
      case Matched(:final prev, :final next):
        // The padding changes when a value crosses zero; it eases like the arc.
        final paddingAngle = index > 0 ? interpolate(prev.paddingAngle, next.paddingAngle, t)! : 0;
        final angle = interpolate(prev.endAngle - prev.startAngle, next.endAngle - next.startAngle, t)!;
        final latest = next.withAngles(curAngle + paddingAngle, curAngle + angle + paddingAngle);
        out.add(latest);
        curAngle = latest.endAngle;
      case Added(:final next):
        final paddingAngle = index > 0 ? next.paddingAngle : 0;
        final deltaAngle = interpolate(0, next.endAngle - next.startAngle, t)!;
        final latest = next.withAngles(curAngle + paddingAngle, curAngle + deltaAngle + paddingAngle);
        out.add(latest);
        curAngle = latest.endAngle;
    }
  }
  return out;
}

/// `selectPieLegend` for every Pie, sorted by the Legend's `itemSorter`.
List<LegendPayload> pieLegendPayload(PolarModel m, Legend legend) =>
    sortLegendPayload([for (final p in m.pies) ...pieLegendEntries(p)], legend);

/// The legend rows one Pie registers (`selectPieLegend`).
List<LegendPayload> pieLegendEntries(PieModel p) {
  final payload = <LegendPayload>[];
  {
    final pie = p.settings, cells = pie.cells;
    for (final (i, entry) in (p.displayedData ?? const <Object?>[]).indexed) {
      final name = getValueByDataKey(entry, pie.nameKey, pie.name);
      final cellFill = i < cells.length ? cells[i].fill : null;
      final entryFill = _prop(entry, 'fill');
      payload.add(LegendPayload(
        value: name != null ? jsString(name) : (pie.dataKey is String ? pie.dataKey as String : null),
        type: pie.legendType,
        color: cellFill ?? (entry is Map && entry.containsKey('fill') ? cssFillOf(entryFill) : pie.fill),
        dataKey: pie.dataKey,
      ));
    }
  }
  return payload;
}

/// The Legend's `itemSorter` applied to [payload].
List<LegendPayload> sortLegendPayload(List<LegendPayload> payload, Legend legend) {
  final sorter = legend.itemSorter;
  if (sorter == 'value') return sortByKey(payload, (p) => p.value);
  if (sorter == 'dataKey') return sortByKey(payload, (p) => p.dataKey is Function ? null : p.dataKey);
  if (sorter is Object? Function(LegendPayload)) return sortByKey(payload, sorter);
  return payload;
}

/// `getActiveShapeFill`: an object `activeShape` with a fill recolors every tooltip row.
Color? activeShapeFill(Pie pie) => pie.activeShape is SectorStyle ? (pie.activeShape as SectorStyle).fill : null;

/// `combineTooltipPayload` for the Pies [pies] (their tooltip entry settings)
/// at [activeIndex]: each Pie's `dataDefinedOnItem` sliced like the chart
/// data, then the sector at the index.
List<TooltipPayloadEntry> pieTooltipPayload(PolarModel m, Iterable<PieModel> pies, int? activeIndex) {
  if (activeIndex == null) return const [];
  final (sliceStart, sliceEnd) = getBrushSliceIndexes(m.chartData, m.dataStartIndex, m.dataEndIndex);
  final out = <TooltipPayloadEntry>[];
  for (final p in pies) {
    final sectors = getSliced(p.sectors ?? const <PieSector>[], sliceStart, sliceEnd);
    if (activeIndex < 0 || activeIndex >= sectors.length) continue;
    final e = sectors[activeIndex].tooltipPayload;
    final fill = activeShapeFill(p.settings);
    out.add(fill == null
        ? e
        : TooltipPayloadEntry(
            dataKey: e.dataKey,
            name: e.name,
            value: e.value,
            payload: e.payload,
            color: fill,
            fill: fill,
            stroke: e.stroke,
            hide: e.hide,
            type: e.type,
            formatter: e.formatter,
          ));
  }
  return out;
}
