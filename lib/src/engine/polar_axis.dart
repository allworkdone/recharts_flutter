// The polar axis chain: src/state/selectors/polarAxisSelectors.ts,
// polarScaleSelectors.ts, polarSelectors.ts and polarGridSelectors.ts, with
// the axisSelectors.ts combiners they share (combineAxisDomain,
// combineNumericalDomain, combineAxisTicks, combineGraphicalItemTicks,
// combineTicksOfTooltipAxis, combineDuplicateDomain, combineCategoricalDomain)
// and getAxisTypeBasedOnLayout. Leaf helpers come from axis.dart.

import 'dart:math' as math;
import 'dart:ui';

import '../components.dart';
import '../core/nice_ticks.dart';
import '../core/polar_utils.dart';
import '../core/scale.dart';
import '../polar_axes.dart';
import '../util.dart';
import 'axis.dart';
import 'get_ticks.dart';

/// `PolarLayout`.
enum PolarLayout { centric, radial }

/// `PolarChartOptions` (`ReportPolarOptions`).
class PolarOptions {
  const PolarOptions({
    this.cx = '50%',
    this.cy = '50%',
    this.innerRadius = 0,
    this.outerRadius = '80%',
    required this.startAngle,
    required this.endAngle,
  });
  final Object cx, cy, innerRadius, outerRadius;
  final double startAngle, endAngle;
}

/// A Radar or RadialBar as `state.graphicalItems.polarItems` holds it.
class PolarItem {
  PolarItem.radar(this.id, Radar radar)
      : radar = radar,
        radialBar = null,
        dataKey = radar.dataKey,
        hide = radar.hide,
        angleAxisId = radar.angleAxisId,
        radiusAxisId = radar.radiusAxisId,
        stackId = null;
  PolarItem.radialBar(this.id, RadialBar bar)
      : radar = null,
        radialBar = bar,
        dataKey = bar.dataKey,
        hide = bar.hide,
        angleAxisId = bar.angleAxisId,
        radiusAxisId = bar.radiusAxisId,
        stackId = bar.stackId == null ? null : jsString(bar.stackId);
  final String id;
  final Radar? radar;
  final RadialBar? radialBar;
  final Object? dataKey;
  final bool hide;
  final Object angleAxisId, radiusAxisId;

  /// `getNormalizedStackId`.
  final String? stackId;
  bool get isRadar => radar != null;
  bool get isRadialBar => radialBar != null;
}

/// `AngleAxisSettings` / `RadiusAxisSettings` after `getAxisTypeBasedOnLayout`.
class PolarAxisSettings {
  const PolarAxisSettings({
    required this.id,
    required this.dataKey,
    required this.type,
    required this.domain,
    required this.scale,
    required this.tickCount,
    required this.niceTicks,
    required this.allowDecimals,
    required this.allowDuplicatedCategory,
    required this.allowDataOverflow,
    required this.reversed,
    required this.includeHidden,
    required this.ticks,
  });
  final Object id;
  final Object? dataKey;
  final AxisDomainType type;
  final Object? domain;
  final String scale;

  /// Null is undefined: no nice ticks.
  final int? tickCount;
  final NiceTicksAlgorithm niceTicks;
  final bool allowDecimals, allowDuplicatedCategory, allowDataOverflow, reversed, includeHidden;
  final List<Object>? ticks;
}

/// `isCategoricalAxis` for polar layouts.
bool isPolarCategorical(PolarLayout layout, bool isAngle) =>
    (layout == PolarLayout.centric && isAngle) || (layout == PolarLayout.radial && !isAngle);

AxisDomainType _evaluatedType(PolarLayout layout, bool isAngle, AxisDomainType type) =>
    type != AxisDomainType.auto
        ? type
        : (isPolarCategorical(layout, isAngle) ? AxisDomainType.category : AxisDomainType.number);

/// `selectAngleAxis`: the declared axis, else `implicitAngleAxis`.
PolarAxisSettings angleAxisSettings(PolarLayout layout, Object id, PolarAngleAxis? axis) => PolarAxisSettings(
      id: id,
      dataKey: axis?.dataKey,
      type: _evaluatedType(layout, true, axis?.type ?? AxisDomainType.auto),
      domain: axis?.domain,
      scale: axis?.scale ?? 'auto',
      tickCount: axis?.tickCount,
      niceTicks: axis?.niceTicks ?? NiceTicksAlgorithm.auto,
      allowDecimals: axis?.allowDecimals ?? false,
      // The axis ignores the prop: its calculation behaves as if it were false.
      allowDuplicatedCategory: false,
      allowDataOverflow: false,
      reversed: axis?.reversed ?? false,
      includeHidden: false,
      ticks: axis?.ticks,
    );

/// `selectRadiusAxis`: the declared axis, else `implicitRadiusAxis`.
PolarAxisSettings radiusAxisSettings(PolarLayout layout, Object id, PolarRadiusAxis? axis) => PolarAxisSettings(
      id: id,
      dataKey: axis?.dataKey,
      type: _evaluatedType(layout, false, axis?.type ?? AxisDomainType.auto),
      domain: axis?.domain,
      scale: axis?.scale ?? 'auto',
      tickCount: axis?.tickCount ?? 5,
      niceTicks: axis?.niceTicks ?? NiceTicksAlgorithm.auto,
      allowDecimals: axis?.allowDecimals ?? false,
      allowDuplicatedCategory: axis?.allowDuplicatedCategory ?? true,
      allowDataOverflow: axis?.allowDataOverflow ?? false,
      reversed: axis?.reversed ?? false,
      includeHidden: axis?.includeHidden ?? false,
      ticks: axis?.ticks,
    );

/// One polar axis from settings to scale and ticks.
class PolarAxisRuntime {
  PolarAxisRuntime(this.settings, this.isAngle, this.element);
  final PolarAxisSettings settings;
  final bool isAngle;

  /// The declared [PolarAngleAxis] or [PolarRadiusAxis], null for an implicit axis.
  final RechartsElement? element;

  List<Object?>? domain;
  String? realScaleType;
  List<num>? niceTicks;
  List<Object?>? domainWithNiceTicks;
  List<Object?>? duplicateDomain;
  List<Object?>? categoricalDomain;

  /// `selectAngleAxisRange` / `selectRadiusAxisRange`.
  late List<double> range;

  /// `...WithReversed`.
  late List<double> rangeWithReverse;
  RechartsScale? scale;

  /// `selectPolarAxisTicks`.
  List<TickItem>? ticks;

  /// `selectPolarGraphicalItemAxisTicks`.
  List<TickItem>? itemTicks;

  Object get id => settings.id;
  AxisDomainType get type => settings.type;
}

/// `getDomainDefinition`.
Object _domainDefinition(PolarAxisSettings s) {
  if (s.domain != null) return s.domain!;
  final ticks = s.ticks;
  if (ticks != null) {
    if (s.type == AxisDomainType.number) {
      final all = onlyAllowNumbers(ticks);
      return [all.reduce(math.min), all.reduce(math.max)];
    }
    if (s.type == AxisDomainType.category) return ticks.map(jsString).toList();
  }
  return const <Object>[0, 'auto'];
}

/// `combineNiceTicks`, through the shared implementation.
List<num>? _niceTicks(PolarAxisRuntime a, Object domainDefinition) {
  final s = a.settings;
  final synthetic = XAxis(
      tickCount: s.tickCount ?? 0, allowDecimals: s.allowDecimals, niceTicks: s.niceTicks, type: s.type);
  return combineNiceTicks(a.domain, synthetic, s.type, domainDefinition, a.realScaleType);
}

/// Everything the polar axis selectors read from the chart.
class PolarAxisContext {
  PolarAxisContext({
    required this.layout,
    required this.chartName,
    required this.chartData,
    required this.items,
    required this.options,
    required this.maxRadius,
    required this.innerRadius,
    required this.outerRadius,
    required this.stackOffset,
  });
  final PolarLayout layout;
  final String chartName;
  final List<Object?> chartData;
  final List<PolarItem> items;
  final PolarOptions options;
  final double maxRadius, innerRadius, outerRadius;
  final StackOffset stackOffset;
  bool get hasBar => items.any((i) => i.isRadialBar);
}

/// `selectPolarAxisDomain` .. `selectPolarAxisTicks`, plus the graphical-item ticks.
PolarAxisRuntime computePolarAxis(PolarAxisSettings s, bool isAngle, RechartsElement? element, PolarAxisContext ctx) {
  final a = PolarAxisRuntime(s, isAngle, element);
  final layout = ctx.layout;
  final isCategorical = isPolarCategorical(layout, isAngle);

  // selectPolarItemsSettings
  final items = [
    for (final i in ctx.items)
      if ((isAngle ? i.angleAxisId : i.radiusAxisId) == s.id && (s.includeHidden || !i.hide)) i,
  ];
  // Polar items carry no data of their own: the whole chart data.
  final displayedData = ctx.chartData;
  final List<Object?> applied;
  if (s.dataKey != null) {
    applied = [for (final e in displayedData) getValueByDataKey(e, s.dataKey)];
  } else if (items.isNotEmpty) {
    applied = [
      for (final i in items)
        for (final e in displayedData) getValueByDataKey(e, i.dataKey),
    ];
  } else {
    applied = displayedData;
  }

  final definition = _domainDefinition(s);
  final fromPreference = numericalDomainSpecifiedWithoutRequiringData(definition, s.allowDataOverflow);

  // combineDomainOfAllAppliedNumericalValuesIncludingErrorValues
  double? lower, upper;
  void take(List<double>? d) {
    if (d == null) return;
    lower = lower == null ? d[0] : math.min(lower!, d[0]);
    upper = upper == null ? d[1] : math.max(upper!, d[1]);
  }

  for (final item in items) {
    for (final entry in ctx.chartData) {
      take(makeDomain(getValueByDataKey(entry, s.dataKey ?? item.dataKey)));
    }
  }
  if (s.dataKey != null && items.isEmpty) {
    for (final entry in displayedData) {
      take(makeDomain(getValueByDataKey(entry, s.dataKey)));
    }
  }
  final dataDomain = isWellBehavedNumber(lower) && isWellBehavedNumber(upper) ? <double>[lower!, upper!] : null;

  // combineNumericalDomain: polar charts never add the stack groups' domain.
  List<double>? numerical;
  if (fromPreference != null) {
    numerical = fromPreference;
  } else {
    numerical = parseNumericalUserDomain(definition, mergeDomains([dataDomain]), s.allowDataOverflow);
  }

  // combineAxisDomain
  if (displayedData.isEmpty && numerical == null) {
    a.domain = null;
  } else if (isCategorical && s.dataKey == null) {
    a.domain = List<Object?>.generate(displayedData.length, (i) => i);
  } else if (s.type == AxisDomainType.category) {
    final categorical = applied.where((v) => isNumOrStr(v) || v is DateTime).toList();
    if (isCategorical && (s.dataKey == null || (s.allowDuplicatedCategory && hasDuplicate(categorical)))) {
      a.domain = List<Object?>.generate(applied.length, (i) => i);
    } else if (s.allowDuplicatedCategory) {
      a.domain = categorical;
    } else {
      a.domain = categorical.toSet().toList();
    }
  } else if (!isCategorical &&
      ctx.stackOffset == StackOffset.expand &&
      // combineStackOffsetTypeOfAxis: only an axis with stacked radial bars on it, hidden ones included.
      ctx.items.any((i) => (isAngle ? i.angleAxisId : i.radiusAxisId) == s.id && i.isRadialBar && i.stackId != null)) {
    a.domain = const [0.0, 1.0];
  } else {
    a.domain = numerical;
  }

  a.realScaleType = combineRealScaleType(s.scale, s.type, ctx.hasBar, ctx.chartName);
  a.niceTicks = _niceTicks(a, definition);

  // combineAxisDomainWithNiceTicks: the angle axis never extends its domain.
  final d = a.domain, nt = a.niceTicks;
  if (!isAngle && s.type == AxisDomainType.number && isWellFormedNumberDomain(d) && nt != null && nt.isNotEmpty) {
    a.domainWithNiceTicks = [
      math.min((d![0] as num).toDouble(), nt.first.toDouble()),
      math.max((d[1] as num).toDouble(), nt.last.toDouble()),
    ];
  } else {
    a.domainWithNiceTicks = d;
  }

  final validData = applied.where((v) => v != null).toList();
  a.duplicateDomain = s.dataKey != null &&
          isCategorical &&
          s.type == AxisDomainType.category &&
          s.allowDuplicatedCategory &&
          hasDuplicate(validData)
      ? applied
      : null;
  a.categoricalDomain =
      s.dataKey != null && isCategorical && (s.type == AxisDomainType.number || s.scale != 'auto') ? applied : null;

  // Ranges.
  a.range = isAngle
      ? [ctx.options.startAngle, ctx.options.endAngle]
      : [ctx.innerRadius, ctx.outerRadius];
  a.rangeWithReverse = s.reversed ? [a.range[1], a.range[0]] : a.range;
  a.scale = buildScale(a.realScaleType, a.domainWithNiceTicks, a.rangeWithReverse);
  a.ticks = polarAxisTicks(a, layout);
  a.itemTicks = polarGraphicalItemTicks(a, layout);
  return a;
}

List<TickItem> _mapEntries(List<Object?> entries, RechartsScale scale, double offset) {
  final out = <TickItem>[];
  for (var index = 0; index < entries.length; index++) {
    final scaled = scale.map(entries[index]);
    if (!isWellBehavedNumber(scaled)) continue;
    out.add(TickItem(coordinate: scaled! + offset, value: entries[index], index: index, offset: offset));
  }
  return out;
}

List<TickItem> _mapDomain(RechartsScale scale, List<Object?>? duplicateDomain, double offset) {
  final out = <TickItem>[];
  final dom = scale.domain;
  for (var index = 0; index < dom.length; index++) {
    final entry = dom[index];
    final scaled = scale.map(entry);
    if (!isWellBehavedNumber(scaled)) continue;
    final dup = duplicateDomain;
    final value = dup != null && entry is int && entry >= 0 && entry < dup.length ? dup[entry] : entry;
    out.add(TickItem(coordinate: scaled! + offset, value: value, index: index, offset: offset));
  }
  return out;
}

/// The band offset of an angle axis' ticks: `mathSign(range[0] - range[1]) * 2 * offset`.
double _angleOffset(double offset, List<double> range) => mathSign(range[0] - range[1]) * 2 * offset;

/// `combineAxisTicks` for a polar axis. The `'scaleBand'` check there never
/// matches a real scale type, so the band offset is half a bandwidth.
List<TickItem>? polarAxisTicks(PolarAxisRuntime a, PolarLayout layout) {
  final scale = a.scale;
  if (scale == null) return null;
  final s = a.settings;
  final bandwidth = scale.bandwidth;
  var offset = s.type == AxisDomainType.category && bandwidth != null ? bandwidth / 2 : 0.0;
  if (a.isAngle) offset = _angleOffset(offset, a.rangeWithReverse);
  final ticksOrNice = s.ticks ?? a.niceTicks;
  if (ticksOrNice != null) {
    final out = <TickItem>[];
    for (var index = 0; index < ticksOrNice.length; index++) {
      final entry = ticksOrNice[index];
      final scaleContent = a.duplicateDomain != null ? a.duplicateDomain!.indexOf(entry) : entry;
      final scaled = scale.map(scaleContent);
      if (!isWellBehavedNumber(scaled)) continue;
      out.add(TickItem(index: index, coordinate: scaled! + offset, value: entry, offset: offset));
    }
    return out;
  }
  if (isPolarCategorical(layout, a.isAngle) && a.categoricalDomain != null) {
    return _mapEntries(a.categoricalDomain!, scale, offset);
  }
  final scaleTicks = scale.ticks(s.tickCount ?? 10);
  if (scaleTicks != null) return _mapEntries(scaleTicks, scale, offset);
  return _mapDomain(scale, a.duplicateDomain, offset);
}

/// `combineGraphicalItemTicks`: no band offset.
List<TickItem>? polarGraphicalItemTicks(PolarAxisRuntime a, PolarLayout layout) {
  final scale = a.scale;
  if (scale == null || a.rangeWithReverse[0] == a.rangeWithReverse[1]) return null;
  if (isPolarCategorical(layout, a.isAngle) && a.categoricalDomain != null) {
    return _mapEntries(a.categoricalDomain!, scale, 0);
  }
  final scaleTicks = scale.ticks(a.settings.tickCount ?? 10);
  if (scaleTicks != null) return _mapEntries(scaleTicks, scale, 0);
  return _mapDomain(scale, a.duplicateDomain, 0);
}

/// `combineTicksOfTooltipAxis`: an angle axis uses its range as given, not reversed.
List<TickItem>? polarTooltipTicks(PolarAxisRuntime a, PolarLayout layout) {
  final scale = a.scale;
  if (scale == null) return null;
  final bandwidth = scale.bandwidth;
  var offset = a.type == AxisDomainType.category && bandwidth != null ? bandwidth / 2 : 0.0;
  if (a.isAngle) offset = _angleOffset(offset, a.range);
  if (isPolarCategorical(layout, a.isAngle) && a.categoricalDomain != null) {
    return _mapEntries(a.categoricalDomain!, scale, offset);
  }
  return _mapDomain(scale, a.duplicateDomain, offset);
}

/// `selectPolarAngleAxisTicks`: ticks at the same angle modulo a turn drawn once.
List<TickItem> dedupeAngleTicks(List<TickItem> ticks) {
  final seen = <double, TickItem>{};
  for (final t in ticks) {
    seen.putIfAbsent((t.coordinate + 360).remainder(360), () => t);
  }
  return seen.values.toList();
}

/// `selectPolarViewBox` and the radii it is built from.
class PolarGeometry {
  PolarGeometry(this.viewBox, this.maxRadius);
  final PolarViewBox viewBox;
  final double maxRadius;
  double get innerRadius => viewBox.innerRadius;
  double get outerRadius => viewBox.outerRadius;
}

/// `selectMaxRadius`, `selectInnerRadius`, `selectOuterRadius`, `selectPolarViewBox`.
/// cx and cy are percents of the whole chart, with no offset added.
PolarGeometry polarGeometry(PolarOptions o, Size size, ({double top, double right, double bottom, double left}) offset) {
  final maxRadius = getMaxRadius(size.width, size.height,
      top: offset.top, right: offset.right, bottom: offset.bottom, left: offset.left);
  return PolarGeometry(
      PolarViewBox(
        cx: getPercentValue(o.cx, size.width, size.width / 2),
        cy: getPercentValue(o.cy, size.height, size.height / 2),
        innerRadius: getPercentValue(o.innerRadius, maxRadius, 0),
        outerRadius: getPercentValue(o.outerRadius, maxRadius, maxRadius * 0.8),
        startAngle: o.startAngle,
        endAngle: o.endAngle,
      ),
      maxRadius);
}
