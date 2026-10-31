// Child "components" of a cartesian chart. Like Recharts children they are
// plain configuration read by the chart, not widgets. Defaults are copied from
// each component's defaultProps (src/cartesian/XAxis.tsx, YAxis.tsx,
// CartesianAxis.tsx, CartesianGrid.tsx, Line.tsx, Bar.tsx, ReferenceLine.tsx,
// src/component/Tooltip.tsx, Legend.tsx, DefaultLegendContent.tsx) and from
// implicitXAxis/implicitYAxis in src/state/selectors/axisSelectors.ts.
//
// Dart typing notes (where JS is loose):
// * `dataKey` is an [Object]: a String/int path, or `Object? Function(Object? entry)`.
// * Colors are [Color] instead of CSS strings; `strokeDasharray` is `List<double>`.
// * `isAnimationActive` is `bool?`: `null` means Recharts' `'auto'`.
// * Durations are milliseconds (`int`), easing is anything `createEasingFunction` takes.
// * `tick`, `dot`, `activeDot`, `axisLine`, `cursor`, `background` keep Recharts'
//   "boolean or props or custom renderer" shape as an [Object]; see each field.

import 'package:flutter/widgets.dart';

import 'core/nice_ticks.dart';
import 'core/curve.dart';
import 'core/scale.dart';
import 'widgets/cartesian_chart.dart' show CategoricalChart;

/// Base class of everything that goes into a chart's `children`.
abstract class RechartsElement {
  const RechartsElement();
}

class Margin {
  const Margin({this.top = 0, this.right = 0, this.bottom = 0, this.left = 0});
  const Margin.all(double v) : top = v, right = v, bottom = v, left = v;
  final double top, right, bottom, left;

  @override
  bool operator ==(Object other) =>
      other is Margin && other.top == top && other.right == right && other.bottom == bottom && other.left == left;
  @override
  int get hashCode => Object.hash(top, right, bottom, left);
}

/// SVG presentation attributes Recharts lets you pass as an object
/// (e.g. `dot={{ r: 5 }}`, `cursor={{ stroke: 'red' }}`, `axisLine={{...}}`).
class SvgStyle {
  const SvgStyle({
    this.fill,
    this.fillOpacity,
    this.stroke,
    this.strokeWidth,
    this.strokeOpacity,
    this.strokeDasharray,
    this.r,
  });
  final Color? fill;
  final double? fillOpacity;
  final Color? stroke;
  final double? strokeWidth;
  final double? strokeOpacity;
  final List<double>? strokeDasharray;

  /// Circle radius, used by `dot` / `activeDot`.
  final double? r;
}

/// `interval` of an axis: a strategy name or a fixed number (`AxisInterval.number(0)`).
class AxisInterval {
  const AxisInterval._(this.name) : number = null;
  const AxisInterval.number(int this.number) : name = 'number';
  final String name;
  final int? number;

  static const preserveStart = AxisInterval._('preserveStart');
  static const preserveEnd = AxisInterval._('preserveEnd');
  static const preserveStartEnd = AxisInterval._('preserveStartEnd');
  static const equidistantPreserveStart = AxisInterval._('equidistantPreserveStart');
  static const equidistantPreserveEnd = AxisInterval._('equidistantPreserveEnd');
}

/// Axis `padding`: `{left, right}` for XAxis, `{top, bottom}` for YAxis, or
/// the `'gap'` / `'no-gap'` keywords ([AxisPadding.gap], [AxisPadding.noGap]).
class AxisPadding {
  const AxisPadding({this.left = 0, this.right = 0, this.top = 0, this.bottom = 0}) : mode = null;
  const AxisPadding._(this.mode) : left = 0, right = 0, top = 0, bottom = 0;
  static const gap = AxisPadding._('gap');
  static const noGap = AxisPadding._('no-gap');

  /// `'gap'`, `'no-gap'` or null for explicit numbers.
  final String? mode;
  final double left, right, top, bottom;
}

enum AxisDomainType { number, category, auto }

enum AxisOrientation { top, bottom, left, right }

enum TextAnchor { start, middle, end }

enum TextVerticalAnchor { start, middle, end }

enum LegendType { line, plainline, square, rect, circle, cross, diamond, star, triangle, wye, none }

enum StackOffset { none, sign, expand, positive, silhouette, wiggle }

enum IfOverflow { discard, hidden, visible, extendDomain }

enum HorizontalAlign { left, center, right }

enum VerticalAlign { top, middle, bottom }

enum TooltipTrigger { hover, click }

/// Values passed to a custom tick painter (Recharts' tick props).
class TickProps {
  const TickProps({
    required this.x,
    required this.y,
    required this.index,
    required this.value,
    required this.text,
    required this.textAnchor,
    required this.verticalAnchor,
    required this.angle,
    required this.fill,
    required this.style,
    required this.visibleTicksCount,
  });
  final double x, y;
  final int index;

  /// The tick's raw value (`payload.value`).
  final Object? value;

  /// Formatted label: `tickFormatter(value) + unit`.
  final String text;
  final TextAnchor textAnchor;
  final TextVerticalAnchor verticalAnchor;
  final double angle;
  final Color fill;
  final TextStyle style;
  final int visibleTicksCount;
}

typedef TickFormatter = String Function(Object? value, int index);
typedef TickPainter = void Function(Canvas canvas, TickProps props);

/// Values passed to a custom dot painter.
class DotProps {
  const DotProps({
    required this.cx,
    required this.cy,
    required this.r,
    required this.index,
    required this.value,
    required this.payload,
    required this.dataKey,
    this.fill,
    this.stroke,
    this.strokeWidth = 1,
  });
  final double cx, cy, r;
  final int index;
  final Object? value, payload, dataKey;
  final Color? fill, stroke;
  final double strokeWidth;
}

typedef DotPainter = void Function(Canvas canvas, DotProps props);

/// `position` of a [Label] / [LabelList] (src/cartesian/getCartesianPosition.tsx).
/// Cartesian boxes treat the polar-only names and `inside`/`outside` like [middle].
enum LabelPosition {
  top,
  left,
  right,
  bottom,
  inside,
  outside,
  insideLeft,
  insideRight,
  insideTop,
  insideBottom,
  insideTopLeft,
  insideBottomLeft,
  insideTopRight,
  insideBottomRight,
  insideStart,
  insideEnd,
  end,
  center,
  centerTop,
  centerBottom,
  middle,
}

/// Values passed to a custom label painter (the props Recharts gives `content`).
class LabelProps {
  const LabelProps({
    required this.x,
    required this.y,
    required this.viewBox,
    required this.value,
    required this.position,
    required this.offset,
    required this.angle,
    required this.style,
    this.index,
  });

  /// The position computed for [position], before anchoring.
  final double x, y;
  final Rect viewBox;
  final Object? value;
  final LabelPosition position;
  final double offset, angle;

  /// Text style with the label's `fill` (default `#808080`) and `fontSize`.
  final TextStyle style;

  /// Entry index inside a [LabelList].
  final int? index;
}

typedef LabelPainter = void Function(Canvas canvas, LabelProps props);

/// src/component/Label.tsx. Pass it as `label` to [XAxis], [YAxis] or [ReferenceLine].
class Label {
  const Label({
    this.value,
    this.position = LabelPosition.middle,
    this.offset = 5,
    this.angle = 0,
    this.fill,
    this.fontSize,
    this.textAnchor,
    this.width,
    this.textBreakAll = false,
    this.formatter,
    this.content,
  });

  /// String, num or bool; nothing is drawn when null (unless [content] is set).
  final Object? value;
  final LabelPosition position;
  final double offset;

  /// Rotation in degrees around the label's anchor point.
  final double angle;

  /// Text fill, default `#808080`.
  final Color? fill;
  final double? fontSize;

  /// Overrides the anchor the position picks.
  final TextAnchor? textAnchor;

  /// Wraps the text at this width (`Text` `width`).
  final double? width;
  final bool textBreakAll;
  final Object? Function(Object? value)? formatter;
  final LabelPainter? content;
}

/// Input of [LabelList.valueAccessor] (`CartesianLabelListEntry`).
class LabelListEntry {
  const LabelListEntry({required this.value, required this.payload, required this.viewBox, this.fill, this.parentViewBox});

  /// The item's value; `[start, end]` for stacked bars.
  final Object? value;
  final Object? payload;

  /// The bar rectangle, or a zero-size box at the line point.
  final Rect viewBox;
  final Color? fill;

  /// The chart box for bars, null for lines.
  final Rect? parentViewBox;
}

/// src/component/LabelList.tsx: one [Label] per data point of the enclosing
/// [Line] or [Bar]. Labels are hidden while the series animates.
class LabelList extends RechartsElement {
  const LabelList({
    this.dataKey,
    this.valueAccessor,
    this.position = LabelPosition.middle,
    this.offset = 5,
    this.angle = 0,
    this.fill,
    this.fontSize,
    this.textBreakAll = false,
    this.formatter,
    this.content,
  });

  /// Reads the label from each entry's payload; overrides [valueAccessor].
  final Object? dataKey;

  /// Defaults to the entry's value (the last element of a `[start, end]` pair).
  final Object? Function(LabelListEntry entry, int index)? valueAccessor;
  final LabelPosition position;
  final double offset;
  final double angle;

  /// Text fill; falls back to the entry's (a [Cell]'s) fill, then `#808080`.
  final Color? fill;
  final double? fontSize;
  final bool textBreakAll;
  final Object? Function(Object? value)? formatter;
  final LabelPainter? content;
}

/// Shared props of [XAxis] and [YAxis] (`BaseCartesianAxis` + CartesianAxis props).
abstract class CartesianAxisElement extends RechartsElement {
  const CartesianAxisElement({
    required this.id,
    this.dataKey,
    required this.type,
    this.domain,
    this.allowDataOverflow = false,
    this.allowDecimals = true,
    this.allowDuplicatedCategory = true,
    this.angle = 0,
    this.hide = false,
    this.includeHidden = false,
    this.interval = AxisInterval.preserveEnd,
    this.minTickGap = 5,
    this.mirror = false,
    required this.orientation,
    required this.padding,
    this.reversed = false,
    this.scale = 'auto',
    this.tick = true,
    this.tickCount = 5,
    this.tickFormatter,
    this.ticks,
    this.unit,
    this.name,
    this.niceTicks = NiceTicksAlgorithm.auto,
    this.axisLine = true,
    this.tickLine = true,
    this.tickSize = 6,
    this.tickMargin = 2,
    this.stroke = const Color(0xFF666666),
    this.textAnchor,
    this.fontSize,
    this.label,
  });

  /// `xAxisId` / `yAxisId` (String or int).
  final Object id;
  final Object? dataKey;
  final AxisDomainType type;

  /// `[min, max]` where each side is a num, `'auto'`, `'dataMin'`, `'dataMax'`,
  /// `'dataMin - 5'`, `'dataMax + 5'` or `num Function(num dataBound)`; a list of
  /// categories for category axes; or a whole-domain function
  /// `List<num> Function(List<num> dataDomain, bool allowDataOverflow)`.
  final Object? domain;
  final bool allowDataOverflow;
  final bool allowDecimals;
  final bool allowDuplicatedCategory;
  final double angle;
  final bool hide;
  final bool includeHidden;
  final AxisInterval interval;
  final double minTickGap;
  final bool mirror;
  final AxisOrientation orientation;
  final AxisPadding padding;
  final bool reversed;

  /// `'auto'`, `'linear'`, `'band'`, `'point'`, `'log'`, `'pow'` or `'sqrt'`.
  final String scale;

  /// `true`/`false`, a [TextStyle] merged over the tick text (Recharts' tick
  /// props object), or a [TickPainter] drawing the whole tick.
  final Object tick;
  final int tickCount;
  final TickFormatter? tickFormatter;
  final List<Object>? ticks;
  final String? unit;
  final String? name;
  final NiceTicksAlgorithm niceTicks;

  /// `true`/`false` or an [SvgStyle].
  final Object axisLine;

  /// `true`/`false` or an [SvgStyle].
  final Object tickLine;
  final double tickSize;
  final double tickMargin;

  /// Axis line, tick line and tick text color (Recharts `stroke`, default `#666`).
  final Color stroke;

  /// Overrides the orientation-based tick `textAnchor`.
  final TextAnchor? textAnchor;
  final double? fontSize;

  /// A String, a num or a [Label], drawn in the axis box. It never changes the
  /// axis size, except through `YAxis(width: 'auto')`.
  final Object? label;

  bool get isX;
}

class XAxis extends CartesianAxisElement {
  const XAxis({
    Object xAxisId = 0,
    super.dataKey,
    super.type = AxisDomainType.category,
    super.domain,
    super.allowDataOverflow,
    super.allowDecimals,
    super.allowDuplicatedCategory,
    super.angle,
    this.height = 30,
    super.hide,
    super.includeHidden,
    super.interval,
    super.minTickGap,
    super.mirror,
    super.orientation = AxisOrientation.bottom,
    super.padding = const AxisPadding(left: 0, right: 0),
    super.reversed,
    super.scale,
    super.tick,
    super.tickCount,
    super.tickFormatter,
    super.ticks,
    super.unit,
    super.name,
    super.niceTicks,
    super.axisLine,
    super.tickLine,
    super.tickSize,
    super.tickMargin,
    super.stroke,
    super.textAnchor,
    super.fontSize,
    super.label,
  }) : super(id: xAxisId);

  Object get xAxisId => id;
  final double height;

  @override
  bool get isX => true;
}

class YAxis extends CartesianAxisElement {
  const YAxis({
    Object yAxisId = 0,
    super.dataKey,
    super.type = AxisDomainType.number,
    super.domain,
    super.allowDataOverflow,
    super.allowDecimals,
    super.allowDuplicatedCategory,
    super.angle,
    this.width = 60,
    super.hide,
    super.includeHidden,
    super.interval,
    super.minTickGap,
    super.mirror,
    super.orientation = AxisOrientation.left,
    super.padding = const AxisPadding(top: 0, bottom: 0),
    super.reversed,
    super.scale,
    super.tick,
    super.tickCount,
    super.tickFormatter,
    super.ticks,
    super.unit,
    super.name,
    super.niceTicks,
    super.axisLine,
    super.tickLine,
    super.tickSize,
    super.tickMargin,
    super.stroke,
    super.textAnchor,
    super.fontSize,
    super.label,
  })  : assert(width is num || width == 'auto'),
        super(id: yAxisId);

  Object get yAxisId => id;

  /// A number, or `'auto'` to size the axis to its widest tick label plus
  /// `tickSize + tickMargin`, plus the label and a 5px gap when [label] is set
  /// (`getCalculatedYAxisWidth`). Until measured, `'auto'` counts as 60.
  final Object width;

  @override
  bool get isX => false;
}

class CartesianGrid extends RechartsElement {
  const CartesianGrid({
    this.horizontal = true,
    this.vertical = true,
    this.horizontalPoints = const [],
    this.verticalPoints = const [],
    this.horizontalValues,
    this.verticalValues,
    this.fill,
    this.fillOpacity,
    this.horizontalFill = const [],
    this.verticalFill = const [],
    this.stroke = const Color(0xFFCCCCCC),
    this.strokeWidth = 1,
    this.strokeDasharray,
    this.syncWithTicks = false,
    this.xAxisId = 0,
    this.yAxisId = 0,
    this.x,
    this.y,
    this.width,
    this.height,
  });

  /// `true`/`false` or an [SvgStyle] for horizontal lines.
  final Object horizontal;

  /// `true`/`false` or an [SvgStyle] for vertical lines.
  final Object vertical;
  final List<double> horizontalPoints;
  final List<double> verticalPoints;
  final List<Object>? horizontalValues;
  final List<Object>? verticalValues;
  final Color? fill;
  final double? fillOpacity;
  final List<Color> horizontalFill;
  final List<Color> verticalFill;

  /// Default comes from the legacy theme (`grid.stroke: '#ccc'`).
  final Color stroke;
  final double strokeWidth;
  final List<double>? strokeDasharray;
  final bool syncWithTicks;
  final Object xAxisId;
  final Object yAxisId;
  final double? x, y, width, height;
}

/// Shared props of [Line] and [Bar].
abstract class CartesianSeries extends RechartsElement {
  const CartesianSeries({
    required this.dataKey,
    this.xAxisId = 0,
    this.yAxisId = 0,
    this.name,
    this.unit,
    this.hide = false,
    required this.legendType,
    this.tooltipType,
    this.formatter,
    this.isAnimationActive,
    this.animationBegin = 0,
    required this.animationDuration,
    this.animationEasing = 'ease',
    this.onAnimationStart,
    this.onAnimationEnd,
    this.id,
  });
  final Object dataKey;
  final Object xAxisId;
  final Object yAxisId;
  final Object? name;
  final String? unit;
  final bool hide;
  final LegendType legendType;

  /// Recharts' `tooltipType="none"` is `tooltipType: 'none'` here.
  final String? tooltipType;
  final TooltipFormatter? formatter;

  /// `null` is Recharts' `'auto'`: animate unless [MediaQueryData.disableAnimations].
  final bool? isAnimationActive;
  final int animationBegin;
  final int animationDuration;
  final Object animationEasing;
  final VoidCallback? onAnimationStart;
  final VoidCallback? onAnimationEnd;

  /// Stable identity for animations when the children list changes shape.
  final String? id;

  Object? get itemData => null;
  Object? get stackIdOrNull => null;
  Color? get tooltipColor;
}

class Line extends CartesianSeries {
  const Line({
    required super.dataKey,
    super.xAxisId,
    super.yAxisId,
    this.type = CurveType.linear,
    this.stroke = const Color(0xFF3182BD),
    this.strokeWidth = 1,
    this.strokeDasharray,
    this.fill = const Color(0xFFFFFFFF),
    this.dot = true,
    this.activeDot = true,
    this.connectNulls = false,
    super.hide,
    super.legendType = LegendType.line,
    super.name,
    super.unit,
    super.tooltipType,
    super.formatter,
    this.data,
    super.isAnimationActive,
    super.animationBegin,
    super.animationDuration = 1500,
    super.animationEasing,
    this.animateNewValues = true,
    super.onAnimationStart,
    super.onAnimationEnd,
    super.id,
    this.label = false,
    this.children = const [],
  });
  final CurveType type;
  final Color? stroke;
  final double strokeWidth;
  final List<double>? strokeDasharray;

  /// Dot fill (Line's `fill` prop, default `#fff`).
  final Color? fill;

  /// `true`/`false`, an [SvgStyle], or a [DotPainter].
  final Object dot;

  /// `true`/`false`, an [SvgStyle], or a [DotPainter].
  final Object activeDot;
  final bool connectNulls;
  final List<Object?>? data;
  final bool animateNewValues;

  /// `true`, a [LabelList], or a [LabelPainter] drawing each label.
  final Object label;

  /// [LabelList]s.
  final List<RechartsElement> children;

  @override
  Object? get itemData => data;
  @override
  Color? get tooltipColor => stroke;
}

class Bar extends CartesianSeries {
  const Bar({
    required super.dataKey,
    super.xAxisId,
    super.yAxisId,
    this.stackId,
    this.barSize,
    this.maxBarSize,
    this.minPointSize = 0,
    this.fill,
    this.fillOpacity,
    this.stroke,
    this.strokeWidth,
    this.radius = 0,
    this.background = false,
    super.hide,
    super.legendType = LegendType.rect,
    super.name,
    super.unit,
    super.tooltipType,
    super.formatter,
    super.isAnimationActive,
    super.animationBegin,
    super.animationDuration = 400,
    super.animationEasing,
    super.onAnimationStart,
    super.onAnimationEnd,
    super.id,
    this.label = false,
    this.children = const [],
  });

  /// String or int; bars sharing it stack.
  final Object? stackId;

  /// Number or percent string such as `'20%'`.
  final Object? barSize;
  final double? maxBarSize;

  /// A number or `num Function(num? value, int index)`.
  final Object minPointSize;

  /// Bar has no default fill in Recharts, so SVG paints it black.
  final Color? fill;
  final double? fillOpacity;
  final Color? stroke;
  final double? strokeWidth;

  /// A number or `[topLeft, topRight, bottomRight, bottomLeft]`.
  final Object radius;

  /// `true`/`false` or an [SvgStyle] (default background fill `#eee`).
  final Object background;

  /// `true`, a [LabelList], or a [LabelPainter] drawing each label.
  final Object label;

  /// [Cell]s (matched to entries by index) and [LabelList]s.
  final List<RechartsElement> children;

  List<Cell> get cells => children.whereType<Cell>().toList();

  @override
  Object? get stackIdOrNull => stackId;
  @override
  Color? get tooltipColor => fill;
}

/// Per-entry overrides inside a [Bar].
class Cell extends RechartsElement {
  const Cell({this.fill, this.fillOpacity, this.stroke, this.strokeWidth});
  final Color? fill;
  final double? fillOpacity;
  final Color? stroke;
  final double? strokeWidth;
}

class ReferenceLine extends RechartsElement {
  const ReferenceLine({
    this.x,
    this.y,
    this.xAxisId = 0,
    this.yAxisId = 0,
    this.ifOverflow = IfOverflow.discard,
    this.stroke = const Color(0xFFCCCCCC),
    this.strokeWidth = 1,
    this.strokeDasharray,
    this.label,
    this.position = BandPosition.middle,
  });
  final Object? x;
  final Object? y;
  final Object xAxisId;
  final Object yAxisId;
  final IfOverflow ifOverflow;
  final Color stroke;
  final double strokeWidth;
  final List<double>? strokeDasharray;

  /// A String, a num or a [Label], positioned in the line's box.
  final Object? label;
  final BandPosition position;
}

/// One row of the tooltip (`TooltipPayloadEntry`).
class TooltipPayloadEntry {
  const TooltipPayloadEntry({
    required this.dataKey,
    required this.name,
    required this.value,
    required this.payload,
    this.color,
    this.fill,
    this.stroke,
    this.unit,
    this.hide = false,
    this.type,
    this.formatter,
  });
  final Object? dataKey;
  final String? name;
  final Object? value;
  final Object? payload;
  final Color? color;
  final Color? fill;
  final Color? stroke;
  final String? unit;
  final bool hide;
  final String? type;
  final TooltipFormatter? formatter;
}

/// Returns a formatted value, or a `[value, name]` list, or null to hide the row.
typedef TooltipFormatter = Object? Function(
    Object? value, String? name, TooltipPayloadEntry entry, int index, List<TooltipPayloadEntry> payload);

/// Props handed to a custom tooltip `content` builder.
class TooltipContentProps {
  const TooltipContentProps({
    required this.active,
    required this.payload,
    required this.label,
    required this.coordinate,
    required this.activeIndex,
  });
  final bool active;
  final List<TooltipPayloadEntry> payload;
  final Object? label;
  final Offset? coordinate;
  final int? activeIndex;
}

/// Box style of the default tooltip (`contentStyle` in CSS terms).
class TooltipContentStyle {
  const TooltipContentStyle({
    this.padding = const EdgeInsets.all(10),
    this.backgroundColor = const Color(0xFFFFFFFF),
    this.border = const Border.fromBorderSide(BorderSide(color: Color(0xFFCCCCCC))),
    this.borderRadius,
  });
  final EdgeInsets padding;
  final Color backgroundColor;
  final BoxBorder? border;
  final BorderRadius? borderRadius;
}

/// Named [Tooltip] like Recharts; it clashes with material's Tooltip, so use
/// `import 'package:flutter/material.dart' hide Tooltip;`.
class Tooltip extends RechartsElement {
  const Tooltip({
    this.active,
    this.allowEscapeViewBox = const (x: false, y: false),
    this.animationDuration = 400,
    this.animationEasing = 'ease',
    this.axisId = 0,
    this.content,
    this.contentStyle = const TooltipContentStyle(),
    this.cursor = true,
    this.defaultIndex,
    this.filterNull = true,
    this.formatter,
    this.includeHidden = false,
    this.isAnimationActive,
    this.itemSorter = 'name',
    this.itemStyle,
    this.labelFormatter,
    this.labelStyle,
    this.offset = 10,
    this.position,
    this.reverseDirection = const (x: false, y: false),
    this.separator = ' : ',
    this.shared,
    this.trigger = TooltipTrigger.hover,
  });
  final bool? active;
  final ({bool x, bool y}) allowEscapeViewBox;
  final int animationDuration;
  final Object animationEasing;
  final Object axisId;
  final Widget Function(TooltipContentProps props)? content;
  final TooltipContentStyle contentStyle;

  /// `true`/`false` or an [SvgStyle].
  final Object cursor;
  final int? defaultIndex;
  final bool filterNull;
  final TooltipFormatter? formatter;
  final bool includeHidden;

  /// `null` is `'auto'`.
  final bool? isAnimationActive;

  /// `'name'`, `'value'`, `'dataKey'`, `Object? Function(TooltipPayloadEntry)` or null.
  final Object? itemSorter;
  final TextStyle? itemStyle;
  final Object? Function(Object? label, List<TooltipPayloadEntry> payload)? labelFormatter;
  final TextStyle? labelStyle;
  final double offset;
  final ({double? x, double? y})? position;
  final ({bool x, bool y}) reverseDirection;
  final String separator;
  final bool? shared;
  final TooltipTrigger trigger;
}

/// One legend row (`LegendPayload`).
class LegendPayload {
  const LegendPayload({
    required this.value,
    required this.type,
    required this.color,
    required this.dataKey,
    this.inactive = false,
    this.strokeDasharray,
  });
  final String? value;
  final LegendType type;
  final Color? color;
  final Object? dataKey;
  final bool inactive;
  final List<double>? strokeDasharray;
}

class Legend extends RechartsElement {
  const Legend({
    this.align = HorizontalAlign.center,
    this.verticalAlign = VerticalAlign.bottom,
    this.layout,
    this.iconSize = 14,
    this.iconType,
    this.inactiveColor = const Color(0xFFCCCCCC),
    this.itemSorter = 'value',
    this.formatter,
    this.content,
    this.width,
    this.height,
    this.labelStyle,
  });
  final HorizontalAlign align;
  final VerticalAlign verticalAlign;

  /// `null` is `'auto'` (horizontal).
  final ChartLayout? layout;
  final double iconSize;
  final LegendType? iconType;
  final Color inactiveColor;

  /// `'value'`, `'dataKey'`, `Object? Function(LegendPayload)` or null.
  final Object? itemSorter;
  final Object? Function(String? value, LegendPayload entry, int index)? formatter;
  final Widget Function(List<LegendPayload> payload)? content;
  final double? width;
  final double? height;
  final TextStyle? labelStyle;
}

/// `BrushStartEndIndex`: the data slice a [Brush] selects, both ends inclusive.
typedef BrushStartEndIndex = ({int startIndex, int endIndex});

/// Props handed to a custom [Brush.traveller] painter (`TravellerProps`).
class BrushTravellerProps {
  const BrushTravellerProps({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.fill,
    this.stroke,
  });
  final double x, y, width, height;
  final Color? fill, stroke;
}

typedef BrushTravellerPainter = void Function(Canvas canvas, BrushTravellerProps props);

/// src/cartesian/Brush.tsx, defaults from `defaultBrushProps`.
///
/// [child] is the panorama: a chart rendered inside the brush over the full
/// data (Recharts' single chart child).
class Brush extends RechartsElement {
  const Brush({
    this.dataKey,
    this.x,
    this.y,
    this.dy,
    this.width,
    this.height = 40,
    this.travellerWidth = 5,
    this.traveller,
    this.gap = 1,
    this.fill = const Color(0xFFFFFFFF),
    this.stroke = const Color(0xFF666666),
    this.padding = const Margin.all(1),
    this.startIndex,
    this.endIndex,
    this.tickFormatter,
    this.onChange,
    this.onDragEnd,
    this.leaveTimeOut = 1000,
    this.alwaysShowText = false,
    this.ariaLabel,
    this.child,
  });

  /// Picks the start/end label from each data entry.
  final Object? dataKey;

  /// Default to the plot area's left / below the bottom axes / plot width.
  final double? x, y, width;
  final double? dy;
  final double height;
  final double travellerWidth;
  final BrushTravellerPainter? traveller;
  final int gap;
  final Color? fill;
  final Color? stroke;

  /// Margin of the panorama chart.
  final Margin padding;
  final int? startIndex;
  final int? endIndex;
  final TickFormatter? tickFormatter;
  final void Function(BrushStartEndIndex range)? onChange;
  final void Function(BrushStartEndIndex range)? onDragEnd;

  /// Milliseconds a drag survives without moves after leaving the brush.
  final int leaveTimeOut;
  final bool alwaysShowText;
  final String? ariaLabel;
  final CategoricalChart? child;
}

/// Event payload of chart-level mouse handlers (`MouseHandlerDataParam`).
class ChartEventState {
  const ChartEventState({
    this.activeCoordinate,
    this.activeDataKey,
    this.activeIndex,
    this.activeLabel,
    this.activeTooltipIndex,
    this.isTooltipActive = false,
  });
  final Offset? activeCoordinate;
  final Object? activeDataKey;

  /// Recharts uses string indexes; these are ints.
  final int? activeIndex;
  final Object? activeLabel;
  final int? activeTooltipIndex;
  final bool isTooltipActive;
}

typedef ChartEventHandler = void Function(ChartEventState state, PointerEvent event);
