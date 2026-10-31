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
  final data = (p.raw['data'] as List? ?? const []).cast<Object?>();
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
        defaultIndex: p.dbl('defaultIndex')?.toInt(),
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
  }
  return null;
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

Cell _cell(_Props p) => Cell(
    fill: p.color('fill'), fillOpacity: p.dbl('fillOpacity'), stroke: p.color('stroke'), strokeWidth: p.dbl('strokeWidth'));

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

// ponytail: the common CSS named colors only; add more when a fixture needs them.
const _named = <String, int>{
  'black': 0xFF000000, 'white': 0xFFFFFFFF, 'red': 0xFFFF0000, 'green': 0xFF008000, 'blue': 0xFF0000FF,
  'yellow': 0xFFFFFF00, 'orange': 0xFFFFA500, 'purple': 0xFF800080, 'gray': 0xFF808080, 'grey': 0xFF808080,
  'pink': 0xFFFFC0CB, 'brown': 0xFFA52A2A, 'cyan': 0xFF00FFFF, 'magenta': 0xFFFF00FF, 'lime': 0xFF00FF00,
  'navy': 0xFF000080, 'teal': 0xFF008080, 'maroon': 0xFF800000, 'olive': 0xFF808000, 'silver': 0xFFC0C0C0,
  'gold': 0xFFFFD700, 'coral': 0xFFFF7F50, 'tomato': 0xFFFF6347, 'steelblue': 0xFF4682B4,
  'lightgray': 0xFFD3D3D3, 'lightgrey': 0xFFD3D3D3, 'darkgray': 0xFFA9A9A9, 'darkgrey': 0xFFA9A9A9,
  'transparent': 0x00000000,
};

Color? parseCssColor(String input) {
  final s = input.trim().toLowerCase();
  if (s == 'none') return null;
  if (_named.containsKey(s)) return Color(_named[s]!);
  if (s.startsWith('#')) {
    var hex = s.substring(1);
    if (hex.length == 3 || hex.length == 4) hex = hex.split('').map((c) => '$c$c').join();
    if (hex.length == 6) return Color(0xFF000000 | int.parse(hex, radix: 16));
    if (hex.length == 8) {
      final v = int.parse(hex, radix: 16);
      return Color(((v & 0xFF) << 24) | (v >> 8));
    }
  }
  final m = RegExp(r'^rgba?\(([^)]*)\)$').firstMatch(s);
  if (m != null) {
    final parts = m[1]!.split(RegExp(r'[,\s/]+')).where((e) => e.isNotEmpty).toList();
    int ch(String v) => v.endsWith('%') ? (double.parse(v.substring(0, v.length - 1)) * 2.55).round() : double.parse(v).round();
    final a = parts.length > 3 ? double.parse(parts[3]) : 1.0;
    return Color.fromARGB((a * 255).round(), ch(parts[0]), ch(parts[1]), ch(parts[2]));
  }
  return null;
}
