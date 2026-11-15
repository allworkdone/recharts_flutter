// The polar half of the chart store beyond Pie: the polar items and axes of a
// chart (RadarChart, RadialBarChart), the axis tooltip
// (combineActivePolarProps in src/state/selectors/selectors.ts,
// calculateActiveTickIndex and getActivePolarCoordinate in
// src/util/getActiveCoordinate.ts, calculatePolarTooltipPos in ChartUtils.ts),
// the tooltip payloads of Radar and RadialBar (combineTooltipPayload) and
// their legend payloads.

import 'dart:math' as math;
import 'dart:ui';

import '../components.dart';
import '../core/polar_utils.dart';
import '../polar_axes.dart';
import '../util.dart';
import 'axis.dart' show getBandSizeOfAxis;
import 'get_ticks.dart';
import 'model.dart' show calculateActiveTickIndex;
import 'polar_axis.dart';
import 'polar_items.dart';

/// `PolarCoordinate`: a tooltip coordinate with its polar parts.
class PolarCoordinate {
  const PolarCoordinate(this.offset, this.angle, this.radius, this.viewBox);
  final Offset offset;
  final double angle, radius;

  /// cx, cy, radii and angles of the chart's polar view box.
  final PolarViewBox viewBox;
}

/// Polar items and axes of one chart.
class PolarScene {
  PolarScene({
    required this.layout,
    required this.options,
    required this.geometry,
    required this.items,
    required this.radars,
    required this.radialBars,
    required this.angleAxes,
    required this.radiusAxes,
    required this.tooltipAxis,
    required this.grids,
    required this.angleAxisElements,
    required this.radiusAxisElements,
    this.dataStartIndex = 0,
    this.dataEndIndex = 0,
  });
  final PolarLayout layout;
  final PolarOptions options;
  final PolarGeometry geometry;
  final List<PolarItem> items;
  final List<RadarModel> radars;
  final List<RadialBarModel> radialBars;
  final Map<Object, PolarAxisRuntime> angleAxes, radiusAxes;

  /// `selectTooltipAxis`: the angle axis of a centric chart, else the radius axis.
  final PolarAxisRuntime tooltipAxis;
  final List<PolarGrid> grids;
  final List<PolarAngleAxis> angleAxisElements;
  final List<PolarRadiusAxis> radiusAxisElements;

  /// The Brush range (`chartDataSlice`); only RadialBar sectors and the tooltip data follow it.
  final int dataStartIndex, dataEndIndex;

  PolarViewBox get viewBox => geometry.viewBox;

  late final List<TickItem> tooltipTicks = polarTooltipTicks(tooltipAxis, layout) ?? const [];

  /// `selectTooltipAxisType`.
  bool get tooltipOnAngle => layout == PolarLayout.centric;

  /// The axis tooltip needs a tooltip axis with a scale.
  bool get hasTooltipScale => tooltipAxis.scale != null;
}

PolarScene computePolarScene({
  required String chartName,
  required List<Object?> data,
  required List<RechartsElement> children,
  required PolarLayout layout,
  required PolarOptions options,
  required Size size,
  required ({double top, double right, double bottom, double left}) offset,
  StackOffset stackOffset = StackOffset.none,
  bool reverseStackOrder = false,
  Object barGap = 4,
  Object barCategoryGap = '10%',
  Object? barSize,
  double? maxBarSize,
  int dataStartIndex = 0,
  int? dataEndIndex,
}) {
  final end = dataEndIndex ?? (data.isEmpty ? 0 : data.length - 1);
  final geometry = polarGeometry(options, size, offset);
  // Registration order is child order; ids are the explicit `id`, else the position among the
  // chart's elements of a kind. Children pair with models by position: equal `const` elements are one object.
  var radarCount = 0, barCount = 0;
  final items = [
    for (final c in children)
      if (c is Radar)
        PolarItem.radar(c.id ?? 'recharts-radar-${radarCount++}', c)
      else if (c is RadialBar)
        PolarItem.radialBar(c.id ?? 'recharts-radial-bar-${barCount++}', c),
  ];

  final angleElements = children.whereType<PolarAngleAxis>().toList();
  final radiusElements = children.whereType<PolarRadiusAxis>().toList();
  final grids = children.whereType<PolarGrid>().toList();
  final tooltipAxisId = children.whereType<Tooltip>().firstOrNull?.axisId ?? 0;

  final ctx = PolarAxisContext(
    layout: layout,
    chartName: chartName,
    chartData: data,
    items: items,
    options: options,
    maxRadius: geometry.maxRadius,
    innerRadius: geometry.innerRadius,
    outerRadius: geometry.outerRadius,
    stackOffset: stackOffset,
  );

  // Declared axes, then the ids that items, grids and the tooltip refer to.
  final angleIds = <Object>{for (final a in angleElements) a.angleAxisId, for (final i in items) i.angleAxisId, for (final g in grids) g.angleAxisId};
  final radiusIds = <Object>{for (final a in radiusElements) a.radiusAxisId, for (final i in items) i.radiusAxisId, for (final g in grids) g.radiusAxisId};
  if (layout == PolarLayout.centric) {
    angleIds.add(tooltipAxisId);
  } else {
    radiusIds.add(tooltipAxisId);
  }
  if (angleIds.isEmpty) angleIds.add(0);
  if (radiusIds.isEmpty) radiusIds.add(0);

  final angleAxes = <Object, PolarAxisRuntime>{
    for (final id in angleIds)
      id: () {
        final el = angleElements.where((a) => a.angleAxisId == id).lastOrNull;
        return computePolarAxis(angleAxisSettings(layout, id, el), true, el, ctx);
      }(),
  };
  final radiusAxes = <Object, PolarAxisRuntime>{
    for (final id in radiusIds)
      id: () {
        final el = radiusElements.where((a) => a.radiusAxisId == id).lastOrNull;
        return computePolarAxis(radiusAxisSettings(layout, id, el), false, el, ctx);
      }(),
  };
  final tooltipAxis = layout == PolarLayout.centric ? angleAxes[tooltipAxisId]! : radiusAxes[tooltipAxisId]!;

  // selectRadarPoints
  final radars = <RadarModel>[];
  final vb = geometry.viewBox;
  for (final item in items.where((i) => i.isRadar)) {
    final angleAxis = angleAxes[item.angleAxisId], radiusAxis = radiusAxes[item.radiusAxisId];
    RadarComposed? composed;
    if (angleAxis?.scale != null && radiusAxis?.scale != null && item.dataKey != null) {
      final bandSize = isPolarCategorical(layout, false)
          ? getBandSizeOfAxis(radiusAxis!.scale, radiusAxis.ticks, false)
          : getBandSizeOfAxis(angleAxis!.scale, angleAxis.ticks, false);
      if (bandSize != null) {
        composed = computeRadarPoints(
            radiusAxis: radiusAxis!,
            angleAxis: angleAxis!,
            cx: vb.cx,
            cy: vb.cy,
            displayedData: data,
            dataKey: item.dataKey,
            bandSize: bandSize);
      }
    }
    radars.add(RadarModel(item.id, item.radar!, composed));
  }

  final barContext = RadialBarContext(
    layout: layout,
    items: items,
    chartData: data,
    viewBox: vb,
    angleAxes: angleAxes,
    radiusAxes: radiusAxes,
    stackOffset: stackOffset,
    reverseStackOrder: reverseStackOrder,
    dataStartIndex: dataStartIndex,
    dataEndIndex: end,
    barGap: barGap,
    barCategoryGap: barCategoryGap,
    rootBarSize: barSize,
    rootMaxBarSize: maxBarSize,
    tooltipAxis: tooltipAxis,
  );
  final radialBars = [
    for (final item in items.where((i) => i.isRadialBar))
      RadialBarModel(item.id, item.radialBar!, computeRadialBarSectors(item, barContext)),
  ];

  return PolarScene(
    layout: layout,
    options: options,
    geometry: geometry,
    items: items,
    radars: radars,
    radialBars: radialBars,
    angleAxes: angleAxes,
    radiusAxes: radiusAxes,
    tooltipAxis: tooltipAxis,
    grids: grids,
    angleAxisElements: angleElements,
    radiusAxisElements: radiusElements,
    dataStartIndex: dataStartIndex,
    dataEndIndex: end,
  );
}

// ---------------------------------------------------------------------------
// Axis tooltip

/// `ActiveTooltipProps` of a polar pointer.
class PolarActiveProps {
  const PolarActiveProps(this.activeIndex, this.coordinate);
  final int activeIndex;
  final PolarCoordinate coordinate;
}

/// The circular branch of `calculateActiveTickIndex` (an angle axis spanning a full turn).
int calculateActiveAngleTickIndex(double coordinate, List<TickItem> unsorted, List<double> range) {
  final len = unsorted.length;
  final span = range[1] - range[0];
  bool isInside(double lower, double upper, bool inclusiveLower) => [coordinate, coordinate + span, coordinate - span]
      .any((c) => (inclusiveLower ? c >= lower : c > lower) && c <= upper);
  for (var i = 0; i < len; i++) {
    final before = i > 0 ? unsorted[i - 1].coordinate : unsorted[len - 1].coordinate;
    final cur = unsorted[i].coordinate;
    final after = i >= len - 1 ? unsorted[0].coordinate : unsorted[i + 1].coordinate;
    if (mathSign(cur - before) != mathSign(after - cur)) {
      final double sameDirectionCoord;
      final double diff0, diff1;
      if (mathSign(after - cur) == mathSign(range[1] - range[0])) {
        sameDirectionCoord = after;
        final curInRange = cur + range[1] - range[0];
        diff0 = math.min(curInRange, (curInRange + before) / 2);
        diff1 = math.max(curInRange, (curInRange + before) / 2);
      } else {
        sameDirectionCoord = before;
        final afterInRange = after + range[1] - range[0];
        diff0 = math.min(cur, (afterInRange + cur) / 2);
        diff1 = math.max(cur, (afterInRange + cur) / 2);
      }
      final same0 = math.min(cur, (sameDirectionCoord + cur) / 2), same1 = math.max(cur, (sameDirectionCoord + cur) / 2);
      if (isInside(same0, same1, false) || isInside(diff0, diff1, true)) return unsorted[i].index;
    } else {
      final minValue = math.min(before, after), maxValue = math.max(before, after);
      if (isInside((minValue + cur) / 2, (maxValue + cur) / 2, false)) return unsorted[i].index;
    }
  }
  return -1;
}

/// `combineActivePolarProps` for a pointer relative to the chart.
PolarActiveProps? polarActivePropsFromPointer(PolarScene s, Offset pointer) {
  if (!s.hasTooltipScale) return null;
  final rx = jsRound(pointer.dx), ry = jsRound(pointer.dy);
  final rangeObj = inRangeOfSector(Offset(rx, ry), s.viewBox);
  if (rangeObj == null) return null;
  final pos = s.tooltipOnAngle ? rangeObj.angle : rangeObj.radius;
  final ticks = s.tooltipTicks;
  final ordered = sortByKey(ticks, (t) => t.coordinate);
  final axis = s.tooltipAxis;
  final range = axis.rangeWithReverse;
  final int activeIndex;
  if (ordered.length <= 1) {
    activeIndex = 0;
  } else if (s.tooltipOnAngle && ((range[1] - range[0]).abs() - 360).abs() <= 1e-6) {
    activeIndex = calculateActiveAngleTickIndex(pos, ticks, range);
  } else {
    activeIndex = calculateActiveTickIndex(pos, ordered);
  }
  final vb = s.viewBox;
  final entry = ticks.where((t) => t.index == activeIndex).firstOrNull;
  if (entry == null) {
    return PolarActiveProps(activeIndex, PolarCoordinate(Offset.zero, 0, 0, vb));
  }
  final double angle, radius;
  if (s.layout == PolarLayout.centric) {
    angle = entry.coordinate;
    radius = rangeObj.radius;
  } else {
    radius = entry.coordinate;
    angle = rangeObj.angle;
  }
  return PolarActiveProps(
      activeIndex, PolarCoordinate(polarToCartesian(vb.cx, vb.cy, radius, angle), angle, radius, vb));
}

/// `combineActiveLabel`.
Object? polarActiveLabel(PolarScene s, int? activeIndex) {
  if (activeIndex == null || activeIndex < 0) return null;
  final ticks = s.tooltipTicks;
  return activeIndex < ticks.length ? ticks[activeIndex].value : null;
}

/// `combineActiveTooltipIndex` for a polar chart.
int? combinePolarActiveIndex(PolarScene s, List<Object?> chartData, int? desiredIndex) {
  if (desiredIndex == null) return null;
  chartData = getSliced(chartData, s.dataStartIndex, s.dataEndIndex);
  final upperLimit = chartData.isNotEmpty ? chartData.length - 1 : 1 << 30;
  final clamped = math.max(0, math.min(desiredIndex, upperLimit));
  if (clamped >= chartData.length) return clamped;
  final dataKey = s.tooltipAxis.settings.dataKey, domain = s.tooltipAxis.domain;
  if (domain != null && dataKey != null) {
    final value = getValueByDataKey(chartData[clamped], dataKey);
    if (value != null && domain.length == 2 && isWellBehavedNumber(domain[0]) && isWellBehavedNumber(domain[1])) {
      final n = jsNumber(value);
      if (!n.isFinite) return null;
      final a = (domain[0] as num).toDouble(), b = (domain[1] as num).toDouble();
      if (n < math.min(a, b) || n > math.max(a, b)) return null;
    }
  }
  return clamped;
}

/// `combineTooltipPayload` over the polar items [ids] (every item by default,
/// in registration order) at [activeIndex]. Only the [axis] event type looks
/// entries up by the tooltip axis' dataKey.
List<TooltipPayloadEntry> polarTooltipPayload(PolarScene s, List<Object?> chartData, int? activeIndex,
    {Set<String>? ids, bool axis = true}) {
  if (activeIndex == null) return const [];
  final axisDataKey = axis ? s.tooltipAxis.settings.dataKey : null;
  final activeLabel = polarActiveLabel(s, activeIndex);
  chartData = getSliced(chartData, s.dataStartIndex, s.dataEndIndex);
  Object? at(List<Object?> l) => activeIndex >= 0 && activeIndex < l.length ? l[activeIndex] : null;
  final out = <TooltipPayloadEntry>[];
  for (final item in s.items) {
    if (ids != null && !ids.contains(item.id)) continue;
    if (item.isRadar) {
      final r = item.radar!;
      Object? payload;
      if (axisDataKey != null) {
        payload = chartData.where((e) => getValueByDataKey(e, axisDataKey) == activeLabel).firstOrNull;
      }
      payload ??= at(chartData);
      out.add(TooltipPayloadEntry(
        dataKey: r.dataKey,
        name: tooltipNameProp(r.name, r.dataKey),
        value: getValueByDataKey(payload, r.dataKey),
        payload: payload,
        color: legendItemColor(r.stroke, r.fill),
        fill: r.fill,
        stroke: r.stroke,
        unit: '',
        hide: r.hide,
        type: r.tooltipType,
      ));
    } else {
      final b = item.radialBar!;
      // `dataDefinedOnItem` is the sectors, which are already sliced; getSliced slices them again.
      final sectors = getSliced(s.radialBars.firstWhere((m) => m.id == item.id).sectors, s.dataStartIndex, s.dataEndIndex);
      var sector = activeIndex >= 0 && activeIndex < sectors.length ? sectors[activeIndex] : null;
      // `dataDefinedOnItem` is the sectors, searched by index (tooltipAxis dataKey ignored for objects)
      if (axisDataKey != null && sector != null) {
        sector = sectors.where((e) => getValueByDataKey(e.asPayload, axisDataKey) == activeLabel).firstOrNull ?? sector;
      }
      final payload = sector?.asPayload;
      out.add(TooltipPayloadEntry(
        dataKey: b.dataKey,
        name: tooltipNameProp(b.name, b.dataKey),
        value: getValueByDataKey(payload, b.dataKey),
        payload: payload,
        color: sector == null ? b.fill : radialBarEntryColor(b, sector.entry, sector.cell) ?? b.fill,
        fill: b.fill,
        stroke: b.stroke,
        unit: '',
        hide: b.hide,
        type: b.tooltipType,
        formatter: b.formatter,
      ));
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Legend

/// `computeLegendPayloadFromRadarSectors`.
LegendPayload radarLegendEntry(Radar r) => LegendPayload(
      value: tooltipNameProp(r.name, r.dataKey),
      type: r.legendType,
      color: legendItemColor(r.stroke, r.fill),
      dataKey: r.dataKey,
      inactive: r.hide,
    );

/// `selectRadialBarLegendPayload`: one entry per data row, in the color of its sector.
List<LegendPayload> radialBarLegendPayload(RadialBar b, List<Object?> chartData) {
  final cells = b.cells;
  return [
    for (final (i, entry) in chartData.indexed)
      LegendPayload(
        value: switch (entry is Map ? entry['name'] : null) { null => null, final v => jsString(v) },
        type: b.legendType,
        color: radialBarEntryColor(b, entry, i < cells.length ? cells[i] : null),
        dataKey: null,
      ),
  ];
}
