// Child components of polar charts, with the defaults of src/polar/Pie.tsx
// (`defaultPieProps`). Like the cartesian children they are configuration
// read by the chart. Dart typing follows components.dart: colors are [Color],
// `isAnimationActive: null` is `'auto'`, durations are milliseconds.

import 'package:flutter/widgets.dart';

import 'components.dart';
import 'engine/pie.dart' show PieSector;

/// Sector props merged over a sector (`activeShape` / `inactiveShape` given
/// as an object): paint props and geometry overrides.
class SectorStyle {
  const SectorStyle({
    this.fill,
    this.fillOpacity,
    this.stroke,
    this.strokeWidth,
    this.strokeOpacity,
    this.strokeDasharray,
    this.cx,
    this.cy,
    this.innerRadius,
    this.outerRadius,
    this.startAngle,
    this.endAngle,
    this.cornerRadius,
    this.forceCornerRadius,
    this.cornerIsExternal,
  });
  final Color? fill;
  final double? fillOpacity;
  final Color? stroke;
  final double? strokeWidth;
  final double? strokeOpacity;
  final List<double>? strokeDasharray;
  final double? cx, cy, innerRadius, outerRadius, startAngle, endAngle;

  /// A number or a percent string of `outerRadius - innerRadius`.
  final Object? cornerRadius;
  final bool? forceCornerRadius;
  final bool? cornerIsExternal;
}

/// Props handed to a custom sector painter (`PieSectorShapeProps`).
class PieSectorShapeProps {
  const PieSectorShapeProps({required this.sector, required this.index, required this.isActive});
  final PieSector sector;
  final int index;
  final bool isActive;
}

typedef PieShapePainter = void Function(Canvas canvas, PieSectorShapeProps props);

/// Props handed to [PieLabel.content] and [PieLabel.formatter] (`PieLabelRenderProps`).
class PieLabelProps {
  const PieLabelProps({
    required this.sector,
    required this.index,
    required this.x,
    required this.y,
    required this.textAnchor,
    required this.style,
  });
  final PieSector sector;
  final int index;

  /// The label point, `offsetRadius` outside the sector's middle angle.
  final double x, y;
  final TextAnchor textAnchor;

  /// Inherited text style filled with the sector's fill.
  final TextStyle style;
}

/// Props handed to a custom label line painter.
class PieLabelLineProps {
  const PieLabelLineProps({required this.sector, required this.index, required this.points, required this.stroke});
  final PieSector sector;
  final int index;

  /// From the sector's outer edge to the label point.
  final List<Offset> points;
  final Color? stroke;
}

typedef PieLabelLinePainter = void Function(Canvas canvas, PieLabelLineProps props);

/// The `label` object of a Pie without `position`: Recharts' own pie label,
/// placed outside the sector and joined to it by the label line.
class PieLabel {
  const PieLabel({this.offsetRadius = 20, this.fill, this.fontSize, this.formatter, this.content});

  /// Distance from the outer radius; 0 means the default 20, like Recharts.
  final double offsetRadius;
  final Color? fill;
  final double? fontSize;

  /// The label text (a function `label` returning text); null draws the value.
  final Object? Function(PieLabelProps props)? formatter;

  /// Draws the whole label instead of the default text.
  final void Function(Canvas canvas, PieLabelProps props)? content;
}

/// src/polar/Pie.tsx, defaults from `defaultPieProps`.
class Pie extends RechartsElement {
  const Pie({
    this.dataKey = 'value',
    this.nameKey = 'name',
    this.data,
    this.cx = '50%',
    this.cy = '50%',
    this.innerRadius = 0,
    this.outerRadius = '80%',
    this.startAngle = 0,
    this.endAngle = 360,
    this.paddingAngle = 0,
    this.minAngle = 0,
    this.cornerRadius,
    this.maxRadius,
    this.fill = const Color(0xFF808080),
    this.fillOpacity,
    this.stroke = const Color(0xFFFFFFFF),
    this.strokeWidth,
    this.strokeOpacity,
    this.name,
    this.hide = false,
    this.legendType = LegendType.rect,
    this.tooltipType,
    this.formatter,
    this.label = false,
    this.labelLine = true,
    this.activeShape,
    this.inactiveShape,
    this.shape,
    this.isAnimationActive,
    this.animationBegin = 400,
    this.animationDuration = 1500,
    this.animationEasing = 'ease',
    this.onAnimationStart,
    this.onAnimationEnd,
    this.rootTabIndex = 0,
    this.id,
    this.children = const [],
  });
  final Object dataKey;
  final Object nameKey;
  final List<Object?>? data;

  /// Numbers or percent strings of the plot area.
  final Object cx, cy;

  /// Numbers or percent strings of the max radius; [outerRadius] may also be
  /// `Object Function(Object? entry)` returning either.
  final Object innerRadius, outerRadius;
  final double startAngle, endAngle;
  final double paddingAngle;
  final double minAngle;

  /// A number or a percent string of `outerRadius - innerRadius`.
  final Object? cornerRadius;
  final double? maxRadius;
  final Color? fill;
  final double? fillOpacity;
  final Color? stroke;
  final double? strokeWidth;
  final double? strokeOpacity;
  final Object? name;
  final bool hide;
  final LegendType legendType;

  /// Recharts' `tooltipType="none"` is `tooltipType: 'none'` here.
  final String? tooltipType;
  final TooltipFormatter? formatter;

  /// `false`, `true`, a [PieLabel], or a [LabelList] (Recharts' label object
  /// with a `position`).
  final Object label;

  /// `true`/`false`, an [SvgStyle] merged over the line, or a [PieLabelLinePainter].
  final Object labelLine;

  /// The sector at the active tooltip index: `true`, a [SectorStyle] merged
  /// over it, or a [PieShapePainter].
  final Object? activeShape;

  /// The other sectors while one is active; same forms as [activeShape].
  final Object? inactiveShape;

  /// Draws every sector instead of the default Sector.
  final PieShapePainter? shape;

  /// `null` is Recharts' `'auto'`.
  final bool? isAnimationActive;
  final int animationBegin;
  final int animationDuration;
  final Object animationEasing;
  final VoidCallback? onAnimationStart;
  final VoidCallback? onAnimationEnd;

  /// Tab index of the sectors' group; a negative value keeps it out of the tab order.
  final int rootTabIndex;

  /// Stable identity (`id`); defaults to the Pie's position among the chart's Pies.
  final String? id;

  /// [Cell]s (matched to entries by index) and [LabelList]s.
  final List<RechartsElement> children;

  List<Cell> get cells => children.whereType<Cell>().toList();
}
