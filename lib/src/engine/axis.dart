// Port of the axis selectors in src/state/selectors/axisSelectors.ts and their
// combiners (combineRealScaleType, combineCheckedDomain, combineConfiguredScale,
// combineAxisRangeWithReverse), src/util/isDomainSpecifiedByUser.ts, and the
// tick/band helpers of src/util/ChartUtils.ts (getTicksOfAxis,
// getBandSizeOfAxis, getStackedData, getDomainOfStackGroups, offsetSign,
// offsetPositive, getCoordinatesOfGrid); silhouette and wiggle come from
// core/stack.dart. ErrorBar domains: getErrorDomainByDataKey and
// combineDomainOfAllAppliedNumericalValuesIncludingErrorValues; ZAxis:
// implicitZAxis, selectZAxisWithScale.

import 'dart:math' as math;

import '../components.dart';
import '../core/curve.dart';
import '../core/nice_ticks.dart';
import '../core/scale.dart';
import '../core/stack.dart';
import '../util.dart';
import 'get_ticks.dart';

typedef NumberDomain = List<double>;

/// A graphical item as the store sees it (`CartesianGraphicalItemSettings`).
class GraphicalItem {
  GraphicalItem(this.id, this.element);
  final String id;
  final CartesianSeries element;
  bool get isBar => element is Bar;
  bool get isArea => element is Area;
  bool get isScatter => element is Scatter;
  Object? get dataKey => element.dataKey;
  Object get xAxisId => element.xAxisId;
  Object get yAxisId => element.yAxisId;
  bool get hide => element.hide;
  /// `getNormalizedStackId`: stack ids are compared as strings.
  String? get stackId => element.stackIdOrNull == null ? null : jsString(element.stackIdOrNull);
  List<Object?>? get data => element.itemData as List<Object?>?;
}

/// Everything the selectors read from the root chart props.
class ChartContext {
  ChartContext({
    required this.layout,
    required this.chartName,
    required this.chartData,
    List<Object?>? fullChartData,
    this.dataStartIndex = 0,
    this.dataEndIndex = 0,
    required this.items,
    required this.referenceLines,
    required this.stackOffset,
    required this.reverseStackOrder,
    required this.barCategoryGap,
    required this.tooltipAxis,
  }) : fullChartData = fullChartData ?? chartData;
  final ChartLayout layout;
  final String chartName;

  /// Root data sliced by the Brush indexes (`selectChartDataSliceIfNotInPanorama`).
  final List<Object?> chartData;

  /// Root data ignoring the Brush (stacks are computed over all of it).
  final List<Object?> fullChartData;
  final int dataStartIndex, dataEndIndex;
  final List<GraphicalItem> items;
  final List<ReferenceLine> referenceLines;
  final StackOffset stackOffset;
  final bool reverseStackOrder;
  final Object barCategoryGap;

  /// `selectTooltipAxis`: settings of the tooltip axis (implicit if missing).
  final CartesianAxisElement tooltipAxis;

  bool get hasBar => items.any((i) => i.isBar);
}

bool isCategoricalAxis(ChartLayout layout, bool isX) =>
    (layout == ChartLayout.horizontal && isX) || (layout == ChartLayout.vertical && !isX);

/// `getAxisTypeBasedOnLayout`.
AxisDomainType evaluatedAxisType(ChartLayout layout, CartesianAxisElement axis) {
  if (axis.type != AxisDomainType.auto) return axis.type;
  return isCategoricalAxis(layout, axis.isX) ? AxisDomainType.category : AxisDomainType.number;
}

bool _isWellFormedNumberDomain(Object? v) =>
    v is List && v.length == 2 && isWellBehavedNumber(v[0]) && isWellBehavedNumber(v[1]);

double? _makeNumber(Object? val) {
  if (isNumOrStr(val) || val is DateTime) {
    final n = jsNumber(val);
    if (n.isFinite) return n;
  }
  return null;
}

NumberDomain? _makeDomain(Object? val) {
  if (val is List) {
    final a = val.isNotEmpty ? _makeNumber(val[0]) : null;
    final b = val.length > 1 ? _makeNumber(val[1]) : null;
    return a != null && b != null ? [a, b] : null;
  }
  final n = _makeNumber(val);
  return n == null ? null : [n, n];
}

List<double> onlyAllowNumbers(Iterable<Object?> data) => [for (final v in data) ?_makeNumber(v)];

NumberDomain? mergeDomains(List<List<double>?> domains) {
  final all = domains.whereType<List<double>>().expand((d) => d).toList();
  if (all.isEmpty) return null;
  return [all.reduce(math.min), all.reduce(math.max)];
}

final _minValueReg = RegExp(r'^dataMin[\s]*-[\s]*([0-9]+([.]{1}[0-9]+){0,1})$');
final _maxValueReg = RegExp(r'^dataMax[\s]*\+[\s]*([0-9]+([.]{1}[0-9]+){0,1})$');

NumberDomain extendDomain(NumberDomain provided, NumberDomain boundary, bool allowDataOverflow) {
  if (allowDataOverflow) return provided;
  return [math.min(provided[0], boundary[0]), math.max(provided[1], boundary[1])];
}

NumberDomain? numericalDomainSpecifiedWithoutRequiringData(Object? userDomain, bool allowDataOverflow) {
  if (!allowDataOverflow) return null;
  if (userDomain is Function) return null;
  if (userDomain is List && userDomain.length == 2) {
    final [providedMin, providedMax] = userDomain;
    if (providedMin is Function || providedMax is Function) return null;
    final candidate = [
      isWellBehavedNumber(providedMin) ? (providedMin as num).toDouble() : null,
      isWellBehavedNumber(providedMax) ? (providedMax as num).toDouble() : null,
    ];
    if (_isWellFormedNumberDomain(candidate)) return candidate.cast<double>();
  }
  return null;
}

NumberDomain? parseNumericalUserDomain(Object? userDomain, NumberDomain? dataDomain, bool allowDataOverflow) {
  if (!allowDataOverflow && dataDomain == null) return null;
  if (userDomain is Function && userDomain is! num Function(num) && dataDomain != null) {
    try {
      final result = (userDomain as dynamic)(dataDomain, allowDataOverflow);
      if (_isWellFormedNumberDomain(result)) {
        final r = [(result[0] as num).toDouble(), (result[1] as num).toDouble()];
        return extendDomain(r, dataDomain, allowDataOverflow);
      }
    } catch (_) {}
  }
  if (userDomain is List && userDomain.length == 2) {
    final [providedMin, providedMax] = userDomain;
    double? finalMin, finalMax;
    if (providedMin == 'auto') {
      if (dataDomain != null) finalMin = dataDomain.reduce(math.min);
    } else if (isNumber(providedMin)) {
      finalMin = (providedMin as num).toDouble();
    } else if (providedMin is Function) {
      try {
        if (dataDomain != null) finalMin = ((providedMin as dynamic)(dataDomain[0]) as num?)?.toDouble();
      } catch (_) {}
    } else if (providedMin is String && _minValueReg.hasMatch(providedMin)) {
      final m = _minValueReg.firstMatch(providedMin);
      finalMin = m == null || dataDomain == null ? null : dataDomain[0] - double.parse(m[1]!);
    } else {
      finalMin = dataDomain?[0];
    }
    if (providedMax == 'auto') {
      if (dataDomain != null) finalMax = dataDomain.reduce(math.max);
    } else if (isNumber(providedMax)) {
      finalMax = (providedMax as num).toDouble();
    } else if (providedMax is Function) {
      try {
        if (dataDomain != null) finalMax = ((providedMax as dynamic)(dataDomain[1]) as num?)?.toDouble();
      } catch (_) {}
    } else if (providedMax is String && _maxValueReg.hasMatch(providedMax)) {
      final m = _maxValueReg.firstMatch(providedMax);
      finalMax = m == null || dataDomain == null ? null : dataDomain[1] + double.parse(m[1]!);
    } else {
      finalMax = dataDomain?[1];
    }
    final candidate = [finalMin, finalMax];
    if (_isWellFormedNumberDomain(candidate)) {
      final c = [finalMin!, finalMax!];
      return dataDomain == null ? c : extendDomain(c, dataDomain, allowDataOverflow);
    }
  }
  return null;
}

/// `getDomainDefinition`.
Object getDomainDefinition(CartesianAxisElement axis, AxisDomainType type) {
  if (axis.domain != null) return axis.domain!;
  final ticks = axis.ticks;
  if (ticks != null) {
    if (type == AxisDomainType.number) {
      final all = onlyAllowNumbers(ticks);
      return [all.reduce(math.min), all.reduce(math.max)];
    }
    if (type == AxisDomainType.category) return ticks.map(jsString).toList();
  }
  return const <Object>[0, 'auto'];
}

/// The [ErrorBar] children of a [Bar], [Line] or [Scatter].
List<ErrorBar> errorBarsOf(CartesianSeries series) => switch (series) {
      Bar b => b.children.whereType<ErrorBar>().toList(),
      Line l => l.children.whereType<ErrorBar>().toList(),
      Scatter s => s.children.whereType<ErrorBar>().toList(),
      _ => const [],
    };

/// `useErrorBarDirection`.
ErrorBarDirection errorBarDirection(ErrorBar bar, ChartLayout layout) =>
    bar.direction ?? (layout == ChartLayout.horizontal ? ErrorBarDirection.y : ErrorBarDirection.x);

/// `getErrorDomainByDataKey`: `value -/+ error` for each error bar, against
/// the highest number of a range value.
List<double> getErrorDomainByDataKey(Object? entry, Object? appliedValue, List<ErrorBar> errorBars) {
  if (errorBars.isEmpty) return const [];
  double? v;
  if (appliedValue is num && !appliedValue.isNaN) {
    v = appliedValue.toDouble();
  } else if (appliedValue is List) {
    final nums = onlyAllowNumbers(appliedValue);
    if (nums.isNotEmpty) v = nums.reduce(math.max);
  }
  if (v == null) return const [];
  final out = <double>[];
  for (final eb in errorBars) {
    final errorValue = getValueByDataKey(entry, eb.dataKey);
    final low = errorValue is List ? errorValue.firstOrNull : errorValue;
    final high = errorValue is List ? errorValue.elementAtOrNull(1) : errorValue;
    if (isWellBehavedNumber(low) && isWellBehavedNumber(high)) out.addAll([v - (low as num), v + (high as num)]);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Stacks (combineDisplayedStackedData, combineStackGroups, getStackedData)

class StackGroup {
  StackGroup(this.items, this.stackedData);
  final List<GraphicalItem> items;

  /// Item id -> d3 stack series: one `[y0, y1]` per data point.
  final Map<String, List<List<double>>> stackedData;
}

List<Map<String, Object?>> combineDisplayedStackedData(
    List<GraphicalItem> stackedItems, List<Object?> chartData, CartesianAxisElement tooltipAxis) {
  final known = <Object, Map<String, Object?>>{};
  for (final item in stackedItems) {
    final resolvedData = item.data ?? chartData;
    if (resolvedData.isEmpty) continue;
    for (var index = 0; index < resolvedData.length; index++) {
      final entry = resolvedData[index];
      final Object tooltipValue = tooltipAxis.dataKey == null || tooltipAxis.allowDuplicatedCategory
          ? index
          : jsString(getValueByDataKey(entry, tooltipAxis.dataKey, null));
      final curr = known.putIfAbsent(tooltipValue, () => {});
      curr[item.id] = getValueByDataKey(entry, item.dataKey, 0);
    }
  }
  return known.values.toList();
}

Map<String, List<List<double>>> getStackedData(
    List<Map<String, Object?>> data, List<String> keys, StackOffset offsetType) {
  // d3 stack().keys(keys).value((d, key) => Number(get(d, key, 0))).order(none)
  final series = [
    for (final key in keys) [for (final d in data) <double>[0, jsNumber(d[key] ?? 0)]],
  ];
  final order = List.generate(keys.length, (i) => i);
  switch (offsetType) {
    case StackOffset.sign:
      _offsetSign(series);
    case StackOffset.positive:
      _offsetPositive(series);
    case StackOffset.expand:
      _offsetExpand(series);
    case StackOffset.silhouette:
      stackOffsetSilhouette(series, order);
    case StackOffset.wiggle:
      stackOffsetWiggle(series, order);
    case StackOffset.none:
      _offsetNone(series);
  }
  for (var s = 0; s < series.length; s++) {
    for (var p = 0; p < series[s].length; p++) {
      final value = data[p][keys[s]];
      if (value is List && value.length == 2 && isNumber(value[0]) && isNumber(value[1])) {
        series[s][p] = [(value[0] as num).toDouble(), (value[1] as num).toDouble()];
      }
    }
  }
  return {for (var i = 0; i < keys.length; i++) keys[i]: series[i]};
}

void _offsetNone(List<List<List<double>>> series) {
  if (series.length <= 1) return;
  final m = series[0].length;
  for (var i = 1; i < series.length; i++) {
    final s0 = series[i - 1], s1 = series[i];
    for (var j = 0; j < m; j++) {
      s1[j][0] = s0[j][1].isNaN ? s0[j][0] : s0[j][1];
      s1[j][1] += s1[j][0];
    }
  }
}

void _offsetExpand(List<List<List<double>>> series) {
  if (series.isEmpty) return;
  final m = series[0].length;
  for (var j = 0; j < m; j++) {
    var y = 0.0;
    for (final s in series) {
      if (!s[j][1].isNaN) y += s[j][1];
    }
    if (y != 0) {
      for (final s in series) {
        s[j][1] /= y;
      }
    }
  }
  _offsetNone(series);
}

void _offsetSign(List<List<List<double>>> series) {
  if (series.isEmpty || series[0].isEmpty) return;
  for (var j = 0; j < series[0].length; j++) {
    var positive = 0.0, negative = 0.0;
    for (final row in series) {
      final col = row[j];
      final value = col[1].isNaN ? col[0] : col[1];
      if (value >= 0) {
        col[0] = positive;
        positive += value;
        col[1] = positive;
      } else {
        col[0] = negative;
        negative += value;
        col[1] = negative;
      }
    }
  }
}

void _offsetPositive(List<List<List<double>>> series) {
  if (series.isEmpty || series[0].isEmpty) return;
  for (var j = 0; j < series[0].length; j++) {
    var positive = 0.0;
    for (final row in series) {
      final col = row[j];
      final value = col[1].isNaN ? col[0] : col[1];
      if (value >= 0) {
        col[0] = positive;
        positive += value;
        col[1] = positive;
      } else {
        col[0] = 0;
        col[1] = 0;
      }
    }
  }
}

Map<String, StackGroup> combineStackGroups(List<Map<String, Object?>> displayedData, List<GraphicalItem> items,
    StackOffset stackOffset, bool reverseStackOrder) {
  final groups = <String, List<GraphicalItem>>{};
  for (final item in items) {
    if (item.stackId == null) continue;
    groups.putIfAbsent(jsString(item.stackId), () => []).add(item);
  }
  return groups.map((stackId, graphicalItems) {
    final ordered = reverseStackOrder ? graphicalItems.reversed.toList() : graphicalItems;
    return MapEntry(
        stackId, StackGroup(ordered, getStackedData(displayedData, [for (final i in ordered) i.id], stackOffset)));
  });
}

NumberDomain? getDomainOfStackGroups(Map<String, StackGroup>? stackGroups, [int startIndex = 0, int endIndex = 0]) {
  if (stackGroups == null || stackGroups.isEmpty) return null;
  var result = [double.infinity, double.negativeInfinity];
  for (final group in stackGroups.values) {
    for (final entry in group.stackedData.values) {
      final flat = getSliced(entry, startIndex, endIndex).expand((p) => p).where((v) => !v.isNaN).toList();
      if (flat.isEmpty) continue;
      final s0 = flat.reduce(math.min), s1 = flat.reduce(math.max);
      if (!s0.isFinite || !s1.isFinite) continue;
      result = [math.min(result[0], s0), math.max(result[1], s1)];
    }
  }
  return [result[0] == double.infinity ? 0 : result[0], result[1] == double.negativeInfinity ? 0 : result[1]];
}

// ---------------------------------------------------------------------------
// One axis, from settings to scale and ticks.

class AxisRuntime {
  AxisRuntime({required this.settings, required this.isX, required this.type});

  final CartesianAxisElement settings;
  final bool isX;

  /// Settings type after `getAxisTypeBasedOnLayout`.
  final AxisDomainType type;

  late bool isCategorical;
  List<GraphicalItem> items = const [];
  List<Object?> displayedData = const [];
  List<Object?> appliedValues = const [];
  Map<String, StackGroup>? stackGroups;
  List<Object?>? domain;
  String? realScaleType;
  List<num>? niceTicks;
  List<Object?>? domainWithNiceTicks;
  List<double>? range; // not reversed
  RechartsScale? scale;
  List<Object?>? duplicateDomain;
  List<Object?>? categoricalDomain;

  /// `selectTicksOfAxis` (before getTicks filtering).
  List<TickItem>? ticksOfAxis;

  /// `selectTicksOfGraphicalItem`.
  List<TickItem>? itemTicks;

  Object get id => settings.id;
  bool get allowDataOverflow => settings.allowDataOverflow;
}

/// Computes everything up to (but excluding) the range, which needs the offset.
void computeAxisDomain(AxisRuntime axis, ChartContext ctx) {
  final s = axis.settings;
  final layout = ctx.layout;
  axis.isCategorical = isCategoricalAxis(layout, axis.isX);

  // combineGraphicalItemsSettings
  axis.items = ctx.items
      .where((i) => (axis.isX ? i.xAxisId : i.yAxisId) == s.id)
      .where((i) => s.includeHidden || !i.hide)
      .toList();
  final items = axis.items;

  // selectCartesianGraphicalItemsData + combineDisplayedData
  final graphicalItemsData = [for (final i in items) ...?i.data];
  axis.displayedData = graphicalItemsData.isNotEmpty ? graphicalItemsData : ctx.chartData;

  // combineAllAppliedValues
  List<Object?> applied;
  if (s.dataKey != null) {
    applied = [for (final e in axis.displayedData) getValueByDataKey(e, s.dataKey)];
  } else if (items.isNotEmpty) {
    applied = [
      for (final i in items)
        for (final e in axis.displayedData) getValueByDataKey(e, i.dataKey),
    ];
  } else {
    applied = axis.displayedData;
  }
  final anyItemUsesChartData = items.any((i) => i.data == null);
  if (anyItemUsesChartData && s.dataKey != null && graphicalItemsData.isNotEmpty) {
    applied = [
      for (final e in ctx.chartData) ?getValueByDataKey(e, s.dataKey),
      ...applied,
    ];
  }
  axis.appliedValues = applied;

  final domainDefinition = getDomainDefinition(s, axis.type);
  final domainFromUserPreference = numericalDomainSpecifiedWithoutRequiringData(domainDefinition, s.allowDataOverflow);

  // Stack groups (selectStackGroups + combineDomainOfStackGroups): areas and bars.
  final stackedItems = items.where((i) => (i.isBar || i.isArea) && i.stackId != null).toList();
  axis.stackGroups = combineStackGroups(combineDisplayedStackedData(stackedItems, ctx.fullChartData, ctx.tooltipAxis),
      stackedItems, ctx.stackOffset, ctx.reverseStackOrder);
  final domainOfStackGroups = domainFromUserPreference != null
      ? null
      : getDomainOfStackGroups(axis.stackGroups, ctx.dataStartIndex, ctx.dataEndIndex);

  // combineDomainOfAllAppliedNumericalValuesIncludingErrorValues
  double? lowerEnd, upperEnd;
  void take(NumberDomain? d) {
    if (d == null) return;
    lowerEnd = lowerEnd == null ? d[0] : math.min(lowerEnd!, d[0]);
    upperEnd = upperEnd == null ? d[1] : math.max(upperEnd!, d[1]);
  }

  final notStacked = items.where((i) => i.stackId == null).toList();
  final direction = axis.isX ? ErrorBarDirection.x : ErrorBarDirection.y;
  for (final item in notStacked) {
    final errorBars = [
      for (final e in errorBarsOf(item.element))
        if (errorBarDirection(e, layout) == direction) e,
    ];
    for (final entry in item.data ?? ctx.chartData) {
      final value = getValueByDataKey(entry, s.dataKey ?? item.dataKey);
      final errorDomain = getErrorDomainByDataKey(entry, value, errorBars);
      if (errorDomain.length >= 2) take([errorDomain.reduce(math.min), errorDomain.reduce(math.max)]);
      take(_makeDomain(value));
    }
  }
  if (s.dataKey != null && notStacked.isEmpty) {
    for (final entry in axis.displayedData) {
      take(_makeDomain(getValueByDataKey(entry, s.dataKey)));
    }
  }
  final dataDomain =
      isWellBehavedNumber(lowerEnd) && isWellBehavedNumber(upperEnd) ? <double>[lowerEnd!, upperEnd!] : null;

  // combineLinesDomain for ReferenceLine ifOverflow="extendDomain"
  final lineCoords = onlyAllowNumbers([
    for (final l in ctx.referenceLines)
      if (l.ifOverflow == IfOverflow.extendDomain && (axis.isX ? l.xAxisId : l.yAxisId) == s.id)
        axis.isX ? l.x : l.y,
  ]);
  final referenceElementsDomain =
      lineCoords.isEmpty ? null : <double>[lineCoords.reduce(math.min), lineCoords.reduce(math.max)];

  // combineNumericalDomain
  NumberDomain? numericalDomain;
  if (domainFromUserPreference != null) {
    numericalDomain = domainFromUserPreference;
  } else {
    final includeStacks = (layout == ChartLayout.vertical && axis.isX) || (layout == ChartLayout.horizontal && !axis.isX);
    final merged = includeStacks
        ? mergeDomains([domainOfStackGroups, referenceElementsDomain, dataDomain])
        : mergeDomains([referenceElementsDomain, dataDomain]);
    numericalDomain = parseNumericalUserDomain(domainDefinition, merged, s.allowDataOverflow);
    if (numericalDomain == null && s.allowDataOverflow && merged == null && axis.type == AxisDomainType.number) {
      final ticks = onlyAllowNumbers(s.ticks ?? const []);
      if (ticks.isNotEmpty) numericalDomain = [ticks.reduce(math.min), ticks.reduce(math.max)];
    }
  }

  // combineAxisDomain
  final isCategorical = axis.isCategorical;
  if (axis.displayedData.isEmpty && numericalDomain == null) {
    axis.domain = null;
  } else if (isCategorical && s.dataKey == null) {
    axis.domain = List<Object?>.generate(axis.displayedData.length, (i) => i);
  } else if (axis.type == AxisDomainType.category) {
    final categorical = applied.where((v) => isNumOrStr(v) || v is DateTime).toList();
    if (isCategorical && (s.dataKey == null || (s.allowDuplicatedCategory && hasDuplicate(categorical)))) {
      axis.domain = List<Object?>.generate(applied.length, (i) => i);
    } else if (s.allowDuplicatedCategory) {
      axis.domain = categorical;
    } else {
      axis.domain = categorical.toSet().toList();
    }
  } else if (ctx.stackOffset == StackOffset.expand && !isCategorical) {
    axis.domain = const [0.0, 1.0];
  } else {
    axis.domain = numericalDomain;
  }

  // combineRealScaleType
  axis.realScaleType = combineRealScaleType(s.scale, axis.type, ctx.hasBar, ctx.chartName);

  // combineNiceTicks
  axis.niceTicks = combineNiceTicks(axis.domain, s, axis.type, domainDefinition, axis.realScaleType);

  // combineAxisDomainWithNiceTicks
  final d = axis.domain;
  final nt = axis.niceTicks;
  if (axis.type == AxisDomainType.number && _isWellFormedNumberDomain(d) && nt != null && nt.isNotEmpty) {
    axis.domainWithNiceTicks = [
      math.min((d![0] as num).toDouble(), nt.first.toDouble()),
      math.max((d[1] as num).toDouble(), nt.last.toDouble()),
    ];
  } else {
    axis.domainWithNiceTicks = d;
  }

  // combineDuplicateDomain
  final allData = applied;
  final validData = allData.where((v) => v != null).toList();
  axis.duplicateDomain = s.dataKey != null &&
          isCategorical &&
          axis.type == AxisDomainType.category &&
          s.allowDuplicatedCategory &&
          hasDuplicate(validData)
      ? allData
      : null;

  // combineCategoricalDomain
  axis.categoricalDomain =
      s.dataKey != null && isCategorical && (axis.type == AxisDomainType.number || s.scale != 'auto') ? allData : null;
}

/// `implicitZAxis`: the axis of a [Scatter] whose ZAxis is missing.
const implicitZAxis = ZAxis(name: '', unit: '');

/// `selectZAxisWithScale`: the [ZAxis] and the scale of its domain (no nice
/// ticks) over its `range`; null when the domain is undefined, e.g. without a
/// dataKey. Only scatters carry a zAxisId, and ZAxis ignores stacks.
// ponytail: number ZAxis only; a category ZAxis gets no scale (default size).
({ZAxis settings, RechartsScale scale})? zAxisWithScale(ZAxis settings, ChartContext ctx) {
  final items = [
    for (final i in ctx.items)
      if (i.element case final Scatter s when s.zAxisId == settings.zAxisId && !i.hide) i,
  ];
  final itemsData = [for (final i in items) ...?i.data];
  final displayedData = itemsData.isNotEmpty ? itemsData : ctx.chartData;
  final definition = settings.domain ?? const <Object>[0, 'auto'];

  double? lowerEnd, upperEnd;
  void take(NumberDomain? d) {
    if (d == null) return;
    lowerEnd = lowerEnd == null ? d[0] : math.min(lowerEnd!, d[0]);
    upperEnd = upperEnd == null ? d[1] : math.max(upperEnd!, d[1]);
  }

  for (final item in items) {
    for (final entry in item.data ?? ctx.chartData) {
      take(_makeDomain(getValueByDataKey(entry, settings.dataKey ?? item.dataKey)));
    }
  }
  if (settings.dataKey != null && items.isEmpty) {
    for (final entry in displayedData) {
      take(_makeDomain(getValueByDataKey(entry, settings.dataKey)));
    }
  }
  final dataDomain =
      isWellBehavedNumber(lowerEnd) && isWellBehavedNumber(upperEnd) ? <double>[lowerEnd!, upperEnd!] : null;
  final numericalDomain = parseNumericalUserDomain(definition, dataDomain, false);
  if (displayedData.isEmpty && numericalDomain == null) return null;
  if (settings.type == AxisDomainType.category) return null;
  final domain = ctx.stackOffset == StackOffset.expand ? const [0.0, 1.0] : numericalDomain;
  final scale = buildScale(
      combineRealScaleType(settings.scale, settings.type, ctx.hasBar, ctx.chartName), domain, settings.range);
  return scale == null ? null : (settings: settings, scale: scale);
}

String? combineRealScaleType(String scale, AxisDomainType type, bool hasBar, String chartName) {
  if (scale == 'auto') {
    if (type == AxisDomainType.category &&
        (chartName.contains('LineChart') ||
            chartName.contains('AreaChart') ||
            (chartName.contains('ComposedChart') && !hasBar))) {
      return 'point';
    }
    if (type == AxisDomainType.category) return 'band';
    return 'linear';
  }
  const supported = {'linear', 'band', 'point', 'log', 'pow', 'sqrt', 'time', 'utc', 'identity', 'ordinal'};
  return supported.contains(scale) ? scale : 'point';
}

/// Recharts never returns from getNiceTickValues for tickCount <= 2 with a
/// domain spanning zero; the Dart port throws there, so treat it as "no nice ticks".
List<num>? _guard(List<num> Function() f) {
  try {
    return f();
  } catch (_) {
    return null;
  }
}

List<num>? combineNiceTicks(List<Object?>? axisDomain, CartesianAxisElement s, AxisDomainType type,
    Object domainDefinition, String? realScaleType) {
  if (s.niceTicks == NiceTicksAlgorithm.none) return null;
  final hasAuto = domainDefinition is List &&
      domainDefinition.length >= 2 &&
      (domainDefinition[0] == 'auto' || domainDefinition[1] == 'auto');
  final wellFormed = _isWellFormedNumberDomain(axisDomain);
  List<num> dom() => [axisDomain![0] as num, axisDomain[1] as num];
  final mode = s.niceTicks;
  if ((mode == NiceTicksAlgorithm.snap125 || mode == NiceTicksAlgorithm.adaptive) && s.tickCount != 0 && wellFormed) {
    if (hasAuto) {
      return _guard(() =>
          getNiceTickValues(dom(), tickCount: s.tickCount, allowDecimals: s.allowDecimals, niceTicksMode: mode));
    }
    if (type == AxisDomainType.number) {
      return _guard(() => getTickValuesFixedDomain(dom(),
          tickCount: s.tickCount, allowDecimals: s.allowDecimals, niceTicksMode: mode));
    }
  }
  if (mode == NiceTicksAlgorithm.auto && realScaleType == 'linear' && s.tickCount != 0) {
    if (hasAuto && wellFormed) {
      return _guard(() => getNiceTickValues(dom(),
          tickCount: s.tickCount, allowDecimals: s.allowDecimals, niceTicksMode: NiceTicksAlgorithm.adaptive));
    }
    if (type == AxisDomainType.number && wellFormed) {
      return _guard(() => getTickValuesFixedDomain(dom(),
          tickCount: s.tickCount, allowDecimals: s.allowDecimals, niceTicksMode: NiceTicksAlgorithm.adaptive));
    }
  }
  return null;
}

/// `selectSmallestDistanceBetweenValues`.
double? smallestDistanceBetweenValues(AxisRuntime axis) {
  if (axis.type != AxisDomainType.number) return null;
  final sorted = onlyAllowNumbers(axis.appliedValues)..sort();
  if (sorted.isEmpty) return double.infinity;
  final diff = sorted.last - sorted.first;
  if (diff == 0) return double.infinity;
  var smallest = double.infinity;
  for (var i = 0; i < sorted.length - 1; i++) {
    smallest = math.min(smallest, sorted[i + 1] - sorted[i]);
  }
  return smallest / diff;
}

/// `selectCalculatedPadding` for `'gap'` / `'no-gap'`.
double calculatedPadding(AxisRuntime axis, String padding, double rangeWidth, Object barCategoryGap) {
  final smallest = smallestDistanceBetweenValues(axis);
  if (!isWellBehavedNumber(smallest)) return 0;
  if (padding == 'gap') return smallest! * rangeWidth / 2;
  if (padding == 'no-gap') {
    final gap = getPercentValue(barCategoryGap, smallest! * rangeWidth);
    final halfBand = smallest * rangeWidth / 2;
    return halfBand - gap - ((halfBand - gap) / rangeWidth) * gap;
  }
  return 0;
}

/// Builds the d3 scale (`combineConfiguredScale` + `combineCheckedDomain`).
RechartsScale? buildScale(String? realScaleType, List<Object?>? domain, List<double>? rangeWithReverse) {
  if (domain == null || rangeWithReverse == null || realScaleType == null) return null;
  var checked = domain;
  if (realScaleType == 'linear' && !_isWellFormedNumberDomain(domain)) {
    final nums = domain.where(isWellBehavedNumber).map((v) => (v as num).toDouble()).toList();
    if (nums.isEmpty) return null;
    checked = [nums.reduce(math.min), nums.reduce(math.max)];
  }
  List<num> numeric() => [for (final v in checked) jsNumber(v)];
  switch (realScaleType) {
    case 'band':
      return BandScale(domain: checked, range: rangeWithReverse);
    case 'point':
    case 'ordinal':
      return PointScale(domain: checked, range: rangeWithReverse);
    case 'log':
      return LogScale(domain: numeric(), range: rangeWithReverse);
    case 'pow':
      return PowScale(domain: numeric(), range: rangeWithReverse);
    case 'sqrt':
      return PowScale(domain: numeric(), range: rangeWithReverse, exponent: 0.5);
    default:
      // ponytail: time/utc/identity use a linear scale; time ticks differ from d3's.
      return LinearScale(domain: numeric(), range: rangeWithReverse);
  }
}

/// `combineAxisTicks`.
List<TickItem>? combineAxisTicks(AxisRuntime axis) {
  final scale = axis.scale;
  if (scale == null) return null;
  final s = axis.settings;
  final bandwidth = scale.bandwidth;
  final offset = axis.type == AxisDomainType.category && bandwidth != null ? bandwidth / 2 : 0.0;
  final ticksOrNice = s.ticks ?? axis.niceTicks;
  if (ticksOrNice != null) {
    final out = <TickItem>[];
    for (var index = 0; index < ticksOrNice.length; index++) {
      final entry = ticksOrNice[index];
      final scaleContent = axis.duplicateDomain != null ? axis.duplicateDomain!.indexOf(entry) : entry;
      final scaled = scale.map(scaleContent);
      if (!isWellBehavedNumber(scaled)) continue;
      out.add(TickItem(index: index, coordinate: scaled! + offset, value: entry, offset: offset));
    }
    return out;
  }
  if (axis.isCategorical && axis.categoricalDomain != null) {
    return _mapEntries(axis.categoricalDomain!, scale, offset);
  }
  final scaleTicks = scale.ticks(s.tickCount);
  if (scaleTicks != null) return _mapEntries(scaleTicks, scale, offset);
  return _mapDomain(axis, scale, offset);
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

List<TickItem> _mapDomain(AxisRuntime axis, RechartsScale scale, double offset) {
  final out = <TickItem>[];
  final dom = scale.domain;
  for (var index = 0; index < dom.length; index++) {
    final entry = dom[index];
    final scaled = scale.map(entry);
    if (!isWellBehavedNumber(scaled)) continue;
    final dup = axis.duplicateDomain;
    final value = dup != null && entry is int && entry >= 0 && entry < dup.length ? dup[entry] : entry;
    out.add(TickItem(coordinate: scaled! + offset, value: value, index: index, offset: offset));
  }
  return out;
}

/// `combineGraphicalItemTicks`.
List<TickItem>? combineGraphicalItemTicks(AxisRuntime axis) {
  final scale = axis.scale;
  final range = axis.range;
  if (scale == null || range == null || range[0] == range[1]) return null;
  if (axis.isCategorical && axis.categoricalDomain != null) return _mapEntries(axis.categoricalDomain!, scale, 0);
  final scaleTicks = scale.ticks(axis.settings.tickCount);
  if (scaleTicks != null) return _mapEntries(scaleTicks, scale, 0);
  return _mapDomain(axis, scale, 0);
}

/// `getTicksOfAxis(axis, isGrid: true)` as CartesianGrid calls it.
List<TickItem>? getTicksOfAxisForGrid(AxisRuntime axis, List<Object>? ticksOverride) {
  final scale = axis.scale;
  if (scale == null) return null;
  final bandwidth = scale.bandwidth;
  final offset = axis.type == AxisDomainType.category && bandwidth != null ? bandwidth / 2 : 0.0;
  final ticks = ticksOverride ?? axis.settings.ticks;
  final List<Object?>? source = ticks ?? axis.niceTicks;
  if (source != null) {
    final out = <TickItem>[];
    for (var index = 0; index < source.length; index++) {
      final entry = source[index];
      final scaleContent = axis.duplicateDomain != null ? axis.duplicateDomain!.indexOf(entry) : entry;
      final scaled = scale.map(scaleContent);
      if (!isWellBehavedNumber(scaled)) continue;
      out.add(TickItem(coordinate: scaled! + offset, value: entry, offset: offset, index: index));
    }
    return out;
  }
  if (axis.isCategorical && axis.categoricalDomain != null) {
    return _mapEntries(axis.categoricalDomain!, scale, offset);
  }
  final scaleTicks = scale.ticks(axis.settings.tickCount);
  if (scaleTicks != null) return _mapEntries(scaleTicks, scale, offset);
  return _mapDomain(axis, scale, offset);
}

/// `getBandSizeOfAxis(axis, ticks, isBar)`.
double? getBandSizeOfAxis(RechartsScale? scale, List<TickItem>? ticks, [bool isBar = false]) {
  final bandwidth = scale?.bandwidth;
  if (bandwidth != null && (!isBar || bandwidth > 0)) return bandwidth;
  if (scale != null && ticks != null && ticks.length >= 2) {
    final ordered = sortByKey(ticks, (t) => t.coordinate);
    final gaps = <double>[];
    var maxGap = 0.0;
    for (var i = 1; i < ordered.length; i++) {
      final gap = ordered[i].coordinate - ordered[i - 1].coordinate;
      gaps.add(gap);
      maxGap = math.max(gap, maxGap);
    }
    final minMeaningfulGap = maxGap * 1e-4;
    var bandSize = double.infinity;
    for (final gap in gaps) {
      if (gap > minMeaningfulGap) bandSize = math.min(gap, bandSize);
    }
    return bandSize == double.infinity ? 0 : bandSize;
  }
  return isBar ? null : 0;
}

/// `getCoordinatesOfGrid`.
List<double> getCoordinatesOfGrid(List<TickItem> ticks, double minValue, double maxValue, bool syncWithTicks) {
  if (syncWithTicks) return [for (final t in ticks) t.coordinate];
  var hasMin = false, hasMax = false;
  final values = [
    for (final t in ticks) t.coordinate,
  ];
  for (final v in values) {
    if (v == minValue) hasMin = true;
    if (v == maxValue) hasMax = true;
  }
  if (!hasMin) values.add(minValue);
  if (!hasMax) values.add(maxValue);
  return values;
}
