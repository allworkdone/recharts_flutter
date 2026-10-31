
import 'recharts_flutter_platform_interface.dart';

export 'src/components.dart';
export 'src/core/curve.dart' show CurveType, ChartLayout;
export 'src/core/easing.dart' show EasingFunction, RechartsCurve, createEasingFunction, configBezier;
export 'src/core/nice_ticks.dart' show NiceTicksAlgorithm;
export 'src/core/scale.dart' show BandPosition;
export 'src/widgets/cartesian_chart.dart' show CategoricalChart, LineChart, BarChart, AreaChart, ComposedChart, FunnelChart;
export 'src/widgets/responsive_container.dart' show ResponsiveContainer;
export 'src/widgets/tooltip.dart' show DefaultTooltipContent;
export 'src/polar_components.dart';
export 'src/engine/pie.dart' show PieSector;
export 'src/widgets/polar_chart.dart' show PolarChart, PieChart;

class RechartsFlutter {
  Future<String?> getPlatformVersion() {
    return RechartsFlutterPlatform.instance.getPlatformVersion();
  }
}
