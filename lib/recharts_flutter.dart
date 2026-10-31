
import 'recharts_flutter_platform_interface.dart';

export 'src/components.dart';
export 'src/core/curve.dart' show CurveType, ChartLayout;
export 'src/core/easing.dart' show EasingFunction, RechartsCurve, createEasingFunction, configBezier;
export 'src/core/nice_ticks.dart' show NiceTicksAlgorithm;
export 'src/core/scale.dart' show BandPosition;
export 'src/widgets/cartesian_chart.dart' show CategoricalChart, LineChart, BarChart, ComposedChart;
export 'src/widgets/responsive_container.dart' show ResponsiveContainer;
export 'src/widgets/tooltip.dart' show DefaultTooltipContent;

class RechartsFlutter {
  Future<String?> getPlatformVersion() {
    return RechartsFlutterPlatform.instance.getPlatformVersion();
  }
}
