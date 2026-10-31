// Area geometry ported from Recharts 3.10.1 specs: test/cartesian/Area.spec.tsx,
// test/chart/AreaChart.spec.tsx, AreaChart.stacked.spec.tsx,
// test/state/selectors/areaSelectors.spec.tsx and the reveal/interpolation
// cases of test/cartesian/Area.animation.spec.tsx. Those specs measure text as
// 0x0 (jsdom) or mock a size no asserted geometry depends on, so text is zero here.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/src/animation.dart';
import 'package:recharts_flutter/src/components.dart';
import 'package:recharts_flutter/src/core/curve.dart';
import 'package:recharts_flutter/src/core/easing.dart';
import 'package:recharts_flutter/src/core/scale.dart';
import 'package:recharts_flutter/src/engine/axis.dart';
import 'package:recharts_flutter/src/engine/get_ticks.dart';
import 'package:recharts_flutter/src/engine/model.dart';
import 'package:recharts_flutter/src/render/painter.dart';
import 'package:recharts_flutter/src/util.dart';

StringMeasurer zero(CartesianAxisElement? _) => (_) => Size.zero;

CartesianModel model(double w, double h, List<Object?> data, List<RechartsElement> children,
        {String chartName = 'AreaChart',
        ChartLayout layout = ChartLayout.horizontal,
        StackOffset stackOffset = StackOffset.none,
        Margin margin = const Margin.all(5),
        Object? baseValue}) =>
    computeCartesianModel(
        chartName: chartName,
        size: Size(w, h),
        data: data,
        children: children,
        layout: layout,
        margin: margin,
        stackOffset: stackOffset,
        baseValue: baseValue,
        measureFor: zero);

/// d3-path output: absolute commands, numbers as JS prints them.
class _SvgSink implements PathSink {
  final b = StringBuffer();
  String n(double v) => jsString(v);
  @override
  void moveTo(double x, double y) => b.write('M${n(x)},${n(y)}');
  @override
  void lineTo(double x, double y) => b.write('L${n(x)},${n(y)}');
  @override
  void bezierCurveTo(double x1, double y1, double x2, double y2, double x, double y) =>
      b.write('C${n(x1)},${n(y1)},${n(x2)},${n(y2)},${n(x)},${n(y)}');
  @override
  void closePath() => b.write('Z');
}

String svg(void Function(PathSink) draw) {
  final s = _SvgSink();
  draw(s);
  return s.b.toString();
}

Area areaOf(SeriesModel s) => s.item.element as Area;

/// `.recharts-area-area`: the fill curve with its baseLine.
String fillD(CartesianModel m, [int i = 0]) {
  final s = m.series[i];
  return svg((sink) => drawArea(sink, pointOffsets(s.points!), areaBaseLineOf(s.baseLine), areaOf(s).type,
      layout: m.layout, connectNulls: areaOf(s).connectNulls));
}

/// `.recharts-area-curve`: the stroke over the points.
String strokeD(CartesianModel m, [int i = 0]) {
  final s = m.series[i];
  return svg((sink) =>
      drawLine(sink, pointOffsets(s.points!), areaOf(s).type, layout: m.layout, connectNulls: areaOf(s).connectNulls));
}

List<List<Object?>> xy(List<LinePoint> ps) => [
      for (final p in ps) [p.x, p.y],
    ];

// Area.spec.tsx
const dataXyv = [
  {'x': 10, 'y': 50, 'value': 100},
  {'x': 50, 'y': 50, 'value': 100},
  {'x': 90, 'y': 50, 'value': 100},
  {'x': 130, 'y': 50, 'value': 100},
  {'x': 170, 'y': 50, 'value': 100},
];

// test/_data.ts PageData
const page6 = [
  {'name': 'Page A', 'uv': 400, 'pv': 2400, 'amt': 2400},
  {'name': 'Page B', 'uv': 300, 'pv': 4567, 'amt': 2400},
  {'name': 'Page C', 'uv': 300, 'pv': 1398, 'amt': 2400},
  {'name': 'Page D', 'uv': 200, 'pv': 9800, 'amt': 2400},
  {'name': 'Page E', 'uv': 278, 'pv': 3908, 'amt': 2400},
  {'name': 'Page F', 'uv': 189, 'pv': 4800, 'amt': 2400},
];

// storybook/stories/data/Page.ts pageData
const page7 = [
  {'name': 'Page A', 'uv': 590, 'pv': 800, 'amt': 1400},
  {'name': 'Page B', 'uv': 590, 'pv': 800, 'amt': 1400},
  {'name': 'Page C', 'uv': 868, 'pv': 967, 'amt': 1506},
  {'name': 'Page D', 'uv': 1397, 'pv': 1098, 'amt': 989},
  {'name': 'Page E', 'uv': 1480, 'pv': 1200, 'amt': 1228},
  {'name': 'Page F', 'uv': 1520, 'pv': 1108, 'amt': 1100},
  {'name': 'Page G', 'uv': 1400, 'pv': 680, 'amt': 1700},
];

void main() {
  group('Area.spec.tsx: baseValue and curve paths', () {
    for (final chart in ['AreaChart', 'ComposedChart']) {
      CartesianModel m(List<RechartsElement> children, {ChartLayout layout = ChartLayout.horizontal}) =>
          model(500, 500, dataXyv, children, chartName: chart, layout: layout);

      test('$chart horizontal: baseValue defaults to zero', () {
        final r = m(const [Area(dataKey: 'value'), YAxis()]);
        expect(fillD(r), 'M65,5L172.5,5L280,5L387.5,5L495,5L495,495L387.5,495L280,495L172.5,495L65,495Z');
        expect(strokeD(r), 'M65,5L172.5,5L280,5L387.5,5L495,5');
      });

      test('$chart horizontal: baseValue defaults to the first number in domain', () {
        final r = m(const [Area(dataKey: 'value'), YAxis(domain: [20, 300])]);
        expect(fillD(r), 'M65,355L172.5,355L280,355L387.5,355L495,355L495,495L387.5,495L280,495L172.5,495L65,495Z');
        expect(strokeD(r), 'M65,355L172.5,355L280,355L387.5,355L495,355');
      });

      test('$chart horizontal: baseValue dataMin / dataMax', () {
        expect(fillD(m(const [Area(dataKey: 'value', baseValue: 'dataMin'), YAxis(domain: [20, 300])])),
            'M65,355L172.5,355L280,355L387.5,355L495,355L495,495L387.5,495L280,495L172.5,495L65,495Z');
        final max = m(const [Area(dataKey: 'value', baseValue: 'dataMax'), YAxis(domain: [20, 300])]);
        expect(fillD(max), 'M65,355L172.5,355L280,355L387.5,355L495,355L495,5L387.5,5L280,5L172.5,5L65,5Z');
        expect(strokeD(max), 'M65,355L172.5,355L280,355L387.5,355L495,355');
      });

      test('$chart vertical: baseValue defaults to zero', () {
        final r = m(const [Area(dataKey: 'value'), XAxis(type: AxisDomainType.number), YAxis(dataKey: 'y')],
            layout: ChartLayout.vertical);
        expect(fillD(r),
            'M495,388.333L495,388.333L495,388.333L495,388.333L495,388.333L65,388.333L65,388.333L65,388.333L65,388.333L65,388.333Z');
        expect(strokeD(r), 'M495,388.333L495,388.333L495,388.333L495,388.333L495,388.333');
      });

      test('$chart vertical: no curve without a YAxis dataKey', () {
        for (final children in const [
          [Area(dataKey: 'value'), XAxis(type: AxisDomainType.number)],
          [Area(dataKey: 'value'), XAxis(type: AxisDomainType.number), YAxis()],
        ]) {
          final r = m(children, layout: ChartLayout.vertical);
          expect(fillD(r), '');
          expect(strokeD(r), '');
        }
      });

      test('$chart vertical: baseValue default, dataMin and dataMax', () {
        CartesianModel v(Object? baseValue) => m([
              Area(dataKey: 'value', baseValue: baseValue),
              const XAxis(type: AxisDomainType.number),
              const YAxis(dataKey: 'y', domain: [20, 300]),
            ], layout: ChartLayout.vertical);
        const minD =
            'M495,54.286L495,54.286L495,54.286L495,54.286L495,54.286L65,54.286L65,54.286L65,54.286L65,54.286L65,54.286Z';
        expect(fillD(v(null)), minD);
        expect(fillD(v('dataMin')), minD);
        expect(fillD(v('dataMax')),
            'M495,54.286L495,54.286L495,54.286L495,54.286L495,54.286L495,54.286L495,54.286L495,54.286L495,54.286L495,54.286Z');
        expect(strokeD(v('dataMax')), 'M495,54.286L495,54.286L495,54.286L495,54.286L495,54.286');
      });

      test('$chart without axes: baseValue 0, number, dataMin, dataMax', () {
        CartesianModel n(Object? baseValue) => m([Area(dataKey: 'value', baseValue: baseValue)]);
        const stroke = 'M5,5L127.5,5L250,5L372.5,5L495,5';
        expect(fillD(n(null)), 'M5,5L127.5,5L250,5L372.5,5L495,5L495,495L372.5,495L250,495L127.5,495L5,495Z');
        expect(fillD(n(9)), 'M5,5L127.5,5L250,5L372.5,5L495,5L495,450.9L372.5,450.9L250,450.9L127.5,450.9L5,450.9Z');
        expect(fillD(n('dataMin')), 'M5,5L127.5,5L250,5L372.5,5L495,5L495,495L372.5,495L250,495L127.5,495L5,495Z');
        expect(fillD(n('dataMax')), 'M5,5L127.5,5L250,5L372.5,5L495,5L495,5L372.5,5L250,5L127.5,5L5,5Z');
        expect(strokeD(n(9)), stroke);
      });

      test('$chart: the event payload of the fill curve (points and baseLine)', () {
        final s = m(const [Area(dataKey: 'value')]).series.single;
        expect(s.baseLine, 495);
        expect(xy(s.points!), [
          [5, 5],
          [127.5, 5],
          [250, 5],
          [372.5, 5],
          [495, 5],
        ]);
        expect(s.points!.map((p) => p.value), everyElement([0, 100]));
        expect(s.points!.map((p) => p.payload), dataXyv);
      });
    }

    test('the chart baseValue applies when the Area has none; the Area wins', () {
      expect(fillD(model(500, 500, dataXyv, const [Area(dataKey: 'value')], baseValue: 'dataMax')),
          'M5,5L127.5,5L250,5L372.5,5L495,5L495,5L372.5,5L250,5L127.5,5L5,5Z');
      expect(fillD(model(500, 500, dataXyv, const [Area(dataKey: 'value', baseValue: 9)], baseValue: 'dataMax')),
          'M5,5L127.5,5L250,5L372.5,5L495,5L495,450.9L372.5,450.9L250,450.9L127.5,450.9L5,450.9Z');
    });

    test('Area renders only in AreaChart and ComposedChart', () {
      for (final chart in ['LineChart', 'BarChart']) {
        final m = model(500, 500, dataXyv, const [Area(dataKey: 'value')], chartName: chart);
        expect(m.series.single.points, isNull);
        // ... but still feeds the axes and the tooltip.
        expect(tooltipPayloadOf(m, 0).single.value, 100);
      }
    });
  });

  group('Area.spec.tsx: getBaseValue', () {
    AxisRuntime axis(List<Object> domain, AxisDomainType type, {bool isX = false}) =>
        AxisRuntime(settings: isX ? const XAxis() : const YAxis(), isX: isX, type: type)
          ..scale = type == AxisDomainType.number
              ? LinearScale(domain: domain.cast<num>(), range: const [0, 1])
              : PointScale(domain: domain, range: const [0, 1]);
    final x = axis([0, 500], AxisDomainType.number, isX: true), y = axis([0, 500], AxisDomainType.number);

    test('numbers win, the item over the chart', () {
      expect(getBaseValue(ChartLayout.horizontal, null, 8, x, y), 8);
      expect(getBaseValue(ChartLayout.horizontal, 9, null, x, y), 9);
      expect(getBaseValue(ChartLayout.horizontal, 9, 10, x, y), 10);
      expect(getBaseValue(ChartLayout.horizontal, null, double.nan, x, axis([30, 40], AxisDomainType.number)), 30);
    });

    // [domain, axis type, expected] for undefined/NaN, 'dataMin' and 'dataMax'.
    const n = AxisDomainType.number, c = AxisDomainType.category;
    final cases = <Object?, List<(List<Object>, AxisDomainType, num)>>{
      null: [
        ([4, 5], n, 4), ([5, 4], n, 4), ([5, 4], c, 5), ([-10, -20], n, -10), ([-20, -10], n, -10),
        ([-10, -20], c, -10), ([-20, -10], c, -20),
      ],
      'dataMin': [
        ([4, 5], n, 4), ([5, 4], n, 4), ([5, 4], c, 5), ([-10, -20], n, -20), ([-20, -10], n, -20),
        ([-10, -20], c, -10), ([-20, -10], c, -20),
      ],
      'dataMax': [
        ([4, 5], n, 5), ([5, 4], n, 5), ([5, 4], c, 4), ([-10, -20], n, -10), ([-20, -10], n, -10),
        ([-10, -20], c, -20), ([-20, -10], c, -10),
      ],
    };
    for (final MapEntry(key: baseValue, value: rows) in cases.entries) {
      for (final (domain, type, expected) in rows) {
        test('baseValue $baseValue, $type domain $domain -> $expected', () {
          expect(getBaseValue(ChartLayout.horizontal, baseValue, baseValue, x, axis(domain, type)), expected);
          expect(getBaseValue(ChartLayout.vertical, baseValue, baseValue, axis(domain, type, isX: true), y), expected);
        });
      }
    }
  });

  group('Area.spec.tsx: state integration', () {
    test('legend and tooltip payloads', () {
      final m = model(500, 500, dataXyv, const [Area(dataKey: 'value'), Tooltip()]);
      final legend = legendPayloadOf(m.items, const Legend(itemSorter: null)).single;
      expect(legend.color, const Color(0xFF3182BD));
      expect(legend.dataKey, 'value');
      expect(legend.inactive, false);
      expect(legend.type, LegendType.line);
      expect(legend.value, 'value');
      final entry = tooltipPayloadOf(m, 2).single;
      expect(entry.color, const Color(0xFF3182BD));
      expect(entry.fill, const Color(0xFF3182BD));
      expect(entry.stroke, const Color(0xFF3182BD));
      expect(entry.name, 'value');
      expect(entry.value, 100);
      expect(entry.unit, isNull);
    });

    test('getLegendItemColor: the fill when stroke is none', () {
      final m = model(500, 500, dataXyv, const [Area(dataKey: 'value', stroke: null, fill: Color(0xFF00FF00))]);
      expect(legendPayloadOf(m.items, const Legend()).single.color, const Color(0xFF00FF00));
      expect(tooltipPayloadOf(m, 0).single.color, const Color(0xFF00FF00));
    });
  });

  group('AreaChart.spec.tsx', () {
    test('Renders 2 path in simple AreaChart', () {
      final m = model(100, 50, page6, const [Area(type: CurveType.monotone, dataKey: 'uv')]);
      expect(strokeD(m),
          'M5,5C11,10,17,15,23,15C29,15,35,15,41,15C47,15,53,25,59,25C65,25,71,17.2,77,17.2C83,17.2,89,21.65,95,26.1');
    });

    test('Renders 1 dot and no path when data only have one element', () {
      final s = model(100, 50, page6.sublist(0, 1), const [Area(type: CurveType.monotone, dataKey: 'pv')]).series.single;
      expect(s.points, hasLength(1));
    });

    test('Renders 4 path in a stacked AreaChart', () {
      final m = model(100, 50, page6, const [
        Area(type: CurveType.monotone, dataKey: 'uv', stackId: 'test'),
        Area(type: CurveType.monotone, dataKey: 'pv', stackId: 'test'),
      ]);
      expect(strokeD(m, 0),
          'M5,43.4C11,43.6,17,43.8,23,43.8C29,43.8,35,43.8,41,43.8C47,43.8,53,44.2,59,44.2C65,44.2,71,43.888,77,43.888C83,43.888,89,44.066,95,44.244');
      expect(strokeD(m, 1),
          'M5,33.8C11,29.666,17,25.532,23,25.532C29,25.532,35,38.208,41,38.208C47,38.208,53,5,59,5C65,5,71,28.256,77,28.256C83,28.256,89,26.65,95,25.044');
    });

    test('Renders a path in a vertical AreaChart', () {
      final m = model(100, 50, page6, const [
        XAxis(type: AxisDomainType.number),
        YAxis(dataKey: 'name', type: AxisDomainType.category),
        Area(type: CurveType.monotone, dataKey: 'uv'),
      ], layout: ChartLayout.vertical);
      expect(strokeD(m),
          'M95,5C91.25,5.667,87.5,6.333,87.5,7C87.5,7.667,87.5,8.333,87.5,9C87.5,9.667,80,10.333,80,11C80,11.667,85.85,12.333,85.85,13C85.85,13.667,82.513,14.333,79.175,15');
    });

    test('renders a stacked percentage chart', () {
      final m = model(500, 400, page7, const [
        XAxis(dataKey: 'name'),
        YAxis(),
        Area(dataKey: 'uv', stackId: '1', id: 'area-1'),
        Area(dataKey: 'pv', stackId: '1'),
        Area(dataKey: 'amt', stackId: '1'),
      ], stackOffset: StackOffset.expand, margin: const Margin(top: 10, right: 30, left: 20, bottom: 20));
      final s = m.series.first;
      expect(xy(s.baseLine! as List<LinePoint>), [
        for (final x in [80, 145, 210, 275, 340, 405, 470]) [x, 350],
      ]);
      expect(s.isRange, false);
      expect(xy(s.points!), [
        [80, 278.10035842293905],
        [145, 278.10035842293905],
        [210, 261.6671655193056],
        [275, 213.66819747416764],
        [340, 221.23848515864896],
        [405, 211.3733905579399],
        [470, 224.07407407407408],
      ]);
      expect(s.points!.map((p) => p.value), [
        [0, 0.2114695340501792],
        [0, 0.2114695340501792],
        [0, 0.25980245435498356],
        [0, 0.40097588978185994],
        [0, 0.37871033776867963],
        [0, 0.40772532188841204],
        [0, 0.37037037037037035],
      ]);
      expect([for (var i = 0; i < 3; i++) strokeD(m, i)], [
        'M80,278.1L145,278.1L210,261.667L275,213.668L340,221.238L405,211.373L470,224.074',
        'M80,180.609L145,180.609L210,163.26L275,106.515L340,116.837L405,110.322L470,162.91',
        'M80,10L145,10L210,10L275,10L340,10L405,10L470,10',
      ]);
    });

    test('renders a stacked chart when x-axis is of type number', () {
      const data = [
        {'xKey': 4000, 'uv': 400, 'pv': 2400},
        {'xKey': 6000, 'uv': 300, 'pv': 4567},
        {'xKey': 8000, 'uv': 300, 'pv': 1398},
        {'xKey': 10000, 'uv': 200, 'pv': 9800},
        {'xKey': 12000, 'uv': 278, 'pv': 3908},
        {'xKey': 14000, 'uv': 189, 'pv': 4800},
      ];
      final m = model(500, 400, data, const [
        XAxis(type: AxisDomainType.number, dataKey: 'xKey', domain: ['dataMin', 'dataMax']),
        Area(dataKey: 'uv', stackId: '1'),
        Area(dataKey: 'pv', stackId: '1'),
      ]);
      expect([for (final t in m.axes.single.runtime.ticksOfAxis!) [t.coordinate, t.value]], [
        [5, 4000],
        [127.5, 6500],
        [250, 9000],
        [372.5, 11500],
        [495, 14000],
      ]);
      expect(strokeD(m, 0), 'M5,350.6L103,354.2L201,354.2L299,357.8L397,354.992L495,358.196');
      expect(strokeD(m, 1), 'M5,264.2L103,189.788L201,303.872L299,5L397,214.304L495,185.396');
      final s = m.series.first;
      expect(xy(s.baseLine! as List<LinePoint>), [
        for (final x in [5, 103, 201, 299, 397, 495]) [x, 365],
      ]);
      expect(xy(s.points!), [
        [5, 350.59999999999997],
        [103, 354.2],
        [201, 354.2],
        [299, 357.8],
        [397, 354.992],
        [495, 358.19599999999997],
      ]);
    });

    test('renders a stacked chart when stackId is a number', () {
      final m = model(500, 400, page7, const [Area(dataKey: 'uv', stackId: '1'), Area(dataKey: 'pv', stackId: 1)]);
      expect(strokeD(m, 0), 'M5,312.821L86.667,312.821L168.333,274.1L250,200.418L331.667,188.857L413.333,183.286L495,200');
      expect(strokeD(m, 1), 'M5,201.393L86.667,201.393L168.333,139.411L250,47.482L331.667,21.714L413.333,28.957L495,105.286');
      final s = m.series.first;
      expect(xy(s.baseLine! as List<LinePoint>), [
        [5, 395],
        [86.66666666666667, 395],
        [168.33333333333334, 395],
        [250, 395],
        [331.6666666666667, 395],
        [413.33333333333337, 395],
        [495, 395],
      ]);
      expect(s.points!.map((p) => p.y), [
        312.82142857142856,
        312.82142857142856,
        274.09999999999997,
        200.41785714285714,
        188.85714285714286,
        183.2857142857143,
        200,
      ]);
    });

    const connectData = [
      {'name': 'Page A', 'uv': 400, 'pv': 2400, 'amt': 2400},
      {'name': 'Page B', 'uv': 300, 'amt': 2400},
      {'name': 'Page C', 'uv': 300, 'pv': 1398, 'amt': 2400},
    ];
    List<RechartsElement> stacked3({bool connectNulls = false}) => [
          for (final k in ['uv', 'pv', 'amt'])
            Area(stackId: '1', connectNulls: connectNulls, type: CurveType.monotone, dataKey: k),
        ];

    test('Renders null points as 0 if stacked and connectNulls is true', () {
      final m = model(100, 50, connectData, stacked3(connectNulls: true));
      expect([for (var i = 0; i < 3; i++) strokeD(m, i)], [
        'M5,42.333C20,42.667,35,43,50,43C65,43,80,43,95,43',
        'M5,26.333C20,34.667,35,43,50,43C65,43,80,38.34,95,33.68',
        'M5,10.333C20,18.667,35,27,50,27C65,27,80,22.34,95,17.68',
      ]);
    });

    const allNullData = [
      {'name': 'Page A', 'uv': 400, 'pv': 2400, 'amt': 2400},
      {'name': 'Page B'},
      {'name': 'Page C', 'uv': 300, 'pv': 1398, 'amt': 2400},
    ];

    test('connects across points where every stacked series is null if connectNulls is true', () {
      final m = model(100, 50, allNullData, stacked3(connectNulls: true));
      for (var i = 0; i < 3; i++) {
        final d = strokeD(m, i);
        expect(RegExp(r'[a-zA-Z][\d ,.-]+').allMatches(d), hasLength(2));
        expect(d, startsWith('M5,'));
      }
    });

    test('breaks at points where every stacked series is null if connectNulls is false', () {
      final m = model(100, 50, allNullData, stacked3());
      for (var i = 0; i < 3; i++) {
        expect('M'.allMatches(strokeD(m, i)).length, greaterThan(1));
      }
    });
  });

  group('AreaChart.stacked.spec.tsx', () {
    const dataMerged = [
      {'name': 'a', 'value1': 5, 'value2': 10, 'value3': 23},
      {'name': 'b', 'value1': 25, 'value2': 10, 'value3': 13},
    ];
    const strokes = ['M65,335L495,215', 'M65,275L495,155', 'M65,137L495,77'];

    void expectStacked(CartesianModel m, {double secondX = 495}) {
      expect([for (final g in m.axes.where((a) => !a.runtime.isX).single.runtime.stackGroups!.values) g.stackedData.values], [
        [
          [[0, 5], [0, 25]],
          [[5, 15], [25, 35]],
          [[15, 38], [35, 48]],
        ],
      ]);
      final a1 = m.series[0], a2 = m.series[1];
      expect(xy(a1.baseLine! as List<LinePoint>), [
        [65, 365],
        [secondX, 365],
      ]);
      expect(xy(a1.points!), [
        [65, 335],
        [secondX, 214.99999999999997],
      ]);
      expect(a1.points!.map((p) => p.value), [
        [0, 5],
        [0, 25],
      ]);
      expect(xy(a2.baseLine! as List<LinePoint>), [
        [65, 335],
        [secondX, 214.99999999999997],
      ]);
      expect(xy(a2.points!), [
        [65, 275],
        [secondX, 154.99999999999997],
      ]);
      expect([for (var i = 0; i < 3; i++) strokeD(m, i)],
          secondX == 495 ? strokes : ['M65,335L151,215', 'M65,275L151,155', 'M65,137L151,77']);
    }

    List<RechartsElement> areas(String Function(int) key, {List<List<Object?>>? data}) => [
          for (var i = 1; i <= 3; i++)
            Area(type: CurveType.monotone, dataKey: key(i), stackId: '1', id: 'area$i', data: data?[i - 1]),
        ];

    test('with single data array', () {
      expectStacked(model(500, 400, dataMerged, [
        const XAxis(dataKey: 'name', allowDuplicatedCategory: false),
        const YAxis(dataKey: 'sum'),
        const Tooltip(),
        ...areas((i) => 'value$i'),
      ]));
    });

    test('with single data array, and without explicit XAxis dataKey', () {
      expectStacked(model(500, 400, dataMerged, [
        const XAxis(allowDuplicatedCategory: false),
        const YAxis(dataKey: 'sum'),
        const Tooltip(),
        ...areas((i) => 'value$i'),
      ]));
    });

    const data1 = [
      {'name': 'a', 'value': 5},
      {'name': 'b', 'value': 25},
    ];
    const data2 = [
      {'name': 'a', 'value': 10},
      {'name': 'b', 'value': 10},
    ];
    const data3 = [
      {'name': 'a', 'value': 23},
      {'name': 'b', 'value': 13},
    ];

    test('with multiple data arrays but each has their own dataKey', () {
      List<Object?> rename(List<Map<String, Object>> d, int i) => [
            for (final e in d) {'name': e['name'], 'value$i': e['value']},
          ];
      expectStacked(model(500, 400, const [], [
        const XAxis(dataKey: 'name', allowDuplicatedCategory: false),
        const YAxis(dataKey: 'sum'),
        const Tooltip(),
        ...areas((i) => 'value$i', data: [rename(data1, 1), rename(data2, 2), rename(data3, 3)]),
      ]));
    });

    test('with multiple data arrays with the same dataKey', () {
      expectStacked(model(500, 400, const [], [
        const XAxis(dataKey: 'name', allowDuplicatedCategory: false),
        const YAxis(dataKey: 'value'),
        const Tooltip(),
        ...areas((_) => 'value', data: [data1, data2, data3]),
      ]));
    });

    test('with multiple data arrays with the same dataKey, and without explicit XAxis dataKey', () {
      expectStacked(
          model(500, 400, const [], [
            const XAxis(allowDuplicatedCategory: false),
            const YAxis(dataKey: 'value'),
            const Tooltip(),
            ...areas((_) => 'value', data: [data1, data2, data3]),
          ]),
          secondX: 151);
    });

    test('stackOffset expand only fixes the numeric axis domain', () {
      const numericData = [
        {'x': 1, 'value1': 5, 'value2': 10},
        {'x': 2, 'value1': 15, 'value2': 20},
        {'x': 3, 'value1': 25, 'value2': 10},
      ];
      final m = model(400, 400, numericData, const [
        XAxis(dataKey: 'x', type: AxisDomainType.number),
        YAxis(),
        Area(dataKey: 'value1', stackId: '1'),
        Area(dataKey: 'value2', stackId: '1'),
      ], stackOffset: StackOffset.expand);
      expect(m.axes.where((a) => !a.runtime.isX).single.runtime.domain, [0, 1]);
      expect(m.axes.where((a) => a.runtime.isX).single.runtime.domain, isNot([0, 1]));
      expect(strokeD(m, 0), isNotEmpty);
      expect(strokeD(m, 1), isNotEmpty);
    });
  });

  group('stack offsets', () {
    List<RechartsElement> three() => const [
          YAxis(),
          Area(dataKey: 'uv', stackId: '1'),
          Area(dataKey: 'pv', stackId: '1'),
          Area(dataKey: 'amt', stackId: '1'),
        ];
    List<List<List<double>>> stacks(CartesianModel m) =>
        m.axes.single.runtime.stackGroups!.values.single.stackedData.values.toList();

    test('silhouette centres the stack around zero', () {
      final s = stacks(model(500, 400, page6, three(), stackOffset: StackOffset.silhouette));
      for (var j = 0; j < page6.length; j++) {
        expect(s.first[j][0], closeTo(-s.last[j][1], 1e-9));
      }
    });

    test('wiggle and silhouette extend the domain below zero', () {
      for (final offset in [StackOffset.silhouette, StackOffset.wiggle]) {
        final m = model(500, 400, page6, three(), stackOffset: offset);
        final domain = m.axes.single.runtime.domain!;
        final flat = stacks(m).expand((s) => s).expand((p) => p);
        expect(domain[0], flat.reduce((a, b) => a < b ? a : b));
        expect(domain[1], flat.reduce((a, b) => a > b ? a : b));
      }
    });

    test('a range value inside a stack keeps its own [low, high]', () {
      final m = model(500, 400, const [
        {'r': [1, 3], 'v': 5},
      ], const [
        Area(dataKey: 'v', stackId: '1'),
        Area(dataKey: 'r', stackId: '1'),
      ]);
      expect(m.series[1].points!.single.value, [1, 3]);
    });
  });

  test('a Brush slice reads the stack from dataStartIndex', () {
    final m = computeCartesianModel(
        chartName: 'AreaChart',
        size: const Size(100, 100),
        data: page6,
        children: const [Area(dataKey: 'uv', stackId: 's'), Area(dataKey: 'pv', stackId: 's')],
        dataStartIndex: 2,
        dataEndIndex: 3,
        measureFor: zero);
    expect(m.series[1].points!.map((p) => p.value), [
      [300, 1698],
      [200, 10000],
    ]);
    expect(m.series[1].points!.map((p) => p.payload), page6.sublist(2, 4));
  });

  group('areaSelectors.spec.tsx', () {
    test('points, baseline and isRange', () {
      final s = model(400, 400, page6, const [XAxis(dataKey: 'name'), Area(dataKey: 'uv', id: 'area-0')]).series.single;
      expect(s.baseLine, 365);
      expect(s.isRange, false);
      expect(xy(s.points!), [
        [5, 5],
        [83, 95],
        [161, 95],
        [239, 185],
        [317, 114.80000000000001],
        [395, 194.90000000000003],
      ]);
      expect(s.points!.map((p) => p.value), [
        [0, 400],
        [0, 300],
        [0, 300],
        [0, 200],
        [0, 278],
        [0, 189],
      ]);
      final pv = model(400, 400, page6, const [XAxis(dataKey: 'name'), Area(dataKey: 'pv')]).series.single;
      expect(pv.points!.map((p) => p.y), [
        278.59999999999997,
        200.588,
        314.672,
        12.200000000000006,
        224.31199999999998,
        192.20000000000002,
      ]);
    });

    test('a range area: [low, high] values, baseline at the lows', () {
      const rangeData = [
        {'day': '05-01', 'temperature': [-1, 10]},
        {'day': '05-02', 'temperature': [2, 15]},
        {'day': '05-03', 'temperature': [3, 12]},
      ];
      final m = model(400, 200, rangeData, const [
        XAxis(dataKey: 'day'),
        YAxis(),
        Tooltip(),
        Area(dataKey: 'temperature', type: CurveType.monotone),
      ]);
      final s = m.series.single;
      expect(s.isRange, true);
      final y = m.axes.where((a) => !a.runtime.isX).single.runtime.scale!;
      expect(s.points!.map((p) => p.y), [y.map(10), y.map(15), y.map(12)]);
      expect((s.baseLine! as List<LinePoint>).map((p) => p.y), [y.map(-1), y.map(2), y.map(3)]);
      expect(tooltipPayloadOf(m, 1).single.value, [2, 15]);
    });
  });

  group('Area.animation.spec.tsx', () {
    final linear = createEasingFunction('linear')!;
    final uv = model(100, 100, page6, const [Area(dataKey: 'uv')]).series.single;
    final pv = model(100, 100, page6, const [Area(dataKey: 'pv')]).series.single;

    test('the entrance clip rect grows left to right', () {
      Rect? clip(double p) => revealClipRect(linear(p), uv.points!, uv.baseLine!, ChartLayout.horizontal, 1);
      expect([for (final p in [0.0, 0.1, 0.2, 1.0]) clip(p)!.width], [0, 9.000000000000002, 18, 90]);
      for (final p in [0.0, 0.1, 0.2, 1.0]) {
        expect([clip(p)!.left, clip(p)!.top, clip(p)!.height], [5, 0, 96]);
      }
    });

    test('the vertical clip rect grows top to bottom with an unfloored width', () {
      final s = model(100, 100, page6, const [
        XAxis(type: AxisDomainType.number, hide: true),
        YAxis(dataKey: 'name', type: AxisDomainType.category, hide: true),
        Area(dataKey: 'uv', strokeWidth: 2.5),
      ], layout: ChartLayout.vertical).series.single;
      final r = revealClipRect(0.5, s.points!, s.baseLine!, ChartLayout.vertical, 2.5)!;
      expect([r.left, r.top, r.width, r.height], [0, 5, 95 + 2, 45]);
    });

    test('an empty clip when the end points are missing', () {
      expect(revealClipRect(0.5, const [LinePoint(null, 5, null, null), LinePoint(10, 5, null, null)], 0.0,
          ChartLayout.horizontal, 1), isNull);
    });

    test('changing dataKey interpolates the points (rounded) and ends on the raw ones', () {
      final items = matchAnimationItems(uv.points, pv.points, MatchBy.byIndex);
      List<LinePoint> at(double p) => interpolateAreaPoints(items, linear(p));
      String d(List<LinePoint> ps) => svg((sink) => drawLine(sink, pointOffsets(ps), CurveType.linear));
      expect(d(uv.points!), 'M5,5L23,27.5L41,27.5L59,50L77,32.45L95,52.475');
      expect(d(at(0.1)), 'M5,11.84L23,30.14L41,32.992L59,45.68L77,35.188L95,52.408');
      expect(d(at(0.9)), 'M5,66.56L23,51.257L41,76.926L59,11.12L77,57.09L95,51.868');
      expect(d(at(1)), 'M5,73.4L23,53.897L41,82.418L59,6.8L77,59.828L95,51.8');
      expect(at(0.1).map((p) => jsString(p.y)).join(','), '11.84,30.1397,32.9918,45.68,35.1878,52.4075');
      expect(at(0.9).map((p) => jsString(p.y)).join(','), '66.56,51.2573,76.9262,11.12,57.0902,51.8675');
      expect(at(1).map((p) => jsString(p.y)).join(','),
          '73.4,53.897000000000006,82.41799999999999,6.8000000000000025,59.827999999999996,51.8');
      expect(at(0.5).map((p) => jsString(p.x)).join(','), '5,23,41,59,77,95');
    });

    test('labels are the points value pairs (last element shown)', () {
      expect(uv.points!.map((p) => (p.value as List).last), [400, 300, 300, 200, 278, 189]);
    });

    test('baseLine: scalar values interpolate, entrance and arrays without a previous array do not', () {
      final b = AreaBaseLineAnimation();
      expect(b.step(95.0, 0, isEntrance: true), 95);
      expect(b.step(95.0, 0.5, isEntrance: true), 95);
      expect(b.step(95.0, 1, isEntrance: true), 95);
      b.restart();
      expect(b.step(55.0, 0, isEntrance: false), 95);
      expect(b.step(55.0, 0.25, isEntrance: false), 85);
      // Interrupted: the next cycle starts from the last drawn baseline.
      b.restart();
      expect(b.step(95.0, 0, isEntrance: false), 85);
      expect(b.step(95.0, 0.5, isEntrance: false), 90);
      // NaN animates towards 0.
      b.restart();
      expect(b.step(double.nan, 0.5, isEntrance: false), 45);
      // A list after a number: drawn at its target at once.
      b.restart();
      const target = [LinePoint(5, 10, null, null), LinePoint(15, 20, null, null)];
      expect(b.step(target, 0, isEntrance: false), target);
      expect(b.step(target, 0.5, isEntrance: false), target);
      // A list after a list interpolates point by point.
      b.restart();
      const next = [LinePoint(5, 30, null, null), LinePoint(15, 40, null, null)];
      expect(xy(b.step(next, 0.5, isEntrance: false) as List<LinePoint>), [
        [5, 20],
        [15, 30],
      ]);
    });
  });
}
