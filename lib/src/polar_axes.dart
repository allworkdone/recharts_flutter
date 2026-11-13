// Polar child components: src/polar/PolarGrid.tsx, PolarAngleAxis.tsx,
// PolarRadiusAxis.tsx, Radar.tsx and RadialBar.tsx, with the defaults of
// defaultPolarGridProps, defaultPolarAngleAxisProps,
// defaultPolarRadiusAxisProps, defaultRadarProps and defaultRadialBarProps.
// Typing follows polar_components.dart: colors are [Color], `null` for an
// SVG attribute that Recharts leaves undefined (no stroke, 'none' fill),
// `isAnimationActive: null` is `'auto'`, durations are milliseconds.

import 'package:flutter/widgets.dart';

import 'components.dart';
import 'core/nice_ticks.dart';
import 'engine/polar_items.dart' show RadarPoint, RadialBarSector;
import 'polar_components.dart';

/// `gridType` of [PolarGrid].
enum PolarGridType { polygon, circle }

/// `axisLineType` of [PolarAngleAxis].
enum PolarAxisLineType { polygon, circle }

/// `orientation` of [PolarAngleAxis].
enum PolarAngleOrientation { inner, outer }

/// `orientation` of [PolarRadiusAxis].
enum PolarRadiusOrientation { left, right, middle }

/// src/polar/PolarGrid.tsx. [polarAngles] and [polarRadius] replace the
/// axes' ticks.
class PolarGrid extends RechartsElement {
  const PolarGrid({
    this.polarAngles,
    this.polarRadius,
    this.gridType = PolarGridType.polygon,
    this.radialLines = true,
    this.angleAxisId = 0,
    this.radiusAxisId = 0,
    this.stroke = const Color(0xFFCCCCCC),
    this.strokeWidth = 1,
    this.strokeOpacity,
    this.strokeDasharray,
    this.fill,
    this.fillOpacity,
    this.zIndex = -100,
  });
  final List<double>? polarAngles;
  final List<double>? polarRadius;
  final PolarGridType gridType;
  final bool radialLines;
  final Object angleAxisId, radiusAxisId;
  final Color? stroke;
  final double strokeWidth;
  final double? strokeOpacity;
  final List<double>? strokeDasharray;

  /// `'none'` by default.
  final Color? fill;
  final double? fillOpacity;

  /// Recharts' z layer (`grid`, -100): higher layers paint on top.
  final int zIndex;
}

/// src/polar/PolarAngleAxis.tsx. Its defaults carry no `stroke`, so the axis
/// and tick lines draw only when [stroke] (or an [SvgStyle]) is given; tick
/// text is Text's default `#808080` unless [stroke] is set.
class PolarAngleAxis extends RechartsElement {
  const PolarAngleAxis({
    this.angleAxisId = 0,
    this.dataKey,
    this.type = AxisDomainType.auto,
    this.domain,
    this.scale = 'auto',
    this.ticks,
    this.tick = true,
    this.tickLine = true,
    this.tickSize = 8,
    this.tickCount,
    this.tickFormatter,
    this.axisLine = true,
    this.axisLineType = PolarAxisLineType.polygon,
    this.orientation = PolarAngleOrientation.outer,
    this.reversed = false,
    this.allowDecimals = false,
    this.niceTicks = NiceTicksAlgorithm.auto,
    this.name,
    this.stroke,
    this.strokeWidth,
    this.fontSize,
    this.zIndex = 500,
  });
  final Object angleAxisId;
  final Object? dataKey;
  final AxisDomainType type;

  /// Same forms as [CartesianAxisElement.domain].
  final Object? domain;
  final String scale;
  final List<Object>? ticks;

  /// `true`/`false`, a [TextStyle] merged over the tick text, or a [TickPainter].
  final Object tick;

  /// `true`/`false` or an [SvgStyle].
  final Object tickLine;
  final double tickSize;
  final int? tickCount;
  final TickFormatter? tickFormatter;

  /// `true`/`false` or an [SvgStyle].
  final Object axisLine;
  final PolarAxisLineType axisLineType;
  final PolarAngleOrientation orientation;
  final bool reversed;
  final bool allowDecimals;
  final NiceTicksAlgorithm niceTicks;
  final Object? name;
  final Color? stroke;
  final double? strokeWidth;
  final double? fontSize;

  /// Recharts' z layer (`axis`, 500): higher layers paint on top.
  final int zIndex;
}

/// src/polar/PolarRadiusAxis.tsx.
class PolarRadiusAxis extends RechartsElement {
  const PolarRadiusAxis({
    this.radiusAxisId = 0,
    this.dataKey,
    this.type = AxisDomainType.auto,
    this.domain,
    this.scale = 'auto',
    this.angle = 0,
    this.orientation = PolarRadiusOrientation.right,
    this.ticks,
    this.tick = true,
    this.tickCount = 5,
    this.tickFormatter,
    this.axisLine = true,
    this.reversed = false,
    this.allowDecimals = false,
    this.allowDuplicatedCategory = true,
    this.allowDataOverflow = false,
    this.includeHidden = false,
    this.niceTicks = NiceTicksAlgorithm.auto,
    this.label,
    this.name,
    this.stroke = const Color(0xFFCCCCCC),
    this.fontSize,
    this.zIndex = 500,
  });
  final Object radiusAxisId;
  final Object? dataKey;
  final AxisDomainType type;
  final Object? domain;
  final String scale;

  /// Degrees, counter-clockwise from 3 o'clock.
  final double angle;
  final PolarRadiusOrientation orientation;
  final List<Object>? ticks;

  /// `true`/`false`, a [TextStyle] merged over the tick text, or a [TickPainter].
  final Object tick;
  final int tickCount;
  final TickFormatter? tickFormatter;

  /// `true`/`false` or an [SvgStyle].
  final Object axisLine;
  final bool reversed;
  final bool allowDecimals;
  final bool allowDuplicatedCategory;
  final bool allowDataOverflow;
  final bool includeHidden;
  final NiceTicksAlgorithm niceTicks;

  /// A String, a num, a [Label] or a [LabelPainter], drawn in the axis'
  /// polar view box (the ticks' extent along [angle]).
  final Object? label;
  final Object? name;

  /// Axis line color and tick text fill (`#ccc`).
  final Color? stroke;
  final double? fontSize;

  /// Recharts' z layer (`axis`, 500): higher layers paint on top.
  final int zIndex;
}

/// Props handed to a custom [Radar.shape] painter.
class RadarShapeProps {
  const RadarShapeProps({required this.points, required this.baseLinePoints, required this.fill, required this.stroke});
  final List<Offset> points;
  final List<Offset> baseLinePoints;
  final Color? fill, stroke;
}

typedef RadarShapePainter = void Function(Canvas canvas, RadarShapeProps props);

/// What a [Radar] handler receives (`InternalRadarProps`): the item and its points.
class RadarEventProps {
  const RadarEventProps({required this.radar, required this.points, required this.baseLinePoints, required this.isRange});
  final Radar radar;
  final List<RadarPoint> points, baseLinePoints;
  final bool isRange;
}

/// `onMouseEnter` / `onMouseLeave` of the Radar polygon.
typedef RadarEventHandler = void Function(RadarEventProps props, PointerEvent event);

/// `onMouseEnter`, `onMouseLeave`, `onClick` and the touch handlers of a RadialBar sector.
typedef RadialBarEventHandler = void Function(RadialBarSector data, int index, PointerEvent event);

/// src/polar/Radar.tsx. Like SVG, an undefined `fill` (null) paints black
/// (pass a transparent color for `none`) and an undefined `stroke` paints
/// nothing; the legend, tooltip row and active dot see the raw null.
class Radar extends RechartsElement {
  const Radar({
    required this.dataKey,
    this.angleAxisId = 0,
    this.radiusAxisId = 0,
    this.name,
    this.hide = false,
    this.legendType = LegendType.rect,
    this.tooltipType,
    this.dot = false,
    this.activeDot = true,
    this.label = false,
    this.connectNulls = false,
    this.fill,
    this.fillOpacity,
    this.stroke,
    this.strokeWidth,
    this.strokeOpacity,
    this.strokeDasharray,
    this.shape,
    this.onClick,
    this.onMouseEnter,
    this.onMouseLeave,
    this.onMouseOver,
    this.onMouseMove,
    this.onMouseOut,
    this.onTouchStart,
    this.onTouchMove,
    this.onTouchEnd,
    this.isAnimationActive,
    this.animationBegin = 0,
    this.animationDuration = 1500,
    this.animationEasing = 'ease',
    this.onAnimationStart,
    this.onAnimationEnd,
    this.id,
    this.zIndex = 100,
    this.children = const [],
  });
  final Object dataKey;
  final Object angleAxisId, radiusAxisId;
  final Object? name;
  final bool hide;
  final LegendType legendType;
  final String? tooltipType;

  /// Polygon events: a click on its fill or stroke, and the pointer entering or leaving it.
  final void Function(PointerEvent event)? onClick;
  final RadarEventHandler? onMouseEnter, onMouseLeave;

  /// The polygon's DOM events (svgPropertiesAndEvents): the pointer over it,
  /// moving on it and leaving it, and touches that start on it (touchmove
  /// and touchend keep going to it after the finger leaves it).
  final void Function(PointerEvent event)? onMouseOver, onMouseMove, onMouseOut, onTouchStart, onTouchMove, onTouchEnd;

  /// `true`/`false`, an [SvgStyle], or a [DotPainter].
  final Object dot;

  /// `true`/`false`, an [SvgStyle], or a [DotPainter].
  final Object activeDot;

  /// `true`, a [LabelList], or a [LabelPainter] drawing each label.
  final Object label;
  final bool connectNulls;
  final Color? fill;
  final double? fillOpacity;
  final Color? stroke;
  final double? strokeWidth;
  final double? strokeOpacity;
  final List<double>? strokeDasharray;

  /// Draws the polygon instead of the default [Polygon].
  final RadarShapePainter? shape;
  final bool? isAnimationActive;
  final int animationBegin;
  final int animationDuration;
  final Object animationEasing;
  final VoidCallback? onAnimationStart;
  final VoidCallback? onAnimationEnd;
  final String? id;

  /// Recharts' z layer (`area`, 100): higher layers paint on top.
  final int zIndex;

  /// [LabelList]s.
  final List<RechartsElement> children;
}

/// src/polar/RadialBar.tsx. A sector's fill comes from its data entry, then
/// its [Cell], over [fill].
class RadialBar extends RechartsElement {
  const RadialBar({
    required this.dataKey,
    this.angleAxisId = 0,
    this.radiusAxisId = 0,
    this.stackId,
    this.barSize,
    this.maxBarSize,
    this.minPointSize = 0,
    this.background = false,
    this.cornerRadius = 0,
    this.cornerIsExternal = false,
    this.forceCornerRadius = false,
    this.label = false,
    this.legendType = LegendType.rect,
    this.name,
    this.hide = false,
    this.tooltipType,
    this.formatter,
    this.fill,
    this.fillOpacity,
    this.stroke,
    this.strokeWidth,
    this.strokeOpacity,
    this.activeShape,
    this.shape,
    this.onClick,
    this.onMouseEnter,
    this.onMouseLeave,
    this.onTouchStart,
    this.onTouchMove,
    this.onTouchEnd,
    this.isAnimationActive,
    this.animationBegin = 0,
    this.animationDuration = 1500,
    this.animationEasing = 'ease',
    this.onAnimationStart,
    this.onAnimationEnd,
    this.id,
    this.zIndex = 300,
    this.children = const [],
  });
  final Object dataKey;
  final Object angleAxisId, radiusAxisId;

  /// String or int; bars sharing it stack.
  final Object? stackId;

  /// A number. Recharts' polar bar generator has no axis size, so a percent
  /// `barSize` resolves to zero thickness there as well.
  final num? barSize;
  final double? maxBarSize;
  final double minPointSize;

  /// `true`, `false` or a [SectorStyle] (default fill `#eee`).
  final Object background;

  /// A number or a percent string of `outerRadius - innerRadius`.
  final Object cornerRadius;
  final bool cornerIsExternal;
  final bool forceCornerRadius;

  /// `true`, a [LabelList], or a [LabelPainter] drawing each label.
  final Object label;
  final LegendType legendType;
  final Object? name;
  final bool hide;
  final String? tooltipType;
  final TooltipFormatter? formatter;
  final Color? fill;
  final double? fillOpacity;
  final Color? stroke;
  final double? strokeWidth;
  final double? strokeOpacity;

  /// The sector at the active tooltip index: `true`, a [SectorStyle] merged
  /// over it, or a [RadialBarShapePainter].
  final Object? activeShape;

  /// Draws every sector instead of the default Sector.
  final RadialBarShapePainter? shape;

  /// Sector events, fired for the sector under the pointer. Like DOM touch
  /// events, [onTouchMove] and [onTouchEnd] go to the sector the touch
  /// started on, even after the finger leaves it.
  final RadialBarEventHandler? onClick, onMouseEnter, onMouseLeave, onTouchStart, onTouchMove, onTouchEnd;
  final bool? isAnimationActive;
  final int animationBegin;
  final int animationDuration;
  final Object animationEasing;
  final VoidCallback? onAnimationStart;
  final VoidCallback? onAnimationEnd;
  final String? id;

  /// Recharts' z layer (`bar`, 300): higher layers paint on top.
  final int zIndex;

  /// [Cell]s (matched to entries by index) and [LabelList]s.
  final List<RechartsElement> children;

  List<Cell> get cells => children.whereType<Cell>().toList();
}

/// Props handed to a custom [RadialBar] sector painter.
class RadialBarShapeProps {
  const RadialBarShapeProps({required this.sector, required this.index, required this.isActive});
  final RadialBarSector sector;
  final int index;
  final bool isActive;
}

typedef RadialBarShapePainter = void Function(Canvas canvas, RadialBarShapeProps props);
