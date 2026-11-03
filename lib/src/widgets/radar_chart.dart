// RadarChart: src/chart/RadarChart.tsx on the PolarChart base (polar_chart.dart).

import '../engine/polar_axis.dart' show PolarLayout;
import 'polar_chart.dart';

/// src/chart/RadarChart.tsx: a centric layout from 90 to -270 degrees, with the 'axis' tooltip only.
class RadarChart extends PolarChart {
  const RadarChart({
    super.key,
    super.width,
    super.height,
    super.data,
    super.margin,
    super.cx,
    super.cy,
    super.innerRadius,
    super.outerRadius,
    super.startAngle = 90,
    super.endAngle = -270,
    super.layout = PolarLayout.centric,
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
  String get chartName => 'RadarChart';
  @override
  String get defaultTooltipEventType => 'axis';
  @override
  List<String> get allowedTooltipTypes => const ['axis'];
  @override
  bool get usesPolarScene => true;
}
