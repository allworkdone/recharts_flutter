// Radar and RadialBar as the store sees them: src/state/selectors/
// radarSelectors.ts and computeRadarPoints (src/polar/Radar.tsx);
// radialBarSelectors.ts and computeRadialBarDataItems (src/polar/RadialBar.tsx);
// their legend payloads and tooltip entry settings; defaultRadarAnimateItems
// and defaultRadialBarAnimateItems.

import 'dart:math' as math;
import 'dart:ui';

import '../animation.dart';
import '../components.dart';
import '../core/polar_utils.dart';
import '../polar_axes.dart';
import '../render/sector.dart';
import '../util.dart';
import 'axis.dart';
import 'get_ticks.dart';
import 'model.dart' show BarPosition, barSizeList, getBarPositions, truncateByDomain;
import 'polar_axis.dart';

// ---------------------------------------------------------------------------
// Radar

/// `RadarPoint`.
class RadarPoint {
  RadarPoint({
    required this.x,
    required this.y,
    required this.cx,
    required this.cy,
    required this.angle,
    required this.radius,
    required this.value,
    required this.payload,
    required this.name,
  });
  final double x, y, cx, cy, angle, radius;
  final Object? value, payload, name;

  RadarPoint at(double x, double y) =>
      RadarPoint(x: x, y: y, cx: cx, cy: cy, angle: angle, radius: radius, value: value, payload: payload, name: name);

  @override
  bool operator ==(Object other) =>
      other is RadarPoint &&
      other.x == x &&
      other.y == y &&
      other.cx == cx &&
      other.cy == cy &&
      other.angle == angle &&
      other.radius == radius &&
      identical(other.payload, payload);
  @override
  int get hashCode => Object.hash(x, y, cx, cy, angle, radius);
}

/// `RadarComposedData`.
typedef RadarComposed = ({List<RadarPoint> points, List<RadarPoint> baseLinePoints, bool isRange});

/// `computeRadarPoints`.
RadarComposed computeRadarPoints({
  required PolarAxisRuntime radiusAxis,
  required PolarAxisRuntime angleAxis,
  required double cx,
  required double cy,
  required List<Object?> displayedData,
  required Object? dataKey,
  required double bandSize,
}) {
  var isRange = false;
  final points = <RadarPoint>[];
  final angleBandSize = angleAxis.type != AxisDomainType.number ? bandSize : 0.0;
  final radiusScale = radiusAxis.scale!, angleScale = angleAxis.scale!;
  for (var i = 0; i < displayedData.length; i++) {
    final entry = displayedData[i];
    final name = getValueByDataKey(entry, angleAxis.settings.dataKey, i);
    final value = getValueByDataKey(entry, dataKey);
    final angle = (angleScale.map(name) ?? 0) + angleBandSize;
    final pointValue = value is List ? value.lastOrNull : value;
    final radius = pointValue == null ? 0.0 : (radiusScale.map(pointValue) ?? 0);
    if (value is List && value.length >= 2) isRange = true;
    final p = polarToCartesian(cx, cy, radius, angle);
    points.add(RadarPoint(
        x: p.dx, y: p.dy, cx: cx, cy: cy, angle: angle, radius: radius, value: value, payload: entry, name: name));
  }
  final baseLinePoints = <RadarPoint>[];
  if (isRange) {
    for (final point in points) {
      if (point.value is List) {
        final baseValue = (point.value as List).firstOrNull;
        final radius = baseValue == null ? 0.0 : (radiusScale.map(baseValue) ?? 0);
        final p = polarToCartesian(cx, cy, radius, point.angle);
        baseLinePoints.add(RadarPoint(
            x: p.dx,
            y: p.dy,
            cx: cx,
            cy: cy,
            angle: point.angle,
            radius: radius,
            value: point.value,
            payload: point.payload,
            name: point.name));
      } else {
        baseLinePoints.add(point);
      }
    }
  }
  return (points: points, baseLinePoints: baseLinePoints, isRange: isRange);
}

/// `defaultRadarAnimateItems`: new points grow from the center.
List<RadarPoint> interpolateRadarPoints(List<AnimationItem<RadarPoint>>? items, double t) {
  if (items == null) return const [];
  if (t == 1) {
    return [
      for (final i in items)
        if (i is Matched<RadarPoint>) i.next else if (i is Added<RadarPoint>) i.next,
    ];
  }
  return [
    for (final item in items)
      switch (item) {
        Removed() => null,
        Matched(:final prev, :final next) =>
          next.at(interpolate(prev.x, next.x, t)!, interpolate(prev.y, next.y, t)!),
        Added(:final next) => next.at(interpolate(next.cx, next.x, t)!, interpolate(next.cy, next.y, t)!),
      },
  ].nonNulls.toList();
}

/// A Radar as the store sees it.
class RadarModel {
  RadarModel(this.id, this.settings, this.composed);
  final String id;
  final Radar settings;

  /// Null when the scales are not ready (`selectRadarPoints` is undefined).
  final RadarComposed? composed;
  List<RadarPoint>? get points => composed?.points;
}

/// `getLegendItemColor`.
Color? legendItemColor(Color? stroke, Color? fill) => stroke ?? fill;

/// `getTooltipNameProp`.
String? tooltipNameProp(Object? name, Object? dataKey) =>
    name != null ? jsString(name) : (dataKey is String ? dataKey : null);

// ---------------------------------------------------------------------------
// RadialBar

/// `RadialBarDataItem`: a sector with the data entry's props spread over it.
class RadialBarSector {
  RadialBarSector({
    required this.cx,
    required this.cy,
    required this.innerRadius,
    required this.outerRadius,
    required this.startAngle,
    required this.endAngle,
    required this.value,
    required this.entry,
    required this.props,
    required this.background,
    required this.cell,
    required this.fill,
    required this.fillOpacity,
    required this.stroke,
    required this.strokeWidth,
    required this.strokeOpacity,
  });
  final double cx, cy, innerRadius, outerRadius, startAngle, endAngle;
  final Object? value;
  final Object? entry;

  /// The entry's props with its [Cell]'s merged over them.
  final Map<String, Object?> props;

  /// The track behind the sector (radial layout only).
  final SectorGeometry? background;
  final Cell? cell;
  final Color? fill;
  final double? fillOpacity;
  final Color? stroke;
  final double? strokeWidth;
  final double? strokeOpacity;

  /// Whether the sector has finite geometry (a missing category coordinate leaves it NaN).
  bool get isFinite => innerRadius.isFinite && outerRadius.isFinite && startAngle.isFinite && endAngle.isFinite;

  RadialBarSector withAngles(double startAngle, double endAngle) => RadialBarSector(
        cx: cx,
        cy: cy,
        innerRadius: innerRadius,
        outerRadius: outerRadius,
        startAngle: startAngle,
        endAngle: endAngle,
        value: value,
        entry: entry,
        props: props,
        background: background,
        cell: cell,
        fill: fill,
        fillOpacity: fillOpacity,
        stroke: stroke,
        strokeWidth: strokeWidth,
        strokeOpacity: strokeOpacity,
      );

  /// The sector as the tooltip payload (`dataDefinedOnItem`) sees it: the entry's keys plus its own.
  Map<String, Object?> get asPayload => {
        ...props,
        'payload': entry,
        'value': value,
        'cx': cx,
        'cy': cy,
        'innerRadius': innerRadius,
        'outerRadius': outerRadius,
        'startAngle': startAngle,
        'endAngle': endAngle,
      };

  @override
  bool operator ==(Object other) =>
      other is RadialBarSector &&
      other.cx == cx &&
      other.cy == cy &&
      other.innerRadius == innerRadius &&
      other.outerRadius == outerRadius &&
      other.startAngle == startAngle &&
      other.endAngle == endAngle &&
      other.fill == fill &&
      other.stroke == stroke &&
      identical(other.entry, entry);
  @override
  int get hashCode => Object.hash(cx, cy, innerRadius, outerRadius, startAngle, endAngle);
}

/// `parseCornerRadius`: a string goes through `parseInt`.
double? parseCornerRadius(Object? cornerRadius) => switch (cornerRadius) {
      final num n => n.toDouble(),
      final String s => int.tryParse(RegExp(r'^\s*[-+]?\d+').stringMatch(s)?.trim() ?? '')?.toDouble(),
      _ => null,
    };

/// `getBaseValueOfBar`.
Object? baseValueOfBar(PolarAxisRuntime numericAxis) {
  final domain = numericAxis.scale!.domain;
  if (numericAxis.type == AxisDomainType.number) {
    final a = jsNumber(domain[0]), b = jsNumber(domain[1]);
    final minValue = math.min(a, b), maxValue = math.max(a, b);
    if (minValue <= 0 && maxValue >= 0) return 0;
    if (maxValue < 0) return maxValue;
    return minValue;
  }
  return domain.isEmpty ? null : domain[0];
}

/// `getCateCoordinateOfBar`.
double? _cateCoordinateOfBar(
    PolarAxisRuntime axis, List<TickItem> ticks, double offset, double bandSize, Object? entry, int index) {
  if (axis.type == AxisDomainType.category) {
    return index < ticks.length ? ticks[index].coordinate + offset : null;
  }
  final d = axis.scale!.domain;
  final value = getValueByDataKey(entry, axis.settings.dataKey, index < d.length ? d[index] : null);
  if (value == null) return null;
  final scaled = axis.scale!.map(value);
  if (!isNumber(scaled)) return null;
  return scaled! - bandSize / 2 + offset;
}

/// The synthetic [Bar] the cartesian bar helpers read a [RadialBar] through.
GraphicalItem _asBar(PolarItem i) {
  final b = i.radialBar!;
  return GraphicalItem(
      i.id, Bar(dataKey: b.dataKey, stackId: b.stackId, barSize: b.barSize, maxBarSize: b.maxBarSize, hide: b.hide));
}

/// What `selectRadialBarSectors` reads besides the axes.
class RadialBarContext {
  RadialBarContext({
    required this.layout,
    required this.items,
    required this.chartData,
    required this.viewBox,
    required this.angleAxes,
    required this.radiusAxes,
    required this.stackOffset,
    required this.reverseStackOrder,
    required this.barGap,
    required this.barCategoryGap,
    required this.rootBarSize,
    required this.rootMaxBarSize,
    required this.tooltipAxis,
    this.dataStartIndex = 0,
    this.dataEndIndex = 0,
  });
  final PolarLayout layout;
  final List<PolarItem> items;
  final List<Object?> chartData;
  final PolarViewBox viewBox;
  final Map<Object, PolarAxisRuntime> angleAxes, radiusAxes;
  final StackOffset stackOffset;
  final bool reverseStackOrder;
  final Object barGap, barCategoryGap;
  final Object? rootBarSize;
  final double? rootMaxBarSize;

  /// `selectTooltipAxis`.
  final PolarAxisRuntime tooltipAxis;

  /// `chartDataSlice`: sectors cover `chartData.slice(dataStartIndex, dataEndIndex + 1)`.
  final int dataStartIndex, dataEndIndex;
}

/// `selectRadialBarSectors` for [item].
List<RadialBarSector> computeRadialBarSectors(PolarItem item, RadialBarContext ctx) {
  final bar = item.radialBar!;
  final layout = ctx.layout;
  final angleAxis = ctx.angleAxes[item.angleAxisId], radiusAxis = ctx.radiusAxes[item.radiusAxisId];
  if (angleAxis == null || radiusAxis == null || angleAxis.scale == null || radiusAxis.scale == null) return const [];
  final radiusItemTicks = radiusAxis.itemTicks, angleTicks = angleAxis.ticks;
  if (radiusItemTicks == null) return const [];

  // selectBandSizeOfPolarAxis
  final bandSize = isPolarCategorical(layout, false)
      ? getBandSizeOfAxis(radiusAxis.scale, radiusItemTicks, false)
      : getBandSizeOfAxis(angleAxis.scale, angleTicks, false);
  if (bandSize == null) return const [];

  // selectAllVisibleRadialBars + selectPolarBarSizeList
  final allBars = [
    for (final i in ctx.items)
      if (i.isRadialBar &&
          !i.hide &&
          (layout == PolarLayout.centric ? i.angleAxisId == item.angleAxisId : i.radiusAxisId == item.radiusAxisId))
        _asBar(i),
  ];
  final sizeList = barSizeList(allBars, ctx.rootBarSize, null);

  // selectPolarBarBandSize + combineAllBarPositions
  final maxBarSize = bar.maxBarSize ?? ctx.rootMaxBarSize;
  final barBandSize = (layout == PolarLayout.centric
          ? getBandSizeOfAxis(angleAxis.scale, angleTicks, true)
          : getBandSizeOfAxis(radiusAxis.scale, radiusItemTicks, true)) ??
      maxBarSize ??
      0;
  var positions = getBarPositions(
      ctx.barGap, ctx.barCategoryGap, barBandSize != bandSize ? barBandSize : bandSize, sizeList, maxBarSize);
  if (barBandSize != bandSize && positions != null) {
    positions = [for (final p in positions) BarPosition(p.stackId, p.dataKeys, p.offset - barBandSize / 2, p.size)];
  }
  final pos = positions?.where((p) => p.stackId == item.stackId && p.dataKeys.contains(item.dataKey)).firstOrNull;
  if (pos == null || angleTicks == null) return const [];

  // selectBaseValue
  final numericAxis = layout == PolarLayout.radial ? angleAxis : radiusAxis;
  final baseValue = baseValueOfBar(numericAxis);

  // selectPolarStackedData
  final stackAxis = layout == PolarLayout.centric ? radiusAxis : angleAxis;
  final stackedItems = [
    for (final i in ctx.items)
      if (i.isRadialBar &&
          i.stackId != null &&
          (layout == PolarLayout.centric ? i.radiusAxisId == stackAxis.id : i.angleAxisId == stackAxis.id) &&
          (stackAxis.settings.includeHidden || !i.hide))
        _asBar(i),
  ];
  final tooltipSettings = ctx.tooltipAxis.settings;
  final groups = combineStackGroups(
      combineDisplayedStackedData(stackedItems, ctx.chartData,
          XAxis(dataKey: tooltipSettings.dataKey, allowDuplicatedCategory: tooltipSettings.allowDuplicatedCategory)),
      stackedItems,
      ctx.stackOffset,
      ctx.reverseStackOrder);
  final stackedData = item.stackId == null ? null : groups[item.stackId]?.stackedData[item.id];
  final stackedDomain = stackedData != null ? numericAxis.scale!.domain : null;

  final vb = ctx.viewBox;
  final cells = bar.cells;
  final sectors = <RadialBarSector>[];
  final displayedData = ctx.chartData.sublist(
      math.min(ctx.dataStartIndex, ctx.chartData.length), math.min(ctx.dataEndIndex + 1, ctx.chartData.length));
  for (var index = 0; index < displayedData.length; index++) {
    final entry = displayedData[index];
    List<Object?> value;
    if (stackedData != null) {
      final i = ctx.dataStartIndex + index;
      value = i < stackedData.length ? truncateByDomain(stackedData[i], stackedDomain!) : [null, null];
    } else {
      final v = getValueByDataKey(entry, bar.dataKey);
      value = v is List ? v : [baseValue, v];
    }

    double? innerRadius, outerRadius, startAngle, endAngle;
    SectorGeometry? background;
    if (layout == PolarLayout.radial) {
      startAngle = angleAxis.scale!.map(value[0]) ?? vb.startAngle;
      endAngle = angleAxis.scale!.map(value.length > 1 ? value[1] : null) ?? vb.endAngle;
      innerRadius = _cateCoordinateOfBar(radiusAxis, radiusItemTicks, pos.offset, bandSize, entry, index);
      if (innerRadius != null) {
        outerRadius = innerRadius + pos.size;
        final deltaAngle = endAngle - startAngle;
        if (bar.minPointSize.abs() > 0 && deltaAngle.abs() < bar.minPointSize.abs()) {
          endAngle += mathSign(deltaAngle != 0 ? deltaAngle : bar.minPointSize) *
              (bar.minPointSize.abs() - deltaAngle.abs());
        }
        background = SectorGeometry(
            cx: vb.cx,
            cy: vb.cy,
            innerRadius: innerRadius,
            outerRadius: outerRadius,
            startAngle: vb.startAngle,
            endAngle: vb.endAngle,
            cornerRadius: parseCornerRadius(bar.cornerRadius) ?? 0,
            forceCornerRadius: bar.forceCornerRadius,
            cornerIsExternal: bar.cornerIsExternal);
      }
    } else {
      innerRadius = radiusAxis.scale!.map(value[0]);
      outerRadius = radiusAxis.scale!.map(value.length > 1 ? value[1] : null);
      startAngle = _cateCoordinateOfBar(angleAxis, angleTicks, pos.offset, bandSize, entry, index);
      if (innerRadius != null && outerRadius != null && startAngle != null) {
        endAngle = startAngle + pos.size;
        final deltaRadius = outerRadius - innerRadius;
        if (bar.minPointSize.abs() > 0 && deltaRadius.abs() < bar.minPointSize.abs()) {
          outerRadius += mathSign(deltaRadius != 0 ? deltaRadius : bar.minPointSize) *
              (bar.minPointSize.abs() - deltaRadius.abs());
        }
      }
    }

    final cell = index < cells.length ? cells[index] : null;
    final props = <String, Object?>{
      if (entry is Map) ...entry.cast<String, Object?>(),
      if (cell != null) ...{
        'fill': ?cell.fill,
        'fillOpacity': ?cell.fillOpacity,
        'stroke': ?cell.stroke,
        'strokeWidth': ?cell.strokeWidth,
      },
    };
    Color? color(String k, Color? fallback) => switch (props[k]) { final Color c => c, _ => fallback };
    double? number(String k, double? fallback) => switch (props[k]) { final num n => n.toDouble(), _ => fallback };
    sectors.add(RadialBarSector(
      cx: vb.cx,
      cy: vb.cy,
      innerRadius: innerRadius ?? double.nan,
      outerRadius: outerRadius ?? double.nan,
      startAngle: startAngle ?? double.nan,
      endAngle: endAngle ?? double.nan,
      value: stackedData != null ? value : (value.length > 1 ? value[1] : null),
      entry: entry,
      props: props,
      background: background,
      cell: cell,
      fill: color('fill', bar.fill),
      fillOpacity: number('fillOpacity', bar.fillOpacity),
      stroke: color('stroke', bar.stroke),
      strokeWidth: number('strokeWidth', bar.strokeWidth),
      strokeOpacity: number('strokeOpacity', bar.strokeOpacity),
    ));
  }
  return sectors;
}

/// `defaultRadialBarAnimateItems`: new sectors grow from their start angle.
List<RadialBarSector> interpolateRadialBarSectors(List<AnimationItem<RadialBarSector>>? items, double t) {
  if (items == null) return const [];
  if (t == 1) {
    return [
      for (final i in items)
        if (i is Matched<RadialBarSector>) i.next else if (i is Added<RadialBarSector>) i.next,
    ];
  }
  return [
    for (final item in items)
      switch (item) {
        Removed() => null,
        Matched(:final prev, :final next) => next.withAngles(
            interpolate(prev.startAngle, next.startAngle, t)!, interpolate(prev.endAngle, next.endAngle, t)!),
        Added(:final next) => next.withAngles(next.startAngle, interpolate(next.startAngle, next.endAngle, t)!),
      },
  ].nonNulls.toList();
}

/// A RadialBar as the store sees it.
class RadialBarModel {
  RadialBarModel(this.id, this.settings, this.sectors);
  final String id;
  final RadialBar settings;
  final List<RadialBarSector> sectors;
}
