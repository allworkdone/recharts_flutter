// RadialBarChart: src/chart/RadialBarChart.tsx on the PolarChart base (polar_chart.dart).

import '../engine/polar_axis.dart' show PolarLayout;
import 'polar_chart.dart';

/// src/chart/RadialBarChart.tsx: a radial layout over a full circle, with the 'axis' or 'item' tooltip.
class RadialBarChart extends PolarChart {
  const RadialBarChart({
    super.key,
    super.width,
    super.height,
    super.data,
    super.margin,
    super.cx,
    super.cy,
    super.innerRadius,
    super.outerRadius,
    super.startAngle = 0,
    super.endAngle = 360,
    super.layout = PolarLayout.radial,
    super.stackOffset,
    super.reverseStackOrder,
    super.barCategoryGap,
    super.barGap,
    super.barSize,
    super.maxBarSize,
    super.syncId,
    super.accessibilityLayer,
    super.onClick,
    super.onMouseEnter,
    super.onMouseMove,
    super.onMouseLeave,
    super.children,
  });
  @override
  String get chartName => 'RadialBarChart';
  @override
  String get defaultTooltipEventType => 'axis';
  @override
  List<String> get allowedTooltipTypes => const ['axis', 'item'];
  @override
  bool get usesPolarScene => true;
}
