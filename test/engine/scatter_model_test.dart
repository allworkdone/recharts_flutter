// Scatter, ZAxis and ErrorBar geometry ported from Recharts 3.10.1 specs:
// test/cartesian/Scatter.spec.tsx, Scatter.animation.spec.tsx, ErrorBar.spec.tsx
// and test/chart/ScatterChart.spec.tsx. jsdom measures text as 0x0, so text
// is measured as zero; the one Legend case passes the 50px its spec mocks.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/src/animation.dart';
import 'package:recharts_flutter/src/components.dart';
import 'package:recharts_flutter/src/core/curve.dart';
import 'package:recharts_flutter/src/core/symbols.dart';
import 'package:recharts_flutter/src/engine/axis.dart' show getErrorDomainByDataKey;
import 'package:recharts_flutter/src/engine/model.dart';
import 'package:recharts_flutter/src/render/label.dart';
import 'package:recharts_flutter/src/render/painter.dart';
import 'package:recharts_flutter/src/util.dart';

CartesianModel model(String chartName, double w, double h, List<RechartsElement> children,
        {List<Object?> data = const [],
        ChartLayout layout = ChartLayout.horizontal,
        Margin margin = const Margin.all(5),
        Size legendSize = Size.zero}) =>
    computeCartesianModel(
        chartName: chartName,
        size: Size(w, h),
        data: data,
        children: children,
        layout: layout,
        margin: margin,
        legendSize: legendSize,
        measureFor: (_) => (_) => Size.zero);

/// `{cx, cy, width}` of every point, like expectScatterPoints.
List<List<double?>> points(CartesianModel m) => [
      for (final s in m.series)
        for (final p in s.scatterPoints ?? const <ScatterPoint>[]) [p.cx, p.cy, p.width],
    ];

/// `{x1, x2, y1, y2}` of every error bar line, like expectErrorBars.
List<List<double>> errorBarLines(CartesianModel m) => [
      for (final s in m.series)
        for (final (_, lines) in s.errorBars)
          for (final l in lines) [l.p1.dx, l.p2.dx, l.p1.dy, l.p2.dy],
    ];

class _Sink implements PathSink {
  final StringBuffer d = StringBuffer();
  String _n(double v) => jsString(v);
  @override
  void moveTo(double x, double y) => d.write('M${_n(x)},${_n(y)}');
  @override
  void lineTo(double x, double y) => d.write('L${_n(x)},${_n(y)}');
  @override
  void bezierCurveTo(double x1, double y1, double x2, double y2, double x, double y) => d.write('C');
  @override
  void closePath() => d.write('Z');
}

// test/_data.ts
const pageData = [
  {'name': 'Page A', 'uv': 400, 'pv': 2400, 'amt': 2400},
  {'name': 'Page B', 'uv': 300, 'pv': 4567, 'amt': 2400},
  {'name': 'Page C', 'uv': 300, 'pv': 1398, 'amt': 2400},
  {'name': 'Page D', 'uv': 200, 'pv': 9800, 'amt': 2400},
  {'name': 'Page E', 'uv': 278, 'pv': 3908, 'amt': 2400},
  {'name': 'Page F', 'uv': 189, 'pv': 4800, 'amt': 2400},
];

const r64 = 9.0270333367641; // width of a size-64 point

void main() {
  group('Scatter.spec.tsx', () {
    test('Render symbols in a simple Scatter', () {
      const data = [
        {'cx': 10, 'cy': 50},
        {'cx': 50, 'cy': 50},
        {'cx': 90, 'cy': 50},
        {'cx': 130, 'cy': 50},
        {'cx': 170, 'cy': 50},
      ];
      final m = model('ScatterChart', 500, 500, const [Scatter(data: data, dataKey: 'cx')]);
      expect(points(m), [
        [54, 467.77777777777777, r64],
        [152, 358.8888888888889, r64],
        [250, 250, r64],
        [348, 141.11111111111111, r64],
        [446, 32.222222222222236, r64],
      ]);
    });

    test("Don't render any symbols when data is empty", () {
      expect(points(model('ScatterChart', 500, 500, const [Scatter(data: [])])), isEmpty);
    });

    test('Tooltip integration: should return tooltip payload', () {
      final m = model('ScatterChart', 100, 100, const [
        Scatter(data: pageData),
        XAxis(dataKey: 'uv'),
        YAxis(dataKey: 'pv'),
      ]);
      final payload = tooltipPayloadOf(m, 0, items: m.items, itemEventType: true);
      expect([for (final e in payload) (e.dataKey, e.name, e.value, e.unit, e.color, e.hide)], [
        ('uv', 'uv', 400, '', null, false),
        ('pv', 'pv', 2400, '', null, false),
      ]);
      expect(payload.every((e) => identical(e.payload, pageData[0])), isTrue);
    });
  });

  group('Scatter.animation.spec.tsx', () {
    final expectedUv = [
      [12.5, 5.0, r64],
      [27.5, 27.5, r64],
      [42.5, 27.5, r64],
      [57.5, 50.0, r64],
      [72.5, 32.45, r64],
      [87.5, 52.475, r64],
    ];

    test('renders the scatter dots in final position', () {
      expect(points(model('ScatterChart', 100, 100, const [Scatter(data: pageData, dataKey: 'uv')])), expectedUv);
    });

    test('with <Legend /> sibling (50px legend)', () {
      final m = model('ScatterChart', 100, 100, const [Legend(), Scatter(data: pageData, dataKey: 'uv')],
          legendSize: const Size(50, 50));
      expect([for (final p in points(m)) p[1]], [5, 15, 15, 25, 17.200000000000003, 26.100000000000005]);
    });

    test('entrance grows the size from 0 and keeps the dots in place', () {
      final target = model('ScatterChart', 100, 100, const [Scatter(data: pageData, dataKey: 'uv')]).series[0].scatterPoints!;
      String d(double t) {
        final step = interpolateScatterPoints(matchAnimationItems(null, target, MatchBy.append), t);
        expect([for (final p in step) [p.cx, p.cy]], [for (final p in expectedUv) [p[0], p[1]]]);
        final sink = _SymbolSink();
        drawSymbol(sink, SymbolType.circle, step[0].size!);
        return sink.d.toString();
      }

      expect([d(0), d(0.1), d(0.5), d(0.9), d(1)], [
        'M0,0',
        'M1.427,0A1.427,1.427,0,1,1,-1.427,0A1.427,1.427,0,1,1,1.427,0',
        'M3.192,0A3.192,3.192,0,1,1,-3.192,0A3.192,3.192,0,1,1,3.192,0',
        'M4.282,0A4.282,4.282,0,1,1,-4.282,0A4.282,4.282,0,1,1,4.282,0',
        'M4.514,0A4.514,4.514,0,1,1,-4.514,0A4.514,4.514,0,1,1,4.514,0',
      ]);
    });

    test('should animate dots positions after dataKey change', () {
      final uv = model('ScatterChart', 100, 100, const [Scatter(data: pageData, dataKey: 'uv')]).series[0].scatterPoints!;
      final pv = model('ScatterChart', 100, 100, const [Scatter(data: pageData, dataKey: 'pv')]).series[0].scatterPoints!;
      final items = matchAnimationItems(uv, pv, MatchBy.append);
      expect([for (final t in [0.0, 0.1, 0.5, 0.9, 1.0]) interpolateScatterPoints(items, t)[0].cy],
          [5, 11.84, 39.2, 66.56, 73.4]);
      expect([for (final t in [0.0, 0.5, 1.0]) interpolateScatterPoints(items, t)[0].cx], [12.5, 12.5, 12.5]);
    });
  });

  group('ScatterChart.spec.tsx', () {
    const data01 = [
      {'x': 100, 'y': 200, 'z': 200},
      {'x': 120, 'y': 100, 'z': 260},
      {'x': 170, 'y': 300, 'z': 400},
      {'x': 140, 'y': 250, 'z': 280},
      {'x': 150, 'y': 400, 'z': 500},
      {'x': 110, 'y': 280, 'z': 200},
    ];
    const data02 = [
      {'x': 200, 'y': 260, 'z': 240},
      {'x': 240, 'y': 290, 'z': 220},
      {'x': 190, 'y': 290, 'z': 250},
      {'x': 198, 'y': 250, 'z': 210},
      {'x': 180, 'y': 280, 'z': 260},
      {'x': 210, 'y': 220, 'z': 230},
    ];

    test('Render 2 Scatter (ZAxis range [4, 20], category XAxis)', () {
      final m = model(
        'ScatterChart',
        400,
        400,
        const [
          XAxis(dataKey: 'x', name: 'stature', unit: 'cm'),
          YAxis(dataKey: 'y', name: 'weight', unit: 'kg'),
          ZAxis(dataKey: 'z', range: [4, 20], name: 'score', unit: 'km'),
          CartesianGrid(),
          Scatter(name: 'A school', data: data01, fillOpacity: 0.3, fill: Color(0xFFFF7300)),
          Scatter(name: 'B school', data: data02, fill: Color(0xFF347300)),
          Tooltip(),
        ],
        margin: const Margin(top: 20, right: 20, bottom: 20),
      );
      expect(points(m), [
        [73.33333333333333, 185, 3.638913473173784],
        [100, 267.5, 3.960594802695323],
        [126.66666666666667, 102.5, 4.624978308224887],
        [153.33333333333334, 143.75, 4.062165001543845],
        [180.00000000000003, 20, 5.046265044040321],
        [206.66666666666669, 119.00000000000001, 3.638913473173784],
        [73.33333333333333, 135.5, 3.8563503319209342],
        [100, 110.75000000000001, 3.749208526326083],
        [126.66666666666667, 110.75000000000001, 3.9088200952233594],
        [153.33333333333334, 143.75, 3.694472617243352],
        [180.00000000000003, 119.00000000000001, 3.960594802695323],
        [206.66666666666669, 168.49999999999997, 3.803156745151513],
      ]);
      // x, y and z entries with the axes' names and units.
      final payload = tooltipPayloadOf(m, 2, items: [m.items[1]], itemEventType: true);
      expect([for (final e in payload) '${e.name} : ${e.value}${e.unit}'], ['stature : 190cm', 'weight : 290kg', 'score : 250km']);
      expect(payload.every((e) => e.color == const Color(0xFF347300)), isTrue);
    });

    group('ScatterChart with joint line', () {
      const data01 = [
        {'x': 10, 'y': 30, 'z': 120},
        {'x': 30, 'y': 200, 'z': 190},
        {'x': 45, 'y': 100, 'z': 32},
        {'x': 50, 'y': 400, 'z': 67},
        {'x': 70, 'y': 150, 'z': 109},
        {'x': 100, 'y': 250, 'z': 120},
      ];
      const data02 = [
        {'x': 30, 'y': 20, 'z': 190},
        {'x': 50, 'y': 180, 'z': 32},
        {'x': 75, 'y': 240, 'z': 67},
        {'x': 100, 'y': 100, 'z': 109},
        {'x': 120, 'y': 190, 'z': 120},
      ];
      final m = model('ScatterChart', 600, 400, const [
        CartesianGrid(),
        XAxis(type: AxisDomainType.number, dataKey: 'x', name: 'stature', unit: 'cm'),
        YAxis(type: AxisDomainType.number, dataKey: 'y', name: 'weight', unit: 'kg'),
        ZAxis(type: AxisDomainType.number, dataKey: 'z', range: [100, 200]),
        Scatter(name: 'A school', data: data01, fill: Color(0xFF8884D8), line: true, shape: SymbolType.cross),
        Scatter(name: 'B school', data: data02, fill: Color(0xFF82CA9D), line: true, shape: SymbolType.diamond),
      ]);

      test('should render scatter points', () {
        expect(points(m), [
          [109.16666666666666, 338, 14.413156615213909],
          [197.5, 185, 15.957691216057308],
          [263.75, 275, 12.197048368812888],
          [285.83333333333337, 5, 13.12335329012121],
          [374.1666666666667, 230, 14.155129698337069],
          [506.6666666666667, 140, 14.413156615213909],
          [197.5, 347, 15.957691216057308],
          [285.83333333333337, 203.00000000000003, 12.197048368812888],
          [396.25, 149, 13.12335329012121],
          [506.6666666666667, 275, 14.155129698337069],
          [595, 194, 14.413156615213909],
        ]);
      });

      test('ZAxis domain is [0, 190] without nice ticks', () {
        // z = 190 maps to the top of the range.
        expect(m.series[0].scatterPoints![1].size, 200);
        expect(m.series[0].scatterPoints![2].size, closeTo(100 + 32 / 190 * 100, 1e-12));
      });
    });

    group('ScatterChart of two dimension data', () {
      const data = [
        {'x': 100, 'y': 200, 'z': 200},
        {'x': 120, 'y': 100, 'z': 260},
        {'x': 170, 'y': 300, 'z': 400},
        {'x': 140, 'y': 250, 'z': 280},
        {'x': 150, 'y': 400, 'z': 500},
        {'x': 110, 'y': 280, 'z': 200},
      ];
      const expected = [
        [105, 185, r64],
        [155, 267.5, r64],
        [205, 102.5, r64],
        [255, 143.75, r64],
        [305, 20, r64],
        [355, 119.00000000000001, r64],
      ];
      const margin = Margin(top: 20, right: 20, bottom: 20, left: 20);

      test('renders 6 circles in simple ScatterChart', () {
        final m = model(
            'ScatterChart',
            400,
            400,
            const [
              XAxis(dataKey: 'x', name: 'stature', unit: 'cm'),
              YAxis(dataKey: 'y', name: 'weight', unit: 'kg'),
              Scatter(line: true, name: 'A school', data: data, fill: Color(0xFFFF7300)),
            ],
            margin: margin);
        expect(points(m), expected);
      });

      test('renders 6 circles when data is defined on chart root', () {
        final m = model(
            'ScatterChart',
            400,
            400,
            const [
              XAxis(dataKey: 'x', name: 'stature', unit: 'cm'),
              YAxis(dataKey: 'y', name: 'weight', unit: 'kg'),
              Scatter(line: true, name: 'A school', fill: Color(0xFFFF7300)),
            ],
            data: data,
            margin: margin);
        expect(points(m), expected);
      });

      test('renders 6 circles on chart root data with no axes', () {
        expect(points(model('ScatterChart', 400, 400, const [Scatter(dataKey: 'y')], data: data)), [
          [37.5, 200, r64],
          [102.5, 297.5, r64],
          [167.5, 102.5, r64],
          [232.5, 151.25, r64],
          [297.5, 5, r64],
          [362.5, 122.00000000000001, r64],
        ]);
      });

      test('renders line when line prop=true', () {
        const scatter = Scatter(line: true, name: 'A school', data: data, fill: Color(0xFFFF7300));
        final m = model(
            'ScatterChart',
            400,
            400,
            const [XAxis(dataKey: 'x'), YAxis(dataKey: 'y'), scatter],
            margin: margin);
        final line = scatterLine(scatter, m.series[0].scatterPoints!);
        final sink = _Sink();
        drawLine(sink, line.points, line.type);
        expect(sink.d.toString(), 'M105,185L155,267.5L205,102.5L255,143.75L305,20L355,119');
      });

      test('ignores points when data have nulls in it', () {
        final m = model(
            'ScatterChart',
            400,
            400,
            const [
              XAxis(dataKey: 'x'),
              YAxis(dataKey: 'y'),
              Scatter(name: 'A school', data: [
                {'x': null, 'y': 2},
                {'x': 3, 'y': 4},
              ], fill: Color(0xFFFF7300)),
            ],
            margin: margin);
        // The category axis has one tick, so only the first point gets an x.
        expect(points(m), [
          [230, 185, r64],
          [null, 20, r64],
        ]);
      });
    });

    test('allowDuplicatedCategory=false category axes', () {
      final m = model('ScatterChart', 500, 500, const [
        XAxis(type: AxisDomainType.category, allowDuplicatedCategory: false, dataKey: 'x'),
        YAxis(type: AxisDomainType.category, allowDuplicatedCategory: false, dataKey: 'y'),
        Scatter(data: [
          {'x': 100, 'y': 100, 'z': 200},
          {'x': 100, 'y': 200, 'z': 200},
          {'x': 100, 'y': 300, 'z': 200},
        ]),
      ]);
      expect(points(m), [
        [280, 388.33333333333337, r64],
        [280, 235, r64],
        [280, 81.66666666666667, r64],
      ]);
    });
  });

  group('Scatter props', () {
    const data = [
      {'x': 10, 'y': 20},
      {'x': 30, 'y': 40},
    ];
    const children = [
      XAxis(type: AxisDomainType.number, dataKey: 'x'),
      YAxis(type: AxisDomainType.number, dataKey: 'y'),
    ];

    test('legend payload: computeLegendPayloadFromScatterProps', () {
      final m = model('ScatterChart', 400, 400, const [
        ...children,
        Scatter(name: 'A', data: data, fill: Color(0xFF8884D8)),
        Scatter(dataKey: 'y', data: data, legendType: LegendType.wye, hide: true),
      ]);
      expect([for (final p in legendPayloadOf(m.items, const Legend(itemSorter: null))) (p.value, p.type, p.color, p.inactive)], [
        ('A', LegendType.circle, const Color(0xFF8884D8), false),
        ('y', LegendType.wye, null, true),
      ]);
    });

    test('LabelList entries are the boxes around the symbols, in the plot area', () {
      final m = model('ScatterChart', 400, 400, const [...children, Scatter(data: data, label: true)]);
      final p = m.series[0].scatterPoints![1];
      final e = labelListEntries(m.series[0], m.size, viewBox: m.viewBox)[1];
      expect(e.viewBox, Rect.fromLTWH(p.cx! - r64 / 2, p.cy! - r64 / 2, r64, r64));
      expect(e.value, isNull);
      expect(e.parentViewBox, m.viewBox);
    });

    test('Cells are matched to points by index', () {
      const cell = Cell(fill: Color(0xFFFF0000));
      final m = model('ScatterChart', 400, 400, const [...children, Scatter(data: data, children: [Cell(), cell])]);
      expect(m.series[0].scatterPoints![1].cell, same(cell));
    });

    test('a hidden Scatter has no error bars and leaves the domain', () {
      final m = model('ScatterChart', 400, 400, const [
        ...children,
        Scatter(data: data, hide: true, children: [ErrorBar(dataKey: 'y')]),
        Scatter(data: [
          {'x': 1, 'y': 2},
        ]),
      ]);
      expect(m.series[0].errorBars, isEmpty);
      expect(m.axes.firstWhere((a) => !a.runtime.isX).runtime.domain, [0, 2]);
    });
  });

  test('ComposedChart: the axis tooltip lists the scatter point at the active index', () {
    const data = [
      {'name': 'Page A', 'uv': 590, 'cnt': 490},
      {'name': 'Page B', 'uv': 868, 'cnt': 590},
      {'name': 'Page C', 'uv': 1397, 'cnt': 350},
    ];
    final m = model('ComposedChart', 500, 400, const [
      XAxis(dataKey: 'name', scale: 'band'),
      YAxis(),
      Line(dataKey: 'uv'),
      Scatter(dataKey: 'cnt', fill: Color(0xFFFF0000)),
    ], data: data);
    expect([for (final e in tooltipPayloadOf(m, 2)) (e.name, e.value)], [('uv', 1397), ('name', 'Page C'), (null, 350)]);
    // Band scale: the points sit in the middle of the bands.
    final x = m.tooltipAxis.scale!;
    expect(m.series[1].scatterPoints![2].cx, x.map('Page C')! + x.bandwidth! / 2);
  });

  group('ErrorBar.spec.tsx', () {
    const dataWithError = [
      {'name': 'food', 'uv': 2000, 'pv': 2013, 'time': 1, 'uvError': [100, 50], 'pvError': [110, 20]},
      {'name': 'cosmetic', 'uv': 3300, 'pv': 2000, 'time': 2, 'uvError': [120, 140], 'pvError': 50},
      {'name': 'storage', 'uv': 3200, 'pv': 1398, 'time': 3, 'uvError': [120, 80], 'pvError': [200, 100]},
      {'name': 'digital', 'uv': 2800, 'pv': 2800, 'time': 4, 'uvError': [100, 200], 'pvError': 30},
    ];

    test('Renders Error Bars in Bar', () {
      final m = model('BarChart', 500, 500, const [
        Bar(isAnimationActive: false, dataKey: 'uv', children: [ErrorBar(dataKey: 'uvError')]),
      ], data: dataWithError);
      expect(errorBarLines(m), [
        [61.25, 71.25, 215.97222222222223, 215.97222222222223],
        [66.25, 66.25, 236.38888888888889, 215.97222222222223],
        [61.25, 71.25, 236.38888888888889, 236.38888888888889],
        [183.75, 193.75, 26.777777777777754, 26.777777777777754],
        [188.75, 188.75, 62.16666666666668, 26.777777777777754],
        [183.75, 193.75, 62.16666666666668, 62.16666666666668],
        [306.25, 316.25, 48.555555555555564, 48.555555555555564],
        [311.25, 311.25, 75.77777777777779, 48.555555555555564],
        [306.25, 316.25, 75.77777777777779, 75.77777777777779],
        [428.75, 438.75, 86.66666666666666, 86.66666666666666],
        [433.75, 433.75, 127.5, 86.66666666666666],
        [428.75, 438.75, 127.5, 127.5],
      ]);
    });

    test('Renders Error Bars in Line', () {
      const lineData = [
        {'name': 'Page A', 'uv': 1000, 'pv': 2400, 'amt': 2400, 'uvError': [75, 20], 'pvError': [90, 40]},
        {'name': 'Page B', 'uv': 300, 'pv': 4567, 'amt': 2400, 'uvError': [90, 40], 'pvError': [75, 20]},
        {'name': 'Page C', 'uv': 280, 'pv': 1398, 'amt': 2400, 'uvError': 40, 'pvError': 20},
        {'name': 'Page D', 'uv': 200, 'pv': 9800, 'amt': 2400, 'uvError': 20, 'pvError': 28},
        {'name': 'Page I', 'uv': 189, 'pv': 4800, 'amt': 2400, 'uvError': 28, 'pvError': 40},
      ];
      final m = model('LineChart', 500, 500, const [
        Line(isAnimationActive: false, dataKey: 'uv', children: [ErrorBar(dataKey: 'uvError')]),
      ], data: lineData);
      expect(errorBarLines(m), [
        [0, 10, 78.50000000000001, 78.50000000000001],
        [5, 5, 117.29166666666666, 78.50000000000001],
        [0, 10, 117.29166666666666, 117.29166666666666],
        [122.5, 132.5, 356.1666666666667, 356.1666666666667],
        [127.5, 127.5, 409.25, 356.1666666666667],
        [122.5, 132.5, 409.25, 409.25],
        [245, 255, 364.33333333333337, 364.33333333333337],
        [250, 250, 397, 364.33333333333337],
        [245, 255, 397, 397],
        [367.5, 377.5, 405.1666666666667, 405.1666666666667],
        [372.5, 372.5, 421.5, 405.1666666666667],
        [367.5, 377.5, 421.5, 421.5],
        [490, 500, 406.3916666666666, 406.3916666666666],
        [495, 495, 429.2583333333333, 406.3916666666666],
        [490, 500, 429.2583333333333, 429.2583333333333],
      ]);
    });

    test('renders two ErrorBars in ScatterChart, one for XAxis another for YAxis', () {
      final m = model('ScatterChart', 500, 500, const [
        Scatter(isAnimationActive: false, data: dataWithError, dataKey: 'uv', children: [
          ErrorBar(dataKey: 'uvError', direction: ErrorBarDirection.y),
          ErrorBar(dataKey: 'pvError', direction: ErrorBarDirection.x),
        ]),
        XAxis(type: AxisDomainType.number),
      ]);
      expect(points(m), [
        [326671.6666666667, 209.44444444444443, r64],
        [539005, 43.33333333333335, r64],
        [522671.6666666667, 56.111111111111136, r64],
        [457338.3333333333, 107.22222222222221, r64],
      ]);
      expect(m.series[0].errorBars, hasLength(2));
      expect(errorBarLines(m).sublist(0, 3), [
        [326666.6666666667, 326676.6666666667, 203.05555555555557, 203.05555555555557],
        [326671.6666666667, 326671.6666666667, 222.2222222222222, 203.05555555555557],
        [326666.6666666667, 326676.6666666667, 222.2222222222222, 222.2222222222222],
      ]);
      expect(errorBarLines(m).sublist(12, 15), [
        [329938.3333333333, 329938.3333333333, 214.44444444444443, 204.44444444444443],
        [308705, 329938.3333333333, 209.44444444444443, 209.44444444444443],
        [308705, 308705, 214.44444444444443, 204.44444444444443],
      ]);
      expect(errorBarLines(m).last, [452438.3333333333, 452438.3333333333, 112.22222222222221, 102.22222222222221]);
    });

    test('extending YAxis domain when data is declared on chart container', () {
      List<Object?> ticks(List<RechartsElement> children) => [
            for (final t in model('BarChart', 500, 500, children, data: dataWithError).axes.single.ticks) t.value,
          ];
      expect(ticks(const [YAxis(dataKey: 'uv'), Bar(dataKey: 'uv')]), [0, 850, 1700, 2550, 3400]);
      expect(ticks(const [
        YAxis(dataKey: 'uv'),
        Bar(dataKey: 'uv', children: [ErrorBar(dataKey: 'uvError')]),
      ]), [0, 900, 1800, 2700, 3600]);
    });

    test('extending YAxis domain when Scatter has its own data (boxplot example)', () {
      const boxPlotData = [
        {'category': 'A', 'min': 16, 'q1': 20, 'q3': 29, 'max': 35},
        {'category': 'B', 'min': 12, 'q1': 15, 'q3': 21, 'max': 27},
        {'category': 'C', 'min': 22, 'q1': 26, 'q3': 34, 'max': 39},
        {'category': 'D', 'min': 9, 'q1': 13, 'q3': 20, 'max': 26},
      ];
      Object? box(Object? e) => [(e as Map)['q1'], e['q3']];
      Object? whisker(Object? e) => [((e as Map)['q3'] as num) - (e['min'] as num), (e['max'] as num) - (e['q3'] as num)];
      final m = model('BarChart', 500, 500, [
        const YAxis(),
        Bar(isAnimationActive: false, dataKey: box, children: [ErrorBar(dataKey: whisker)]),
        const Scatter(data: [
          {'category': 'A', 'value': 10},
          {'category': 'B', 'value': 5},
          {'category': 'D', 'value': 25},
        ], dataKey: 'value'),
      ], data: boxPlotData);
      expect(m.axes.single.runtime.domain, [0, 39]);
    });

    group('with numeric strings in the data', () {
      const numbers = [
        {'name': 'a', 'uv': 10, 'err': 2},
        {'name': 'b', 'uv': 20, 'err': [4, 1]},
      ];
      const numericStrings = [
        {'name': 'a', 'uv': '10', 'err': '2'},
        {'name': 'b', 'uv': '20', 'err': ['4', '1']},
      ];
      for (final (name, data) in [('numbers', numbers), ('numeric strings', numericStrings)]) {
        test('should draw the same whiskers on a Line for $name', () {
          final m = model('LineChart', 400, 300, const [
            XAxis(dataKey: 'name'),
            YAxis(domain: [0, 30]),
            Line(dataKey: 'uv', isAnimationActive: false, children: [ErrorBar(dataKey: 'err', isAnimationActive: false)]),
          ], data: data);
          // a: 10 - 2 to 10 + 2, b: 20 - 4 to 20 + 1
          expect(errorBarLines(m), [
            [60, 70, 161, 161],
            [65, 65, 195.66666666666669, 161],
            [60, 70, 195.66666666666669, 195.66666666666669],
            [390, 400, 83.00000000000001, 83.00000000000001],
            [395, 395, 126.33333333333334, 83.00000000000001],
            [390, 400, 126.33333333333334, 126.33333333333334],
          ]);
        });

        test('should draw the same whiskers on a vertical Bar for $name', () {
          final m = model('BarChart', 400, 300, const [
            XAxis(type: AxisDomainType.number, domain: [0, 30]),
            YAxis(type: AxisDomainType.category, dataKey: 'name'),
            Bar(dataKey: 'uv', isAnimationActive: false, children: [ErrorBar(dataKey: 'err', isAnimationActive: false)]),
          ], data: data, layout: ChartLayout.vertical);
          expect(errorBarLines(m), [
            [197, 197, 75, 65],
            [153, 197, 70, 70],
            [153, 153, 75, 65],
            [296, 296, 205, 195],
            [241, 296, 200, 200],
            [241, 241, 205, 195],
          ]);
        });
      }

      for (final (name, data) in [
        ('numbers', const [{'name': 'a', 'uv': 10, 'err': 50}]),
        ('numeric strings', const [{'name': 'a', 'uv': '10', 'err': '50'}]),
      ]) {
        test('should extend the YAxis domain by the error values for $name', () {
          final m = model('LineChart', 400, 300, const [
            XAxis(dataKey: 'name'),
            YAxis(),
            Line(dataKey: 'uv', isAnimationActive: false, children: [ErrorBar(dataKey: 'err', isAnimationActive: false)]),
          ], data: data);
          // 10 - 50 and 10 + 50
          expect(m.axes.firstWhere((a) => !a.runtime.isX).runtime.domain, [-40, 60]);
        });
      }

      for (final (name, zero) in [('a number', 0), ('a numeric string', '0')]) {
        test('should draw no whisker for a zero error given as $name', () {
          final m = model('LineChart', 400, 300, const [
            XAxis(dataKey: 'name'),
            YAxis(domain: [0, 30]),
            Line(dataKey: 'uv', isAnimationActive: false, children: [ErrorBar(dataKey: 'err', isAnimationActive: false)]),
          ], data: [
            {'name': 'a', 'uv': 10, 'err': zero},
            const {'name': 'b', 'uv': 20, 'err': 2},
          ]);
          // only b: 20 - 2 to 20 + 2
          expect(errorBarLines(m), [
            [390, 400, 74.33333333333336, 74.33333333333336],
            [395, 395, 109, 74.33333333333336],
            [390, 400, 109, 109],
          ]);
        });
      }
    });

    // errorValue.spec.ts
    test('getErrorDomainByDataKey reads numeric strings as numbers, the same as the data value', () {
      const entry = {
        'val': '2',
        'errX': '3',
        'errY': ['11', '13'],
      };
      const errorBars = [
        ErrorBar(dataKey: 'errX', direction: ErrorBarDirection.x),
        ErrorBar(dataKey: 'errY', direction: ErrorBarDirection.y),
      ];
      expect(getErrorDomainByDataKey(entry, '2', errorBars), [-1, 5, -9, 15]);
    });

    test('getErrorDomainByDataKey reads a ranged value of numeric strings by its larger end', () {
      const entry = {
        'val': ['1', '5'],
        'errY': '3',
      };
      expect(getErrorDomainByDataKey(entry, ['1', '5'], const [ErrorBar(dataKey: 'errY', direction: ErrorBarDirection.y)]),
          [2, 8]);
    });
  });
}

class _SymbolSink implements SymbolPathSink {
  final StringBuffer d = StringBuffer();
  String _n(double v) => jsString(v);
  @override
  void moveTo(double x, double y) => d.write('M${_n(x)},${_n(y)}');
  @override
  void lineTo(double x, double y) => d.write('L${_n(x)},${_n(y)}');
  @override
  void arcTo(double rx, double ry, bool largeArc, bool sweep, double x, double y) =>
      d.write('A${_n(rx)},${_n(ry)},0,${largeArc ? 1 : 0},${sweep ? 1 : 0},${_n(x)},${_n(y)}');
  @override
  void closePath() => d.write('Z');
}
