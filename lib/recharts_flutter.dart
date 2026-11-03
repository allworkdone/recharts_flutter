
import 'recharts_flutter_platform_interface.dart';

export 'src/components.dart';
export 'src/css_color.dart' show parseCssColor;
export 'src/core/curve.dart' show CurveType, ChartLayout;
export 'src/core/easing.dart' show EasingFunction, RechartsCurve, createEasingFunction, configBezier;
export 'src/core/nice_ticks.dart' show NiceTicksAlgorithm;
export 'src/core/scale.dart' show BandPosition;
export 'src/core/symbols.dart' show SymbolType;
export 'src/widgets/cartesian_chart.dart' show CategoricalChart, LineChart, BarChart, AreaChart, ComposedChart, FunnelChart;
export 'src/widgets/cartesian_chart.dart' show ScatterChart;
export 'src/widgets/responsive_container.dart' show ResponsiveContainer;
export 'src/widgets/tooltip.dart' show DefaultTooltipContent;
export 'src/polar_components.dart';
export 'src/engine/pie.dart' show PieSector;
export 'src/widgets/polar_chart.dart' show PolarChart, PieChart;
// ---- polar: exports ----
export 'src/engine/polar_axis.dart' show PolarLayout;
export 'src/polar_axes.dart';
export 'src/widgets/radar_chart.dart' show RadarChart;
export 'src/widgets/radial_bar_chart.dart' show RadialBarChart;
// ---- end polar ----
// ---- treemap: exports ----
export 'src/widgets/treemap_chart.dart';
// ---- end treemap ----
// ---- sankey: exports ----
export 'src/sankey.dart'
    show SankeyData, SankeyLinkDatum, SankeyNode, SankeyLink, SankeyNodeProps, SankeyLinkProps, SankeyElementType, SankeyVerticalAlign, SankeyAlign;
export 'src/widgets/sankey_chart.dart' show Sankey, SankeyNodePainter, SankeyLinkPainter, SankeyEventHandler;
// ---- end sankey ----
// ---- sunburst: exports ----
export 'src/widgets/sunburst_chart.dart' show SunburstChart, SunburstTextOptions, SunburstNodeHandler;
// ---- end sunburst ----

class RechartsFlutter {
  Future<String?> getPlatformVersion() {
    return RechartsFlutterPlatform.instance.getPlatformVersion();
  }
}
