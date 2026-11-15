// Maps a parity fixture ({chart: {type, props, children}}) written with Recharts
// component and prop names onto the recharts_flutter API. SVG `<defs>` children
// only feed `url(#id)` fills: each `<linearGradient>` becomes a LinearGradient.

import 'package:flutter/widgets.dart';
import 'package:recharts_flutter/recharts_flutter.dart';

Widget renderFixture(Map<String, dynamic> fixture) {
  final chart = fixture['chart'] as Map<String, dynamic>;
  final width = (fixture['width'] as num).toDouble();
  final height = (fixture['height'] as num).toDouble();
  return buildChart(chart, width: width, height: height);
}

Widget buildChart(Map<String, dynamic> chart, {double? width, double? height}) {
  final type = chart['type'] as String;
  final p = _Props(chart['props'] as Map<String, dynamic>? ?? const {});
  final nodes = (chart['children'] as List? ?? const []).cast<Map<String, dynamic>>();
  _gradients.addAll(_linearGradients(nodes));
  final children = [for (final c in nodes) ?_child(c)];
  final raw = p.raw['data'];
  final data = (raw is Map ? const [] : (raw as List? ?? const [])).cast<Object?>();
  final layout = p.str('layout') == 'vertical' ? ChartLayout.vertical : ChartLayout.horizontal;
  final margin = p.margin('margin') ?? const Margin.all(5);
  final w = p.dbl('width') ?? width, h = p.dbl('height') ?? height;
  switch (type) {
    case 'LineChart':
      return LineChart(
          width: w, height: h, data: data, layout: layout, margin: margin, syncId: p.raw['syncId'], accessibilityLayer: p.raw['accessibilityLayer'] != false, children: children);
    case 'BarChart':
      return BarChart(
        width: w,
        height: h,
        data: data,
        layout: layout,
        margin: margin,
        barCategoryGap: p.raw['barCategoryGap'] ?? '10%',
        barGap: p.raw['barGap'] ?? 4,
        barSize: p.raw['barSize'],
        maxBarSize: p.dbl('maxBarSize'),
        stackOffset: _enum(StackOffset.values, p.str('stackOffset')) ?? StackOffset.none,
        reverseStackOrder: p.boolean('reverseStackOrder') ?? false,
        syncId: p.raw['syncId'], accessibilityLayer: p.raw['accessibilityLayer'] != false,
        children: children,
      );
    case 'FunnelChart':
      return FunnelChart(width: w, height: h, data: data, margin: margin, syncId: p.raw['syncId'], accessibilityLayer: p.raw['accessibilityLayer'] != false, children: children);
    case 'ComposedChart':
      return ComposedChart(
        width: w,
        height: h,
        data: data,
        layout: layout,
        margin: margin,
        barCategoryGap: p.raw['barCategoryGap'] ?? '10%',
        barGap: p.raw['barGap'] ?? 4,
        barSize: p.raw['barSize'],
        maxBarSize: p.dbl('maxBarSize'),
        stackOffset: _enum(StackOffset.values, p.str('stackOffset')) ?? StackOffset.none,
        reverseStackOrder: p.boolean('reverseStackOrder') ?? false,
        baseValue: p.raw['baseValue'],
        syncId: p.raw['syncId'], accessibilityLayer: p.raw['accessibilityLayer'] != false,
        children: children,
      );
    case 'AreaChart':
      return AreaChart(
        width: w,
        height: h,
        data: data,
        layout: layout,
        margin: margin,
        stackOffset: _enum(StackOffset.values, p.str('stackOffset')) ?? StackOffset.none,
        reverseStackOrder: p.boolean('reverseStackOrder') ?? false,
        baseValue: p.raw['baseValue'],
        syncId: p.raw['syncId'], accessibilityLayer: p.raw['accessibilityLayer'] != false,
        children: children,
      );
    case 'ScatterChart':
      return ScatterChart(
          width: w, height: h, data: data, layout: layout, margin: margin, syncId: p.raw['syncId'], accessibilityLayer: p.raw['accessibilityLayer'] != false, children: children);
    case 'ResponsiveContainer':
      final inner = (chart['children'] as List).cast<Map<String, dynamic>>().first;
      return ResponsiveContainer(
        width: p.raw['width'],
        height: p.raw['height'],
        aspect: p.dbl('aspect'),
        minWidth: p.dbl('minWidth') ?? 0,
        minHeight: p.dbl('minHeight'),
        maxHeight: p.dbl('maxHeight'),
        child: buildChart(inner),
      );
    case 'PieChart':
      return PieChart(
        width: w,
        height: h,
        data: data,
        margin: margin,
        syncId: p.raw['syncId'],
        accessibilityLayer: p.raw['accessibilityLayer'] != false,
        children: children,
      );
    // ---- polar: chart cases ----
    case 'RadarChart':
      return RadarChart(
        width: w,
        height: h,
        data: data,
        margin: margin,
        cx: p.raw['cx'] ?? '50%',
        cy: p.raw['cy'] ?? '50%',
        innerRadius: p.raw['innerRadius'] ?? 0,
        outerRadius: p.raw['outerRadius'] ?? '80%',
        startAngle: p.dbl('startAngle') ?? 90,
        endAngle: p.dbl('endAngle') ?? -270,
        syncId: p.raw['syncId'],
        accessibilityLayer: p.raw['accessibilityLayer'] != false,
        children: children,
      );
    case 'RadialBarChart':
      return RadialBarChart(
        width: w,
        height: h,
        data: data,
        margin: margin,
        cx: p.raw['cx'] ?? '50%',
        cy: p.raw['cy'] ?? '50%',
        innerRadius: p.raw['innerRadius'] ?? 0,
        outerRadius: p.raw['outerRadius'] ?? '80%',
        startAngle: p.dbl('startAngle') ?? 0,
        endAngle: p.dbl('endAngle') ?? 360,
        layout: p.str('layout') == 'centric' ? PolarLayout.centric : PolarLayout.radial,
        stackOffset: _enum(StackOffset.values, p.str('stackOffset')) ?? StackOffset.none,
        reverseStackOrder: p.boolean('reverseStackOrder') ?? false,
        barCategoryGap: p.raw['barCategoryGap'] ?? '10%',
        barGap: p.raw['barGap'] ?? 4,
        barSize: p.raw['barSize'],
        maxBarSize: p.dbl('maxBarSize'),
        syncId: p.raw['syncId'],
        accessibilityLayer: p.raw['accessibilityLayer'] != false,
        children: children,
      );
    // ---- end polar ----
    // ---- treemap: chart cases ----
    case 'Treemap':
      return _treemap(p, w, h, data, children);
    // ---- end treemap ----
    // ---- sankey: chart cases ----
    case 'Sankey':
      return Sankey(
        width: w,
        height: h,
        data: SankeyData.fromJson(p.raw['data'] as Map<String, dynamic>),
        nodePadding: p.dbl('nodePadding') ?? 10,
        nodeWidth: p.dbl('nodeWidth') ?? 10,
        linkCurvature: p.dbl('linkCurvature') ?? 0.5,
        iterations: p.dbl('iterations')?.toInt() ?? 32,
        node: _sankeyStyle(p.raw['node']),
        link: _sankeyStyle(p.raw['link']),
        margin: margin,
        sort: p.boolean('sort') ?? true,
        verticalAlign: p.str('verticalAlign') == 'top' ? SankeyVerticalAlign.top : SankeyVerticalAlign.justify,
        align: p.str('align') == 'left' ? SankeyAlign.left : SankeyAlign.justify,
        dataKey: p.raw['dataKey'] ?? 'value',
        nameKey: p.raw['nameKey'] ?? 'name',
        children: children,
      );
    // ---- end sankey ----
    // ---- sunburst: chart cases ----
    case 'SunburstChart':
      return SunburstChart(
        width: w,
        height: h,
        data: p.raw['data'] as Map<String, dynamic>,
        padding: p.dbl('padding') ?? 2,
        dataKey: p.str('dataKey') ?? 'value',
        nameKey: p.raw['nameKey'] ?? 'name',
        ringPadding: p.dbl('ringPadding') ?? 2,
        innerRadius: p.dbl('innerRadius') ?? 50,
        outerRadius: p.dbl('outerRadius'),
        cx: p.dbl('cx'),
        cy: p.dbl('cy'),
        startAngle: p.dbl('startAngle') ?? 0,
        endAngle: p.dbl('endAngle') ?? 360,
        fill: p.color('fill') ?? const Color(0xFF333333),
        stroke: p.color('stroke') ?? const Color(0xFFFFFFFF),
        textOptions: _sunburstText(p.raw['textOptions']),
        children: children,
      );
    // ---- end sunburst ----
  }
  throw ArgumentError('Unsupported chart type $type');
}

RechartsElement? _child(Map<String, dynamic> node) {
  final p = _Props(node['props'] as Map<String, dynamic>? ?? const {});
  switch (node['type']) {
    case 'XAxis':
      return XAxis(
        xAxisId: p.raw['xAxisId'] ?? 0,
        dataKey: p.raw['dataKey'],
        type: _axisType(p.str('type')) ?? AxisDomainType.category,
        domain: p.raw['domain'],
        allowDataOverflow: p.boolean('allowDataOverflow') ?? false,
        allowDecimals: p.boolean('allowDecimals') ?? true,
        allowDuplicatedCategory: p.boolean('allowDuplicatedCategory') ?? true,
        angle: p.dbl('angle') ?? 0,
        height: p.dbl('height') ?? 30,
        hide: p.boolean('hide') ?? false,
        interval: p.interval() ?? AxisInterval.preserveEnd,
        minTickGap: p.dbl('minTickGap') ?? 5,
        mirror: p.boolean('mirror') ?? false,
        orientation: _enum(AxisOrientation.values, p.str('orientation')) ?? AxisOrientation.bottom,
        padding: p.padding() ?? const AxisPadding(left: 0, right: 0),
        reversed: p.boolean('reversed') ?? false,
        scale: p.str('scale') ?? 'auto',
        tick: p.tick(),
        tickCount: p.dbl('tickCount')?.toInt() ?? 5,
        ticks: (p.raw['ticks'] as List?)?.cast<Object>(),
        unit: p.raw['unit']?.toString(),
        name: p.str('name'),
        axisLine: p.svgOrBool('axisLine') ?? true,
        tickLine: p.svgOrBool('tickLine') ?? true,
        tickSize: p.dbl('tickSize') ?? 6,
        tickMargin: p.dbl('tickMargin') ?? 2,
        stroke: p.color('stroke') ?? const Color(0xFF666666),
        textAnchor: _enum(TextAnchor.values, p.str('textAnchor')),
        fontSize: p.dbl('fontSize'),
        label: _label(p.raw['label']),
      );
    case 'YAxis':
      return YAxis(
        yAxisId: p.raw['yAxisId'] ?? 0,
        dataKey: p.raw['dataKey'],
        type: _axisType(p.str('type')) ?? AxisDomainType.number,
        domain: p.raw['domain'],
        allowDataOverflow: p.boolean('allowDataOverflow') ?? false,
        allowDecimals: p.boolean('allowDecimals') ?? true,
        allowDuplicatedCategory: p.boolean('allowDuplicatedCategory') ?? true,
        angle: p.dbl('angle') ?? 0,
        width: p.raw['width'] == 'auto' ? 'auto' : p.dbl('width') ?? 60,
        hide: p.boolean('hide') ?? false,
        interval: p.interval() ?? AxisInterval.preserveEnd,
        minTickGap: p.dbl('minTickGap') ?? 5,
        mirror: p.boolean('mirror') ?? false,
        orientation: _enum(AxisOrientation.values, p.str('orientation')) ?? AxisOrientation.left,
        padding: p.padding() ?? const AxisPadding(top: 0, bottom: 0),
        reversed: p.boolean('reversed') ?? false,
        scale: p.str('scale') ?? 'auto',
        tick: p.tick(),
        tickCount: p.dbl('tickCount')?.toInt() ?? 5,
        ticks: (p.raw['ticks'] as List?)?.cast<Object>(),
        unit: p.raw['unit']?.toString(),
        name: p.str('name'),
        axisLine: p.svgOrBool('axisLine') ?? true,
        tickLine: p.svgOrBool('tickLine') ?? true,
        tickSize: p.dbl('tickSize') ?? 6,
        tickMargin: p.dbl('tickMargin') ?? 2,
        stroke: p.color('stroke') ?? const Color(0xFF666666),
        textAnchor: _enum(TextAnchor.values, p.str('textAnchor')),
        fontSize: p.dbl('fontSize'),
        label: _label(p.raw['label']),
      );
    case 'CartesianGrid':
      return CartesianGrid(
        horizontal: p.svgOrBool('horizontal') ?? true,
        vertical: p.svgOrBool('vertical') ?? true,
        fill: p.color('fill'),
        fillOpacity: p.dbl('fillOpacity'),
        horizontalFill: [for (final c in (p.raw['horizontalFill'] as List? ?? const [])) ?parseCssColor(c as String)],
        verticalFill: [for (final c in (p.raw['verticalFill'] as List? ?? const [])) ?parseCssColor(c as String)],
        stroke: p.color('stroke') ?? const Color(0xFFCCCCCC),
        strokeWidth: p.dbl('strokeWidth') ?? 1,
        strokeDasharray: p.dash('strokeDasharray'),
        syncWithTicks: p.boolean('syncWithTicks') ?? false,
      );
    case 'Tooltip':
      return Tooltip(
        active: p.boolean('active'),
        cursor: p.svgOrBool('cursor') ?? true,
        defaultIndex: p.raw['defaultIndex'],
        offset: p.dbl('offset') ?? 10,
        separator: p.str('separator') ?? ' : ',
        isAnimationActive: p.boolean('isAnimationActive'),
        animationDuration: p.dbl('animationDuration')?.toInt() ?? 400,
        trigger: p.str('trigger') == 'click' ? TooltipTrigger.click : TooltipTrigger.hover,
        shared: p.boolean('shared'),
        allowEscapeViewBox: (
          x: (p.raw['allowEscapeViewBox'] as Map?)?['x'] == true,
          y: (p.raw['allowEscapeViewBox'] as Map?)?['y'] == true,
        ),
        reverseDirection: (
          x: (p.raw['reverseDirection'] as Map?)?['x'] == true,
          y: (p.raw['reverseDirection'] as Map?)?['y'] == true,
        ),
        position: switch (p.raw['position']) {
          final Map m => (x: (m['x'] as num?)?.toDouble(), y: (m['y'] as num?)?.toDouble()),
          _ => null,
        },
      );
    case 'Legend':
      return Legend(
        align: _enum(HorizontalAlign.values, p.str('align')) ?? HorizontalAlign.center,
        verticalAlign: _enum(VerticalAlign.values, p.str('verticalAlign')) ?? VerticalAlign.bottom,
        layout: switch (p.str('layout')) {
          'vertical' => ChartLayout.vertical,
          'horizontal' => ChartLayout.horizontal,
          _ => null,
        },
        iconSize: p.dbl('iconSize') ?? 14,
        iconType: _enum(LegendType.values, p.str('iconType')),
      );
    case 'Line':
      return Line(
        dataKey: p.raw['dataKey'] as Object,
        xAxisId: p.raw['xAxisId'] ?? 0,
        yAxisId: p.raw['yAxisId'] ?? 0,
        type: _enum(CurveType.values, p.str('type')) ?? CurveType.linear,
        stroke: p.color('stroke') ?? const Color(0xFF3182BD),
        strokeWidth: p.dbl('strokeWidth') ?? 1,
        strokeDasharray: p.dash('strokeDasharray'),
        fill: p.color('fill') ?? const Color(0xFFFFFFFF),
        dot: p.svgOrBool('dot') ?? true,
        activeDot: p.svgOrBool('activeDot') ?? true,
        connectNulls: p.boolean('connectNulls') ?? false,
        hide: p.boolean('hide') ?? false,
        legendType: _enum(LegendType.values, p.str('legendType')) ?? LegendType.line,
        name: p.raw['name'],
        unit: p.raw['unit']?.toString(),
        isAnimationActive: p.boolean('isAnimationActive'),
        animationBegin: p.dbl('animationBegin')?.toInt() ?? 0,
        animationDuration: p.dbl('animationDuration')?.toInt() ?? 1500,
        animationEasing: p.str('animationEasing') ?? 'ease',
        label: _labelList(p.raw['label']) ?? false,
        children: [for (final c in (node['children'] as List? ?? const []).cast<Map<String, dynamic>>()) ?_child(c)],
      );
    case 'Area':
      return Area(
        dataKey: p.raw['dataKey'] as Object,
        xAxisId: p.raw['xAxisId'] ?? 0,
        yAxisId: p.raw['yAxisId'] ?? 0,
        type: _enum(CurveType.values, p.str('type')) ?? CurveType.linear,
        stroke: p.raw.containsKey('stroke') ? p.color('stroke') : const Color(0xFF3182BD),
        strokeWidth: p.dbl('strokeWidth') ?? 1,
        strokeDasharray: p.dash('strokeDasharray'),
        fill: p.raw.containsKey('fill') ? p.paint('fill') : const Color(0xFF3182BD),
        fillOpacity: p.dbl('fillOpacity') ?? 0.6,
        dot: p.svgOrBool('dot') ?? false,
        activeDot: p.svgOrBool('activeDot') ?? true,
        connectNulls: p.boolean('connectNulls') ?? false,
        stackId: p.raw['stackId'],
        baseValue: p.raw['baseValue'],
        hide: p.boolean('hide') ?? false,
        legendType: _enum(LegendType.values, p.str('legendType')) ?? LegendType.line,
        name: p.raw['name'],
        unit: p.raw['unit']?.toString(),
        isAnimationActive: p.boolean('isAnimationActive'),
        animationBegin: p.dbl('animationBegin')?.toInt() ?? 0,
        animationDuration: p.dbl('animationDuration')?.toInt() ?? 1500,
        animationEasing: p.str('animationEasing') ?? 'ease',
        label: _labelList(p.raw['label']) ?? false,
        children: [for (final c in (node['children'] as List? ?? const []).cast<Map<String, dynamic>>()) ?_child(c)],
      );
    case 'Bar':
      return Bar(
        dataKey: p.raw['dataKey'] as Object,
        xAxisId: p.raw['xAxisId'] ?? 0,
        yAxisId: p.raw['yAxisId'] ?? 0,
        stackId: p.raw['stackId'],
        barSize: p.raw['barSize'],
        maxBarSize: p.dbl('maxBarSize'),
        minPointSize: p.dbl('minPointSize') ?? 0,
        fill: p.paint('fill'),
        stroke: p.color('stroke'),
        strokeWidth: p.dbl('strokeWidth'),
        radius: p.raw['radius'] ?? 0,
        background: p.svgOrBool('background') ?? false,
        activeBar: p.svgOrBool('activeBar') ?? false,
        hide: p.boolean('hide') ?? false,
        legendType: _enum(LegendType.values, p.str('legendType')) ?? LegendType.rect,
        name: p.raw['name'],
        unit: p.raw['unit']?.toString(),
        isAnimationActive: p.boolean('isAnimationActive'),
        animationBegin: p.dbl('animationBegin')?.toInt() ?? 0,
        animationDuration: p.dbl('animationDuration')?.toInt() ?? 400,
        animationEasing: p.str('animationEasing') ?? 'ease',
        label: _labelList(p.raw['label']) ?? false,
        children: [
          for (final c in (node['children'] as List? ?? const []).cast<Map<String, dynamic>>())
            if (c['type'] == 'Cell') _cell(_Props(c['props'] as Map<String, dynamic>? ?? const {})) else ?_child(c),
        ],
      );
    case 'Funnel':
      return Funnel(
        dataKey: p.raw['dataKey'] as Object,
        data: (p.raw['data'] as List?)?.cast<Object?>(),
        nameKey: p.raw['nameKey'] ?? 'name',
        name: p.raw['name'],
        hide: p.boolean('hide') ?? false,
        fill: p.color('fill') ?? const Color(0xFF808080),
        fillOpacity: p.dbl('fillOpacity'),
        stroke: p.raw.containsKey('stroke') ? p.color('stroke') : const Color(0xFFFFFFFF),
        strokeWidth: p.dbl('strokeWidth'),
        width: p.raw['width'],
        reversed: p.boolean('reversed') ?? false,
        lastShapeType: _enum(LastShapeType.values, p.str('lastShapeType')) ?? LastShapeType.triangle,
        activeShape: p.svgOrBool('activeShape'),
        tooltipType: p.str('tooltipType'),
        isAnimationActive: p.boolean('isAnimationActive'),
        animationBegin: p.dbl('animationBegin')?.toInt() ?? 400,
        animationDuration: p.dbl('animationDuration')?.toInt() ?? 1500,
        animationEasing: p.str('animationEasing') ?? 'ease',
        label: _labelList(p.raw['label']) ?? false,
        children: [
          for (final c in (node['children'] as List? ?? const []).cast<Map<String, dynamic>>())
            if (c['type'] == 'Cell') _cell(_Props(c['props'] as Map<String, dynamic>? ?? const {})) else ?_child(c),
        ],
      );
    case 'LabelList':
      return _labelList(p.raw);
    case 'Scatter':
      return Scatter(
        dataKey: p.raw['dataKey'],
        xAxisId: p.raw['xAxisId'] ?? 0,
        yAxisId: p.raw['yAxisId'] ?? 0,
        zAxisId: p.raw['zAxisId'] ?? 0,
        data: (p.raw['data'] as List?)?.cast<Object?>(),
        shape: _enum(SymbolType.values, p.str('shape')) ?? SymbolType.circle,
        activeShape: _enum(SymbolType.values, p.str('activeShape')) ?? p.svgOrBool('activeShape'),
        fill: p.color('fill'),
        fillOpacity: p.dbl('fillOpacity'),
        stroke: p.color('stroke'),
        strokeWidth: p.dbl('strokeWidth'),
        line: p.svgOrBool('line') ?? false,
        lineType: _enum(ScatterLineType.values, p.str('lineType')) ?? ScatterLineType.joint,
        lineJointType: _enum(CurveType.values, p.str('lineJointType')) ?? CurveType.linear,
        hide: p.boolean('hide') ?? false,
        legendType: _enum(LegendType.values, p.str('legendType')) ?? LegendType.circle,
        name: p.raw['name'],
        isAnimationActive: p.boolean('isAnimationActive'),
        animationBegin: p.dbl('animationBegin')?.toInt() ?? 0,
        animationDuration: p.dbl('animationDuration')?.toInt() ?? 400,
        animationEasing: p.str('animationEasing') ?? 'linear',
        label: _labelList(p.raw['label']) ?? false,
        children: [
          for (final c in (node['children'] as List? ?? const []).cast<Map<String, dynamic>>())
            if (c['type'] == 'Cell') _cell(_Props(c['props'] as Map<String, dynamic>? ?? const {})) else ?_child(c),
        ],
      );
    case 'ZAxis':
      return ZAxis(
        zAxisId: p.raw['zAxisId'] ?? 0,
        dataKey: p.raw['dataKey'],
        type: _axisType(p.str('type')) ?? AxisDomainType.number,
        domain: p.raw['domain'],
        range: [for (final v in (p.raw['range'] as List? ?? const [64, 64])) (v as num).toDouble()],
        scale: p.str('scale') ?? 'auto',
        name: p.str('name'),
        unit: p.raw['unit']?.toString(),
      );
    case 'ErrorBar':
      return ErrorBar(
        dataKey: p.raw['dataKey'] as Object,
        width: p.dbl('width') ?? 5,
        direction: _enum(ErrorBarDirection.values, p.str('direction')),
        stroke: p.raw.containsKey('stroke') ? p.color('stroke') : const Color(0xFF000000),
        strokeWidth: p.dbl('strokeWidth') ?? 1.5,
        isAnimationActive: p.boolean('isAnimationActive') ?? true,
        animationBegin: p.dbl('animationBegin')?.toInt() ?? 0,
        animationDuration: p.dbl('animationDuration')?.toInt() ?? 400,
        animationEasing: p.str('animationEasing') ?? 'ease-in-out',
      );
    case 'Brush':
      final panorama = (node['children'] as List? ?? const []).cast<Map<String, dynamic>>().firstOrNull;
      return Brush(
        dataKey: p.raw['dataKey'],
        x: p.dbl('x'),
        y: p.dbl('y'),
        dy: p.dbl('dy'),
        width: p.dbl('width'),
        height: p.dbl('height') ?? 40,
        travellerWidth: p.dbl('travellerWidth') ?? 5,
        gap: p.dbl('gap')?.toInt() ?? 1,
        fill: p.raw.containsKey('fill') ? p.color('fill') : const Color(0xFFFFFFFF),
        stroke: p.raw.containsKey('stroke') ? p.color('stroke') : const Color(0xFF666666),
        padding: p.margin('padding') ?? const Margin.all(1),
        startIndex: p.dbl('startIndex')?.toInt(),
        endIndex: p.dbl('endIndex')?.toInt(),
        leaveTimeOut: p.dbl('leaveTimeOut')?.toInt() ?? 1000,
        alwaysShowText: p.boolean('alwaysShowText') ?? false,
        ariaLabel: p.str('ariaLabel'),
        child: panorama == null ? null : buildChart(panorama) as CategoricalChart,
      );
    case 'ReferenceLine':
      return ReferenceLine(
        x: p.raw['x'],
        y: p.raw['y'],
        xAxisId: p.raw['xAxisId'] ?? 0,
        yAxisId: p.raw['yAxisId'] ?? 0,
        stroke: p.color('stroke') ?? const Color(0xFFCCCCCC),
        strokeWidth: p.dbl('strokeWidth') ?? 1,
        strokeDasharray: p.dash('strokeDasharray'),
        label: _label(p.raw['label']),
        ifOverflow: _enum(IfOverflow.values, p.str('ifOverflow')) ?? IfOverflow.discard,
      );
    case 'ReferenceArea':
      return ReferenceArea(
        x1: p.raw['x1'],
        x2: p.raw['x2'],
        y1: p.raw['y1'],
        y2: p.raw['y2'],
        xAxisId: p.raw['xAxisId'] ?? 0,
        yAxisId: p.raw['yAxisId'] ?? 0,
        fill: p.color('fill') ?? const Color(0xFFCCCCCC),
        fillOpacity: p.dbl('fillOpacity') ?? 0.5,
        stroke: p.color('stroke'),
        strokeOpacity: p.dbl('strokeOpacity') ?? 1,
        strokeWidth: p.dbl('strokeWidth') ?? 1,
        radius: p.raw['radius'] is num ? (p.raw['radius'] as num).toDouble() : 0,
        label: _label(p.raw['label']),
        ifOverflow: _enum(IfOverflow.values, p.str('ifOverflow')) ?? IfOverflow.discard,
      );
    case 'ReferenceDot':
      return ReferenceDot(
        x: p.raw['x'],
        y: p.raw['y'],
        r: p.dbl('r') ?? 10,
        xAxisId: p.raw['xAxisId'] ?? 0,
        yAxisId: p.raw['yAxisId'] ?? 0,
        fill: p.color('fill') ?? const Color(0xFFFFFFFF),
        fillOpacity: p.dbl('fillOpacity') ?? 1,
        stroke: p.color('stroke') ?? const Color(0xFFCCCCCC),
        strokeWidth: p.dbl('strokeWidth') ?? 1,
        label: _label(p.raw['label']),
        ifOverflow: _enum(IfOverflow.values, p.str('ifOverflow')) ?? IfOverflow.discard,
      );
    case 'Pie':
      return Pie(
        dataKey: p.raw['dataKey'] ?? 'value',
        nameKey: p.raw['nameKey'] ?? 'name',
        data: (p.raw['data'] as List?)?.cast<Object?>(),
        cx: p.raw['cx'] ?? '50%',
        cy: p.raw['cy'] ?? '50%',
        innerRadius: p.raw['innerRadius'] ?? 0,
        outerRadius: p.raw['outerRadius'] ?? '80%',
        startAngle: p.dbl('startAngle') ?? 0,
        endAngle: p.dbl('endAngle') ?? 360,
        paddingAngle: p.dbl('paddingAngle') ?? 0,
        minAngle: p.dbl('minAngle') ?? 0,
        cornerRadius: p.raw['cornerRadius'],
        fill: p.raw.containsKey('fill') ? p.color('fill') : const Color(0xFF808080),
        stroke: p.raw.containsKey('stroke') ? p.color('stroke') : const Color(0xFFFFFFFF),
        strokeWidth: p.dbl('strokeWidth'),
        name: p.raw['name'],
        hide: p.boolean('hide') ?? false,
        legendType: _enum(LegendType.values, p.str('legendType')) ?? LegendType.rect,
        label: _pieLabel(p.raw['label']),
        labelLine: p.svgOrBool('labelLine') ?? true,
        activeShape: _sectorStyle(p.raw['activeShape']),
        inactiveShape: _sectorStyle(p.raw['inactiveShape']),
        zIndex: p.integer('zIndex') ?? 100,
        isAnimationActive: p.boolean('isAnimationActive'),
        animationBegin: p.dbl('animationBegin')?.toInt() ?? 400,
        animationDuration: p.dbl('animationDuration')?.toInt() ?? 1500,
        animationEasing: p.str('animationEasing') ?? 'ease',
        children: [
          for (final c in (node['children'] as List? ?? const []).cast<Map<String, dynamic>>())
            if (c['type'] == 'Cell') _cell(_Props(c['props'] as Map<String, dynamic>? ?? const {})) else ?_child(c),
        ],
      );
    // ---- polar: child element cases ----
    case 'PolarGrid':
      return PolarGrid(
        polarAngles: (p.raw['polarAngles'] as List?)?.map((e) => (e as num).toDouble()).toList(),
        polarRadius: (p.raw['polarRadius'] as List?)?.cast<Object>(),
        gridType: p.str('gridType') == 'circle' ? PolarGridType.circle : PolarGridType.polygon,
        radialLines: p.boolean('radialLines') ?? true,
        angleAxisId: p.raw['angleAxisId'] ?? 0,
        radiusAxisId: p.raw['radiusAxisId'] ?? 0,
        stroke: p.raw.containsKey('stroke') ? p.color('stroke') : const Color(0xFFCCCCCC),
        strokeWidth: p.dbl('strokeWidth') ?? 1,
        strokeDasharray: p.dash('strokeDasharray'),
        fill: p.color('fill'),
        fillOpacity: p.dbl('fillOpacity'),
        zIndex: p.integer('zIndex') ?? -100,
      );
    case 'PolarAngleAxis':
      return PolarAngleAxis(
        angleAxisId: p.raw['angleAxisId'] ?? 0,
        dataKey: p.raw['dataKey'],
        type: _axisType(p.str('type')) ?? AxisDomainType.auto,
        domain: p.raw['domain'],
        scale: p.str('scale') ?? 'auto',
        ticks: (p.raw['ticks'] as List?)?.cast<Object>(),
        tick: p.tick(),
        tickLine: p.svgOrBool('tickLine') ?? true,
        tickSize: p.dbl('tickSize') ?? 8,
        tickCount: p.dbl('tickCount')?.toInt(),
        axisLine: p.svgOrBool('axisLine') ?? true,
        axisLineType: p.str('axisLineType') == 'circle' ? PolarAxisLineType.circle : PolarAxisLineType.polygon,
        orientation: p.str('orientation') == 'inner' ? PolarAngleOrientation.inner : PolarAngleOrientation.outer,
        reversed: p.boolean('reversed') ?? false,
        allowDecimals: p.boolean('allowDecimals') ?? false,
        stroke: p.color('stroke'),
        strokeWidth: p.dbl('strokeWidth'),
        fontSize: p.dbl('fontSize'),
        zIndex: p.integer('zIndex') ?? 500,
      );
    case 'PolarRadiusAxis':
      return PolarRadiusAxis(
        radiusAxisId: p.raw['radiusAxisId'] ?? 0,
        dataKey: p.raw['dataKey'],
        type: _axisType(p.str('type')) ?? AxisDomainType.auto,
        domain: p.raw['domain'],
        scale: p.str('scale') ?? 'auto',
        angle: p.dbl('angle') ?? 0,
        orientation: _enum(PolarRadiusOrientation.values, p.str('orientation')) ?? PolarRadiusOrientation.right,
        ticks: (p.raw['ticks'] as List?)?.cast<Object>(),
        tick: p.tick(),
        tickCount: p.dbl('tickCount')?.toInt() ?? 5,
        axisLine: p.svgOrBool('axisLine') ?? true,
        reversed: p.boolean('reversed') ?? false,
        allowDecimals: p.boolean('allowDecimals') ?? false,
        allowDataOverflow: p.boolean('allowDataOverflow') ?? false,
        label: _label(p.raw['label']),
        stroke: p.raw.containsKey('stroke') ? p.color('stroke') : const Color(0xFFCCCCCC),
        fontSize: p.dbl('fontSize'),
        zIndex: p.integer('zIndex') ?? 500,
      );
    case 'Radar':
      return Radar(
        dataKey: p.raw['dataKey'] as Object,
        angleAxisId: p.raw['angleAxisId'] ?? 0,
        radiusAxisId: p.raw['radiusAxisId'] ?? 0,
        name: p.raw['name'],
        hide: p.boolean('hide') ?? false,
        legendType: _enum(LegendType.values, p.str('legendType')) ?? LegendType.rect,
        dot: p.svgOrBool('dot') ?? false,
        activeDot: p.svgOrBool('activeDot') ?? true,
        label: _labelList(p.raw['label']) ?? false,
        connectNulls: p.boolean('connectNulls') ?? false,
        fill: _polarFill(p),
        fillOpacity: p.dbl('fillOpacity'),
        stroke: p.color('stroke'),
        strokeWidth: p.dbl('strokeWidth'),
        strokeDasharray: p.dash('strokeDasharray'),
        zIndex: p.integer('zIndex') ?? 100,
        isAnimationActive: p.boolean('isAnimationActive'),
        animationBegin: p.dbl('animationBegin')?.toInt() ?? 0,
        animationDuration: p.dbl('animationDuration')?.toInt() ?? 1500,
        animationEasing: p.str('animationEasing') ?? 'ease',
        children: [
          for (final c in (node['children'] as List? ?? const []).cast<Map<String, dynamic>>()) ?_child(c),
        ],
      );
    case 'RadialBar':
      return RadialBar(
        dataKey: p.raw['dataKey'] as Object,
        angleAxisId: p.raw['angleAxisId'] ?? 0,
        radiusAxisId: p.raw['radiusAxisId'] ?? 0,
        stackId: p.raw['stackId'],
        barSize: p.dbl('barSize'),
        maxBarSize: p.dbl('maxBarSize'),
        minAngle: p.dbl('minAngle') ?? 0,
        minPointSize: p.dbl('minPointSize') ?? 0,
        background: _sectorStyle(p.raw['background']) ?? false,
        cornerRadius: p.raw['cornerRadius'] ?? 0,
        cornerIsExternal: p.boolean('cornerIsExternal') ?? false,
        forceCornerRadius: p.boolean('forceCornerRadius') ?? false,
        label: _labelList(p.raw['label']) ?? false,
        legendType: _enum(LegendType.values, p.str('legendType')) ?? LegendType.rect,
        name: p.raw['name'],
        hide: p.boolean('hide') ?? false,
        fill: _polarFill(p),
        fillOpacity: p.dbl('fillOpacity'),
        stroke: p.color('stroke'),
        strokeWidth: p.dbl('strokeWidth'),
        activeShape: _sectorStyle(p.raw['activeShape']),
        zIndex: p.integer('zIndex') ?? 300,
        isAnimationActive: p.boolean('isAnimationActive'),
        animationBegin: p.dbl('animationBegin')?.toInt() ?? 0,
        animationDuration: p.dbl('animationDuration')?.toInt() ?? 1500,
        animationEasing: p.str('animationEasing') ?? 'ease',
        children: [
          for (final c in (node['children'] as List? ?? const []).cast<Map<String, dynamic>>())
            if (c['type'] == 'Cell') _cell(_Props(c['props'] as Map<String, dynamic>? ?? const {})) else ?_child(c),
        ],
      );
    // ---- end polar ----
    // ---- treemap: child element cases ----
    // ---- end treemap ----
    // ---- sankey: child element cases ----
    // ---- end sankey ----
    // ---- sunburst: child element cases ----
    // ---- end sunburst ----
  }
  return null;
}

/// Pie `label`: true, LabelList props (with `position`) or Pie label props.
Object _pieLabel(Object? v) {
  if (v == true) return true;
  if (v is! Map) return false;
  if (v.containsKey('position')) return _labelList(v)!;
  final p = _Props(v.cast<String, dynamic>());
  return PieLabel(offsetRadius: p.dbl('offsetRadius') ?? 20, fill: p.color('fill'), fontSize: p.dbl('fontSize'));
}

/// `activeShape` / `inactiveShape` given as props: true or Sector props.
Object? _sectorStyle(Object? v) {
  if (v is bool) return v;
  if (v is! Map) return null;
  final p = _Props(v.cast<String, dynamic>());
  return SectorStyle(
    fill: p.color('fill'),
    fillOpacity: p.dbl('fillOpacity'),
    stroke: p.color('stroke'),
    strokeWidth: p.dbl('strokeWidth'),
    strokeOpacity: p.dbl('strokeOpacity'),
    strokeDasharray: p.dash('strokeDasharray'),
    cx: p.dbl('cx'),
    cy: p.dbl('cy'),
    innerRadius: p.dbl('innerRadius'),
    outerRadius: p.dbl('outerRadius'),
    startAngle: p.dbl('startAngle'),
    endAngle: p.dbl('endAngle'),
    cornerRadius: p.raw['cornerRadius'],
    zIndex: p.integer('zIndex'),
  );
}

/// `label` of an axis or ReferenceLine: string, number or Label props.
Object? _label(Object? v) {
  if (v is String || v is num) return v;
  if (v is! Map) return null;
  final p = _Props(v.cast<String, dynamic>());
  return Label(
    value: p.raw['value'],
    position: _enum(LabelPosition.values, p.str('position')) ?? LabelPosition.middle,
    offset: p.dbl('offset') ?? 5,
    angle: p.dbl('angle') ?? 0,
    fill: p.color('fill'),
    fontSize: p.dbl('fontSize'),
    textAnchor: _enum(TextAnchor.values, p.str('textAnchor')),
    width: p.dbl('width'),
    textBreakAll: p.boolean('textBreakAll') ?? false,
  );
}

/// `label` of a Line/Bar (true or LabelList props), or LabelList props.
LabelList? _labelList(Object? v) {
  if (v == true) return const LabelList();
  if (v is! Map) return null;
  final p = _Props(v.cast<String, dynamic>());
  return LabelList(
    dataKey: p.raw['dataKey'],
    position: _enum(LabelPosition.values, p.str('position')) ?? LabelPosition.middle,
    offset: p.dbl('offset') ?? 5,
    angle: p.dbl('angle') ?? 0,
    fill: p.color('fill'),
    fontSize: p.dbl('fontSize'),
    textBreakAll: p.boolean('textBreakAll') ?? false,
  );
}

/// Raw CSS strings go to the library; `url(#id)` paints are not colors and stay unset.
Object? _cssPaint(_Props p, String k) => p.raw[k] is String && (p.raw[k] as String).startsWith('url(') ? null : p.raw[k];

Cell _cell(_Props p) => Cell.css(
    fill: _cssPaint(p, 'fill'), fillOpacity: p.dbl('fillOpacity'), stroke: _cssPaint(p, 'stroke'), strokeWidth: p.dbl('strokeWidth'));

/// `<linearGradient>`s by id, from every chart rendered so far (SVG ids are document-wide).
final _gradients = <String, LinearGradient>{};

/// The `<linearGradient>` elements under `<defs>`: x1/y1/x2/y2 are fractions of
/// the bounding box (objectBoundingBox, default 0 0 1 0), stops have offset,
/// stopColor and stopOpacity.
Map<String, LinearGradient> _linearGradients(List<Map<String, dynamic>> nodes) {
  final out = <String, LinearGradient>{};
  for (final defs in nodes.where((n) => n['type'] == 'defs')) {
    for (final g in (defs['children'] as List? ?? const []).cast<Map<String, dynamic>>()) {
      if (g['type'] != 'linearGradient') continue;
      final p = (g['props'] as Map? ?? const {}).cast<String, dynamic>();
      double frac(String k, double d) {
        final v = p[k];
        if (v is num) return v.toDouble();
        if (v is String) return v.endsWith('%') ? double.parse(v.substring(0, v.length - 1)) / 100 : double.parse(v);
        return d;
      }

      Alignment at(double x, double y) => Alignment(x * 2 - 1, y * 2 - 1);
      final stops = (g['children'] as List? ?? const []).cast<Map<String, dynamic>>().where((s) => s['type'] == 'stop');
      final colors = <Color>[], offsets = <double>[];
      for (final s in stops) {
        final sp = _Props((s['props'] as Map? ?? const {}).cast<String, dynamic>());
        final c = sp.color('stopColor') ?? const Color(0xFF000000);
        final o = sp.raw['offset'];
        colors.add(c.withValues(alpha: c.a * (sp.dbl('stopOpacity') ?? 1)));
        offsets.add(o is String && o.endsWith('%') ? double.parse(o.substring(0, o.length - 1)) / 100 : (o as num?)?.toDouble() ?? 0);
      }
      out[p['id'] as String] = LinearGradient(
        begin: at(frac('x1', 0), frac('y1', 0)),
        end: at(frac('x2', 1), frac('y2', 0)),
        colors: colors,
        stops: offsets,
      );
    }
  }
  return out;
}

T? _enum<T extends Enum>(List<T> values, String? name) => values.where((v) => v.name == name).firstOrNull;

AxisDomainType? _axisType(String? s) => _enum(AxisDomainType.values, s);

class _Props {
  _Props(this.raw);
  final Map<String, dynamic> raw;

  String? str(String k) => raw[k] is String ? raw[k] as String : null;
  double? dbl(String k) => raw[k] is num ? (raw[k] as num).toDouble() : null;
  int? integer(String k) => raw[k] is num ? (raw[k] as num).toInt() : null;
  bool? boolean(String k) => raw[k] is bool ? raw[k] as bool : null;
  Color? color(String k) => raw[k] is String ? parseCssColor(raw[k] as String) : null;

  /// A color, or `url(#id)` of a `<linearGradient>`.
  Object? paint(String k) {
    final m = raw[k] is String ? RegExp(r'^url\(#(.+)\)$').firstMatch(raw[k] as String) : null;
    return m != null ? _gradients[m[1]] : color(k);
  }

  List<double>? dash(String k) {
    final v = raw[k];
    if (v is num) return [v.toDouble()];
    if (v is String) return [for (final s in v.split(RegExp(r'[,\s]+'))) ?double.tryParse(s)];
    if (v is List) return [for (final s in v) (s as num).toDouble()];
    return null;
  }

  Margin? margin(String k) {
    final m = raw[k];
    if (m is! Map) return null;
    double side(String s) => (m[s] as num?)?.toDouble() ?? 0;
    return Margin(top: side('top'), right: side('right'), bottom: side('bottom'), left: side('left'));
  }

  AxisInterval? interval() {
    final v = raw['interval'];
    if (v is num) return AxisInterval.number(v.toInt());
    return switch (v) {
      'preserveStart' => AxisInterval.preserveStart,
      'preserveEnd' => AxisInterval.preserveEnd,
      'preserveStartEnd' => AxisInterval.preserveStartEnd,
      'equidistantPreserveStart' => AxisInterval.equidistantPreserveStart,
      'equidistantPreserveEnd' => AxisInterval.equidistantPreserveEnd,
      _ => null,
    };
  }

  AxisPadding? padding() {
    final v = raw['padding'];
    if (v == 'gap') return AxisPadding.gap;
    if (v == 'no-gap') return AxisPadding.noGap;
    if (v is Map) {
      double side(String s) => (v[s] as num?)?.toDouble() ?? 0;
      return AxisPadding(left: side('left'), right: side('right'), top: side('top'), bottom: side('bottom'));
    }
    return null;
  }

  Object tick() {
    final v = raw['tick'];
    if (v is bool) return v;
    if (v is Map) {
      return TextStyle(
        color: v['fill'] is String ? parseCssColor(v['fill'] as String) : null,
        fontSize: (v['fontSize'] as num?)?.toDouble(),
      );
    }
    return true;
  }

  Object? svgOrBool(String k) {
    final v = raw[k];
    if (v is bool) return v;
    if (v is Map) {
      final s = _Props(v.cast<String, dynamic>());
      return SvgStyle(
        fill: s.color('fill'),
        fillOpacity: s.dbl('fillOpacity'),
        stroke: s.color('stroke'),
        strokeWidth: s.dbl('strokeWidth'),
        strokeOpacity: s.dbl('strokeOpacity'),
        strokeDasharray: s.dash('strokeDasharray'),
        r: s.dbl('r'),
        radius: s.raw['radius'],
      );
    }
    return null;
  }
}

/// `textOptions` of a SunburstChart; absent means the chart's defaults.
SunburstTextOptions _sunburstText(Object? raw) {
  if (raw is! Map) return SunburstTextOptions.defaults;
  final p = _Props(raw.cast<String, dynamic>());
  final weight = raw['fontWeight'];
  return SunburstTextOptions(
    fontWeight: weight == 'bold' ? FontWeight.bold : (weight is num ? FontWeight.values[(weight ~/ 100 - 1).clamp(0, 8)] : null),
    fontSize: p.dbl('fontSize'),
    fill: p.color('fill'),
    stroke: p.color('stroke'),
    strokeWidth: p.dbl('strokeWidth') ?? 1,
    strokeBeforeFill: raw['paintOrder'] == 'stroke fill',
    dx: p.dbl('dx') ?? 0,
    dy: p.dbl('dy') ?? 0,
    angle: p.dbl('angle') ?? 0,
    pointerEventsNone: raw['pointerEvents'] == 'none',
  );
}

// ---- sankey: helpers ----
SvgStyle? _sankeyStyle(Object? v) {
  if (v is! Map<String, dynamic>) return null;
  final p = _Props(v);
  return SvgStyle.css(
    fill: _cssPaint(p, 'fill'),
    fillOpacity: p.dbl('fillOpacity'),
    stroke: _cssPaint(p, 'stroke'),
    strokeWidth: p.dbl('strokeWidth'),
    strokeOpacity: p.dbl('strokeOpacity'),
    strokeDasharray: p.dash('strokeDasharray'),
    radius: v['radius'],
  );
}
// ---- end sankey ----

// ---- treemap: helpers ----
Widget _treemap(_Props p, double? w, double? h, List<Object?> data, List<RechartsElement> children) {
  const d = Treemap();
  return Treemap(
    width: w,
    height: h,
    data: data,
    dataKey: p.raw['dataKey'] ?? d.dataKey,
    nameKey: p.raw['nameKey'] ?? d.nameKey,
    aspectRatio: p.dbl('aspectRatio') ?? d.aspectRatio,
    nodeInset: p.dbl('nodeInset') ?? 0,
    nodeGap: p.dbl('nodeGap') ?? 0,
    fill: p.color('fill'),
    stroke: p.color('stroke'),
    type: p.str('type') == 'nest' ? TreemapType.nest : TreemapType.flat,
    colorPanel: [for (final c in (p.raw['colorPanel'] as List? ?? const [])) ?parseCssColor(c as String)].nullIfEmpty,
    isAnimationActive: p.boolean('isAnimationActive'),
    isUpdateAnimationActive: p.boolean('isUpdateAnimationActive'),
    animationBegin: p.dbl('animationBegin')?.toInt() ?? 0,
    animationDuration: p.dbl('animationDuration')?.toInt() ?? 1500,
    animationEasing: p.str('animationEasing') ?? 'linear',
    children: children,
  );
}

extension on List<Color> {
  List<Color>? get nullIfEmpty => isEmpty ? null : this;
}
// ---- end treemap ----

// ---- polar: helpers ----

/// Radar and RadialBar `fill`: absent stays null (SVG black), `'none'` paints nothing.
Color? _polarFill(_Props p) => p.raw['fill'] == 'none' ? cssNone : p.color('fill');

// ---- end polar ----
