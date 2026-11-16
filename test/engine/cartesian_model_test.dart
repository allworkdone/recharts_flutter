// Coordinates ported from Recharts 3.11.0-canary.9 specs. Those specs run in jsdom where
// getStringSize measures every string as 0x0, so text is measured as zero here
// too unless a spec mocks it (getTicks.spec.ts: width = text.length, height = 12).

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/src/components.dart';
import 'package:recharts_flutter/src/core/curve.dart';
import 'package:recharts_flutter/src/engine/get_ticks.dart';
import 'package:recharts_flutter/src/engine/model.dart';
import 'package:recharts_flutter/src/render/painter.dart';
import 'package:recharts_flutter/src/util.dart';
import 'package:recharts_flutter/src/widgets/tooltip.dart';

StringMeasurer zero(CartesianAxisElement? _) => (_) => Size.zero;

CartesianModel model(String chartName, double w, double h, List<Object?> data, List<RechartsElement> children,
        {ChartLayout layout = ChartLayout.horizontal}) =>
    computeCartesianModel(
        chartName: chartName, size: Size(w, h), data: data, children: children, layout: layout, measureFor: zero);

List<List<double>> rects(CartesianModel m) => [
      for (final s in m.series)
        for (final r in s.rects!) [round4(r.x), round4(r.y), round4(r.width), round4(r.height)],
    ];

// test/_data.ts PageData
const pageData = [
  {'name': 'Page A', 'uv': 400, 'pv': 2400, 'amt': 2400},
  {'name': 'Page B', 'uv': 300, 'pv': 4567, 'amt': 2400},
  {'name': 'Page C', 'uv': 300, 'pv': 1398, 'amt': 2400},
  {'name': 'Page D', 'uv': 200, 'pv': 9800, 'amt': 2400},
  {'name': 'Page E', 'uv': 278, 'pv': 3908, 'amt': 2400},
  {'name': 'Page F', 'uv': 189, 'pv': 4800, 'amt': 2400},
];

// test/chart/BarChart.spec.tsx
const barData = [
  {'name': 'food', 'uv': 400, 'pv': 2400},
  {'name': 'cosmetic', 'uv': 300, 'pv': 4567},
  {'name': 'storage', 'uv': 300, 'pv': 1398},
  {'name': 'digital', 'uv': 200, 'pv': 9800},
];

void main() {
  group('BarChart.spec.tsx: rendering bar rectangles', () {
    test('renders simple BarChart', () {
      expect(rects(model('BarChart', 100, 50, barData, const [Bar(dataKey: 'uv')])), [
        [7.25, 5, 18, 40],
        [29.75, 15, 18, 30],
        [52.25, 15, 18, 30],
        [74.75, 25, 18, 20],
      ]);
    });

    test('Renders BarChart with two Bars', () {
      expect(rects(model('BarChart', 100, 50, barData, const [Bar(dataKey: 'uv'), Bar(dataKey: 'pv')])), [
        [7.25, 43.4, 7, 1.6],
        [29.75, 43.8, 7, 1.2],
        [52.25, 43.8, 7, 1.2],
        [74.75, 44.2, 7, 0.8],
        [18.25, 35.4, 7, 9.6],
        [40.75, 26.732, 7, 18.268],
        [63.25, 39.408, 7, 5.592],
        [85.75, 5.8, 7, 39.2],
      ]);
    });

    test('Renders 8 bars in a vertical BarChart', () {
      final m = model(
        'BarChart',
        100,
        50,
        barData,
        const [
          XAxis(type: AxisDomainType.number),
          YAxis(type: AxisDomainType.category, dataKey: 'name'),
          Bar(dataKey: 'uv'),
          Bar(dataKey: 'pv'),
        ],
        layout: ChartLayout.vertical,
      );
      expect(rects(m), [
        [65, 5.25, 1.2, 1],
        [65, 7.75, 0.9, 1],
        [65, 10.25, 0.9, 1],
        [65, 12.75, 0.6, 1],
        [65, 6.25, 7.2, 1],
        [65, 8.75, 13.701, 1],
        [65, 11.25, 4.194, 1],
        [65, 13.75, 29.4, 1],
      ]);
    });

    test('Renders 8 bars in a stacked BarChart', () {
      final m = model('BarChart', 100, 50, barData, const [
        YAxis(),
        Bar(dataKey: 'uv', stackId: 'test'),
        Bar(dataKey: 'pv', stackId: 'test'),
      ]);
      expect(rects(m), [
        [65.75, 43.4, 6, 1.6],
        [73.25, 43.8, 6, 1.2],
        [80.75, 43.8, 6, 1.2],
        [88.25, 44.2, 6, 0.8],
        [65.75, 33.8, 6, 9.6],
        [73.25, 25.532, 6, 18.268],
        [80.75, 38.208, 6, 5.592],
        [88.25, 5, 6, 39.2],
      ]);
    });
  });

  group('Bar.spec.tsx: own data', () {
    const ownData = [
      {'name': 'A', 'value': 10},
      {'name': 'B', 'value': 20},
    ];
    for (final chart in ['BarChart', 'ComposedChart']) {
      test('$chart renders Bar using its own data prop even when the chart root has no data', () {
        final m = model(chart, 400, 400, const [], const [
          XAxis(dataKey: 'name'),
          YAxis(),
          Bar(dataKey: 'value', data: ownData, isAnimationActive: false),
        ]);
        expect(m.series.single.rects, hasLength(2));
      });
    }

    test('the tooltip of a Bar with its own data reads the chart data (no dataDefinedOnItem)', () {
      final m = model('BarChart', 400, 400, const [], const [
        XAxis(dataKey: 'name'),
        Bar(dataKey: 'value', data: ownData),
      ]);
      expect(activeLabelOf(m, 1), 'B');
      final entry = tooltipPayloadOf(m, 1).single;
      expect(entry.payload, isNull);
      expect(entry.value, isNull);
    });
  });

  group('Bar.spec.tsx: minPointSize in a stacked bar chart', () {
    test('shifts a stack segment outward instead of overlapping the inflated one below it (horizontal)', () {
      final m = model('BarChart', 200, 400, const [
        {'name': 'a', 'small': 1, 'big': 100},
      ], const [
        XAxis(dataKey: 'name'),
        YAxis(),
        Bar(dataKey: 'small', stackId: 's', minPointSize: 20),
        Bar(dataKey: 'big', stackId: 's', minPointSize: 20),
      ]);
      final small = m.series[0].rects!.single, big = m.series[1].rects!.single;
      expect(small.height, 20);
      expect(big.y + big.height, closeTo(small.y, 1e-5));
    });

    test('shifts a stack segment outward instead of overlapping the inflated one before it (vertical)', () {
      final m = model(
          'BarChart',
          400,
          200,
          const [
            {'name': 'a', 'small': 1, 'big': 100},
          ],
          const [
            XAxis(type: AxisDomainType.number),
            YAxis(dataKey: 'name', type: AxisDomainType.category),
            Bar(dataKey: 'small', stackId: 's', minPointSize: 20),
            Bar(dataKey: 'big', stackId: 's', minPointSize: 20),
          ],
          layout: ChartLayout.vertical);
      final small = m.series[0].rects!.single, big = m.series[1].rects!.single;
      expect(small.width, 20);
      expect(big.x, closeTo(small.x + small.width, 1e-5));
    });

    test('cascades the shift across more than two segments in the same stack', () {
      final m = model('BarChart', 200, 400, const [
        {'name': 'a', 's1': 50, 's2': 1, 's3': 50},
      ], const [
        XAxis(dataKey: 'name'),
        YAxis(domain: [0, 101]),
        Bar(dataKey: 's1', stackId: 's', minPointSize: 20),
        Bar(dataKey: 's2', stackId: 's', minPointSize: 20),
        Bar(dataKey: 's3', stackId: 's', minPointSize: 20),
      ]);
      final [seg1, seg2, seg3] = [for (final s in m.series) s.rects!.single];
      expect(seg2.y + seg2.height, closeTo(seg1.y, 1e-5));
      expect(seg3.y + seg3.height, closeTo(seg2.y, 1e-5));
    });

    test('still avoids overlap when a Brush makes dataStartIndex non-zero', () {
      final m = computeCartesianModel(
        chartName: 'BarChart',
        size: const Size(200, 400),
        data: const [
          {'name': 'skipped', 'small': 50, 'big': 50},
          {'name': 'a', 'small': 1, 'big': 100},
        ],
        children: const [
          XAxis(dataKey: 'name'),
          YAxis(),
          Bar(dataKey: 'small', stackId: 's', minPointSize: 20),
          Bar(dataKey: 'big', stackId: 's', minPointSize: 20),
          Brush(dataKey: 'name', startIndex: 1, endIndex: 1, x: 0, y: 370, width: 200, height: 20),
        ],
        measureFor: zero,
        dataStartIndex: 1,
        dataEndIndex: 1,
      );
      final small = m.series[0].rects!.single, big = m.series[1].rects!.single;
      expect(small.height, 20);
      expect(big.y + big.height, closeTo(small.y, 1e-5));
    });
  });

  group('Bar.singleBand.spec.tsx: a single tick on a numeric axis', () {
    // [x, width] of each bar, rounded like the path.
    List<List<double>> spans(CartesianModel m) => [
          for (final r in m.series.single.rects!) [round4(r.x), round4(r.width)],
        ];
    CartesianModel lone(num x, {List<Object>? domain, Object? barSize, double? maxBarSize}) =>
        model('BarChart', 400, 300, [
          {'x': x, 'count': 10},
        ], [
          XAxis(dataKey: 'x', type: AxisDomainType.number, domain: domain),
          Bar(dataKey: 'count', barSize: barSize, maxBarSize: maxBarSize),
        ]);

    test('renders one bar for a single datum on a time-scale number axis', () {
      final time = DateTime.utc(2025).millisecondsSinceEpoch;
      final m = model('BarChart', 400, 300, [
        {'interval': time, 'count': 10},
      ], [
        XAxis(dataKey: 'interval', type: AxisDomainType.number, scale: 'time', domain: [time, time]),
        const YAxis(dataKey: 'count', type: AxisDomainType.number),
        const Bar(dataKey: 'count'),
      ]);
      expect(m.series.single.rects!.single.width, greaterThan(0));
    });

    test('renders one bar for a single datum on a default number axis', () {
      expect(spans(lone(5)), hasLength(1));
      expect(spans(lone(5)).single[1], greaterThan(0));
    });

    test('lets an explicit barSize win over the axis span', () {
      expect([for (final s in spans(lone(5, barSize: 20))) s[1]], [20]);
    });

    test('lets maxBarSize cap the bar width', () {
      expect([for (final s in spans(lone(5, maxBarSize: 30))) s[1]], [30]);
    });

    test('keeps the bar inside the plot area (x 5..395)', () {
      for (final (x, domain) in <(num, List<Object>?)>[
        (5, [0, 10]),
        (5, [5, 5]),
        (5, null),
        (1, [0, 10]),
        (9, [0, 10]),
      ]) {
        final s = spans(lone(x, domain: domain));
        expect(s, hasLength(1), reason: '$x $domain');
        expect(s.single[1], greaterThan(0));
        expect(s.single[0], greaterThanOrEqualTo(5));
        expect(s.single[0] + s.single[1], lessThanOrEqualTo(395));
      }
    });

    test('fills the plot area minus the category gap when the tick is centered', () {
      expect(spans(lone(5, domain: [5, 5])), [
        [44, 312],
      ]);
    });

    test('renders no bar rather than an overflowing one for a tick on the edge', () {
      expect(spans(lone(0, domain: [0, 10])), isEmpty);
      expect(spans(lone(10, domain: [0, 10])), isEmpty);
    });

    // BarChart.spec.tsx
    const onePointData = [
      {'number': 1, 'name': 'food', 'uv': 400, 'pv': 2400},
    ];
    test('renders a bar inside the plot area if barSize is not specified in a numerical XAxis', () {
      expect(
          rects(model('BarChart', 100, 50, onePointData, const [
            XAxis(dataKey: 'number', type: AxisDomainType.number, domain: [0, 2]),
            Bar(dataKey: 'uv', name: 'uv'),
          ])),
          [
            [14, 5, 72, 10],
          ]);
    });

    test('renders nothing instead of an overflowing bar if the only tick is on the edge', () {
      for (final domain in const [
        [1, 2],
        [0, 1],
      ]) {
        expect(
            rects(model('BarChart', 100, 50, onePointData, [
              XAxis(dataKey: 'number', type: AxisDomainType.number, domain: domain),
              const Bar(dataKey: 'uv', name: 'uv'),
            ])),
            isEmpty);
      }
    });
  });

  group('Line.animation.spec.tsx: points', () {
    test('LineChart 100x100 uv points', () {
      final m = model('LineChart', 100, 100, pageData, const [Line(dataKey: 'uv')]);
      expect([for (final p in m.series.single.points!) Offset(p.x!, round4(p.y!))], const [
        Offset(5, 5),
        Offset(23, 27.5),
        Offset(41, 27.5),
        Offset(59, 50),
        Offset(77, 32.45),
        Offset(95, 52.475),
      ]);
    });
  });

  group('Line.spec.tsx: null values in vertical layout', () {
    const nullData = [
      {'name': 'Page A', 'uv': 400},
      {'name': 'Page B', 'uv': 300},
      {'name': 'Page C', 'uv': null},
      {'name': 'Page D', 'uv': 278},
      {'name': 'Page E', 'uv': 189},
    ];
    int moveCount(bool connectNulls) {
      final m = model(
          'LineChart',
          400,
          400,
          nullData,
          [
            const XAxis(type: AxisDomainType.number),
            const YAxis(dataKey: 'name', type: AxisDomainType.category),
            Line(dataKey: 'uv', connectNulls: connectNulls),
          ],
          layout: ChartLayout.vertical);
      final sink = _MoveCounter();
      drawLine(sink, pointOffsets(m.series.single.points!), CurveType.linear,
          layout: m.layout, connectNulls: connectNulls);
      return sink.moves;
    }

    test('should break the line at a null value when connectNulls is false', () => expect(moveCount(false), 2));
    test('should connect the line across a null value when connectNulls is true', () => expect(moveCount(true), 1));
  });

  group('effectiveDataKeySelectors.spec.tsx: the graphical item dataKey wins over the value axis dataKey', () {
    test('should render both Lines when the YAxis has a dataKey too', () {
      List<List<Offset?>> lines(YAxis y) => [
            for (final s in model('LineChart', 400, 300, pageData, [
              const XAxis(dataKey: 'name'),
              y,
              const Line(dataKey: 'uv'),
              const Line(dataKey: 'pv'),
            ]).series)
              pointOffsets(s.points!),
          ];
      expect(lines(const YAxis(dataKey: 'uv')), lines(const YAxis()));
    });

    test('should compute the cartesian axis domain from the graphical item dataKey', () {
      final m = model('LineChart', 400, 300, pageData, const [XAxis(dataKey: 'name'), YAxis(dataKey: 'uv'), Line(dataKey: 'pv')]);
      expect(m.axes.firstWhere((a) => !a.runtime.isX).runtime.domain, [0, 9800]);
    });

    test('should keep the dataKey of the other axis', () {
      final m = model('LineChart', 400, 300, pageData,
          const [XAxis(dataKey: 'pv', type: AxisDomainType.number), YAxis(), Line(dataKey: 'uv')]);
      expect(m.axes.firstWhere((a) => a.runtime.isX).runtime.domain, [0, 9800]);
    });
  });

  group('XAxis.dataKey.spec.tsx', () {
    test('renders array indexes when dataKey is not specified', () {
      final m = model('LineChart', 400, 400, pageData, const [XAxis()]);
      final axis = m.axes.single;
      final labels = [for (final t in axis.ticks) (jsString(t.value), getTickLineCoord(axis, t).tick)];
      expect(labels, [
        ('0', const Offset(5, 373)),
        ('1', const Offset(83, 373)),
        ('2', const Offset(161, 373)),
        ('3', const Offset(239, 373)),
        ('4', const Offset(317, 373)),
        ('5', const Offset(395, 373)),
      ]);
      expect(axis.runtime.scale!.domain, [0, 1, 2, 3, 4, 5]);
    });
  });

  group('YAxis.ticks.spec.tsx', () {
    final data = [
      for (final d in pageData) {...d, 'pv': (d['pv']! as num) / 100},
    ];

    test('with default props', () {
      final m = model('LineChart', 500, 300, data, const [XAxis(dataKey: 'name'), YAxis(), Line(dataKey: 'pv')]);
      final y = m.axes.firstWhere((a) => !a.runtime.isX);
      expect(y.runtime.scale!.domain, [0, 100]);
      expect(y.runtime.niceTicks, [0, 25, 50, 75, 100]);
      expect([for (final t in y.runtime.ticksOfAxis!) t.coordinate], [265, 200, 135, 70, 5]);
      expect([for (final t in y.ticks) getTickLineCoord(y, t).tick], const [
        Offset(57, 265),
        Offset(57, 200),
        Offset(57, 135),
        Offset(57, 70),
        Offset(57, 5),
      ]);
      expect(m.offset.plotArea, const Rect.fromLTWH(65, 5, 430, 260));
    });

    test("with domain=['dataMin', 'dataMax']", () {
      final m = model('LineChart', 500, 300, data, const [
        XAxis(dataKey: 'name'),
        YAxis(domain: ['dataMin', 'dataMax']),
        Line(dataKey: 'pv'),
      ]);
      final y = m.axes.firstWhere((a) => !a.runtime.isX);
      expect(y.runtime.scale!.domain, [13.98, 98]);
      expect(y.runtime.niceTicks, [13.98, 38.98, 63.98, 88.98, 98]);
      final coords = [for (final t in y.runtime.ticksOfAxis!) t.coordinate];
      expect(coords[0], 265);
      expect(coords[1], closeTo(187.6374672696977, 1e-9));
      expect(coords[2], closeTo(110.27493453939539, 1e-9));
      expect(coords[3], closeTo(32.91240180909307, 1e-9));
      expect(coords[4], 5);
    });
  });

  group("YAxis.ticks.spec.tsx with domain=['auto', 'auto'] and tickCount=2 and data that crosses zero", () {
    final m = model('LineChart', 500, 300, const [
      {'name': 'a', 'pv': -10},
      {'name': 'b', 'pv': 10},
    ], const [
      XAxis(dataKey: 'name'),
      YAxis(domain: ['auto', 'auto'], tickCount: 2),
      Line(dataKey: 'pv'),
    ]);
    final y = m.axes.firstWhere((a) => !a.runtime.isX);

    test('should select niceTicks with zero in the middle', () {
      expect(y.runtime.niceTicks, [-10, 0, 10]);
    });

    test('should render 3 ticks', () {
      expect([for (final t in y.ticks) (jsString(t.value), getTickLineCoord(y, t).tick)], const [
        ('-10', Offset(57, 265)),
        ('0', Offset(57, 135)),
        ('10', Offset(57, 5)),
      ]);
    });
  });

  group("AreaChart.stacked.spec.tsx with stackOffset='expand' and a second, unstacked YAxis", () {
    const data = [
      {'name': 'a', 'uv': 10, 'pv': 30, 'price': 120},
      {'name': 'b', 'uv': 20, 'pv': 20, 'price': 480},
      {'name': 'c', 'uv': 30, 'pv': 10, 'price': 250},
    ];
    List<Object?>? domain(Object yAxisId, {List<Object>? rightAxisDomain, bool hideStackedAreas = false}) {
      final m = computeCartesianModel(
        chartName: 'AreaChart',
        size: const Size(400, 300),
        data: data,
        children: [
          const XAxis(dataKey: 'name'),
          const YAxis(yAxisId: 'left'),
          YAxis(yAxisId: 'right', orientation: AxisOrientation.right, domain: rightAxisDomain),
          Area(yAxisId: 'left', dataKey: 'uv', stackId: '1', hide: hideStackedAreas),
          Area(yAxisId: 'left', dataKey: 'pv', stackId: '1', hide: hideStackedAreas),
          const Line(yAxisId: 'right', dataKey: 'price'),
        ],
        stackOffset: StackOffset.expand,
        measureFor: zero,
      );
      return m.axes.firstWhere((a) => !a.runtime.isX && a.settings.id == yAxisId).runtime.domain;
    }

    test('should keep the [0, 1] domain on the stacked axis', () {
      expect(domain('left'), [0, 1]);
    });

    test('should keep the [0, 1] domain on the stacked axis when its areas are hidden', () {
      expect(domain('left', hideStackedAreas: true), [0, 1]);
    });

    test('should give the unstacked axis its own domain', () {
      expect(domain('right'), [0, 480]);
      expect(domain('right', rightAxisDomain: [0, 1000]), [0, 1000]);
    });

    test('a ZAxis with no stacked items keeps its domain too', () {
      final m = computeCartesianModel(
        chartName: 'ScatterChart',
        size: const Size(400, 300),
        data: const [],
        children: const [
          XAxis(dataKey: 'x', type: AxisDomainType.number),
          YAxis(dataKey: 'y', type: AxisDomainType.number),
          ZAxis(zAxisId: 'z', dataKey: 'z', range: [0, 100]),
          Scatter(zAxisId: 'z', data: [
            {'x': 1, 'y': 1, 'z': 5},
            {'x': 2, 'y': 2, 'z': 10},
          ]),
        ],
        stackOffset: StackOffset.expand,
        measureFor: zero,
      );
      // The domain [0, 10] maps z 10 to the end of the range.
      expect([for (final p in m.series.single.scatterPoints!) p.size], [50, 100]);
    });
  });

  group('getTicks.spec.ts (width = text.length, height = 12)', () {
    List<TickItem> ticks() => [
          for (final (i, v) in ['100_000_000_000_000', '200_000_000_000_000', '300_000_000_000_000',
            '400_000_000_000_000', '500_000_000_000_000', '600_000_000_000_000'].indexed)
            TickItem(value: v, coordinate: 50.0 + 20 * i, index: i),
        ];
    List<int> run(AxisInterval interval, double angle) => [
          for (final t in getTicks(
            tick: true,
            ticks: ticks(),
            viewBox: const Rect.fromLTWH(0, 0, 500, 500),
            minTickGap: 5,
            orientation: AxisOrientation.bottom,
            interval: interval,
            angle: angle,
            measure: (s) => Size(s.length.toDouble(), 12),
          ))
            t.index,
        ];

    test('preserveEnd shows every other tick, all of them at 60 degrees', () {
      expect(run(AxisInterval.preserveEnd, 0), [1, 3, 5]);
      expect(run(AxisInterval.preserveEnd, 60), [0, 1, 2, 3, 4, 5]);
    });

    test('preserveStart', () {
      expect(run(AxisInterval.preserveStart, 0), [0, 2, 4]);
      expect(run(AxisInterval.preserveStart, 60), [0, 1, 2, 3, 4, 5]);
    });
  });

  group('getEquidistantTicks.spec.ts', () {
    List<(Object?, double, double?)> shape(List<TickItem> ticks) => [for (final t in ticks) (t.value, t.coordinate, t.tickCoord)];
    double sizeOf(TickItem t, int _) => (t.value as num).toDouble();

    test('should return empty array if no ticks are passed', () {
      expect(getEquidistantTicks(1, (start: 0, end: 100), sizeOf, [], 0), isEmpty);
      expect(getEquidistantPreserveEndTicks(1, (start: 0, end: 100), sizeOf, [], 0), isEmpty);
    });

    for (final (fit, shown) in const [
      ([0, 1, 2, 3, 4, 5, 6, 7, 8, 9], [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]),
      ([0, 1, 2, 3, 4, 5, 6, 7, 8], [0, 2, 4, 6, 8]),
      ([0, 1, 2, 3, 4, 5, 6, 7], [0, 5]),
      ([0, 1, 2, 3, 4, 5, 6], [0, 5]),
      ([0, 1, 2, 3, 4, 5], [0, 5]),
      ([0, 1, 2, 3, 4], [0]),
      ([0, 1, 2, 3], [0]),
      ([0, 1, 2], [0]),
      ([0, 1], [0]),
      ([0], [0]),
      ([1, 2, 3, 4, 5, 6, 7, 8, 9], [0]),
    ]) {
      test('shows only every n-th tick that fits, but always the first: $fit', () {
        final ticks = [
          for (var i = 0; i < 10; i++) TickItem(value: fit.contains(i) ? 10 : 1000, coordinate: i * 50.0, index: i),
        ];
        // The first tick sits on the axis start, so its label moves inwards by half its size.
        expect(shape(getEquidistantTicks(1, (start: 0, end: 500), sizeOf, ticks, 0)), [
          for (final i in shown) (ticks[i].value, ticks[i].coordinate, i == 0 ? sizeOf(ticks[0], 0) / 2 : null),
        ]);
      });
    }

    test('should move the first tick label inwards when it overflows the start boundary', () {
      final ticks = [for (var i = 0; i < 10; i++) TickItem(value: i, coordinate: i * 50.0, index: i)];
      final result = getEquidistantTicks(1, (start: 0, end: 500), (_, _) => 100, ticks, 20);
      expect(result.first.coordinate, 0);
      expect(result.first.tickCoord, 50);
      expect([for (final t in result) t.value], [0, 4, 8]);
    });

    test('preserveEnd skips ticks to satisfy minTickGap while preserving the end tick', () {
      final ticks = [
        for (final (i, v) in ['A', 'B', 'C', 'D', 'E'].indexed) TickItem(value: v, coordinate: i * 10.0, index: i),
      ];
      final result = getEquidistantPreserveEndTicks(1, (start: 0, end: 100), (_, _) => 10, ticks, 8);
      expect([for (final t in result) t.value], ['A', 'C', 'E']);
    });

    test('preserveEnd moves the end tick inwards instead of dropping every other tick', () {
      final ticks = [for (var i = 0; i < 10; i++) TickItem(value: i, coordinate: (i + 1) * 50.0, index: i)];
      final result = getEquidistantPreserveEndTicks(1, (start: 0, end: 500), (_, _) => 100, ticks, 20);
      expect([for (final t in result) t.value], [1, 5, 9]);
      expect(result.last.coordinate, 500);
      expect(result.last.tickCoord, 450);
      // The input ticks are not touched.
      expect(ticks.last.tickCoord, isNull);
    });
  });

  group('Tooltip.animation.spec.tsx: active index and position', () {
    // LineChart 100x100, data [{A,1},{B,2}], tooltip box mocked to 10x10.
    final m = model('LineChart', 100, 100, const [
      {'name': 'A', 'value': 1},
      {'name': 'B', 'value': 2},
    ], const [
      Line(dataKey: 'value'),
      Tooltip(),
    ]);

    Offset? translate(Offset pointer) {
      final props = activePropsFromPointer(m, pointer)!;
      return getTooltipTranslate(
        allowEscapeViewBox: (x: false, y: false),
        coordinate: props.activeCoordinate,
        offset: 10,
        reverseDirection: (x: false, y: false),
        tooltipBox: const Size(10, 10),
        viewBox: m.viewBox,
      );
    }

    test('first hover at (20, 20)', () {
      final props = activePropsFromPointer(m, const Offset(20, 20))!;
      expect(props.activeIndex, 0);
      expect(props.activeCoordinate, const Offset(5, 20));
      expect(translate(const Offset(20, 20)), const Offset(15, 30));
    });

    test('flips when overflowing the view box at (80, 80)', () {
      expect(activePropsFromPointer(m, const Offset(80, 80))!.activeIndex, 1);
      expect(translate(const Offset(80, 80)), const Offset(75, 60));
    });

    test('outside the plot area there is no active index', () {
      expect(activePropsFromPointer(m, const Offset(2, 50)), isNull);
    });
  });

  group('cursor geometry (getCursorRectangle / getCursorPoints)', () {
    test('BarChart cursor is the band', () {
      final m = model('BarChart', 100, 50, barData, const [Bar(dataKey: 'uv'), Tooltip()]);
      final props = activePropsFromPointer(m, const Offset(30, 20))!;
      expect(props.activeIndex, 1);
      expect(props.activeCoordinate, const Offset(38.75, 20));
      expect(cursorRectangle(m.layout, props.activeCoordinate, m.offset, m.tooltipAxisBandSize),
          const Rect.fromLTWH(27.5, 5.5, 22.5, 39));
    });

    test('LineChart cursor is a vertical line', () {
      final m = model('LineChart', 100, 100, pageData, const [Line(dataKey: 'uv'), Tooltip()]);
      final props = activePropsFromPointer(m, const Offset(25, 40))!;
      expect(props.activeIndex, 1);
      expect(cursorPoints(m.layout, props.activeCoordinate, m.offset), const [Offset(23, 5), Offset(23, 95)]);
    });
  });

  group('Bar.theme.spec.tsx without a theme: the tooltip shows the color the bar renders with', () {
    const gold = Color(0xFFFFD700), red = Color(0xFFFF0000), silver = Color(0xFFC0C0C0), blue = Color(0xFF0000FF);
    (Color?, Color?, Color?) colors(List<Object?> data, Bar bar, int index) {
      final e = tooltipPayloadOf(model('BarChart', 400, 400, data, [bar]), index).single;
      return (e.color, e.fill, e.stroke);
    }

    test('per-datum colors: the datum fill, else the datum stroke', () {
      const data = [
        {'name': 'Sun', 'massKg': 1, 'fill': 'gold', 'stroke': 'red'},
        {'name': 'Mercury', 'massKg': 2, 'fill': 'silver'},
        {'name': 'Venus', 'massKg': 3, 'stroke': 'blue'},
      ];
      const bar = Bar(dataKey: 'massKg');
      expect(colors(data, bar, 0), (gold, gold, red));
      expect(colors(data, bar, 1), (silver, silver, null));
      expect(colors(data, bar, 2), (blue, null, blue));
    });

    test('shows the Bar fill in the tooltip when the entry only has a stroke', () {
      const lime = Color(0xFF00FF00), fill = Color(0xFF123456);
      expect(colors(const [{'uv': 1, 'stroke': 'lime'}], const Bar(dataKey: 'uv', fill: fill), 0), (fill, fill, lime));
    });

    test('uses the Bar stroke when there is no fill', () {
      expect(colors(const [{'uv': 1}], const Bar(dataKey: 'uv', stroke: red), 0), (red, null, red));
    });

    test('ignores the entry color key, because it does not paint the bar', () {
      expect(colors(const [{'uv': 1, 'color': 'blue'}], const Bar(dataKey: 'uv', fill: red), 0), (red, red, null));
    });
  });

  group('tooltip payload (combineTooltipPayload)', () {
    test('one entry per item with name, value and color', () {
      final m = model('LineChart', 400, 400, pageData, const [
        XAxis(dataKey: 'name'),
        Line(dataKey: 'uv', stroke: Color(0xFF82CA9D)),
        Line(dataKey: 'pv', name: 'Page views'),
      ]);
      final payload = tooltipPayloadOf(m, 2);
      expect(activeLabelOf(m, 2), 'Page C');
      expect([for (final p in payload) (p.name, p.value, p.color)], const [
        ('uv', 300, Color(0xFF82CA9D)),
        ('Page views', 1398, Color(0xFF3182BD)),
      ]);
    });
  });

  group('Tooltip.multipleDataArrays.spec.tsx: when a series has no point at the hovered label', () {
    // 'label: tooltip rows, active dots' where the pointer at (x, 100) lands
    List<String> hover(CartesianModel m, List<double> xs) => [
          for (final x in xs)
            () {
              final i = activePropsFromPointer(m, Offset(x, 100))!.activeIndex;
              final payload = tooltipPayloadOf(m, i);
              final rows = [for (final e in payload) if (e.value != null) '${e.name} : ${e.value}'];
              return '${activeLabelOf(m, i)}: ${rows.join(', ')}, ${{for (final e in payload) ?e.payload}.length} dots';
            }(),
        ];

    test('leaves the series out of the tooltip and draws no active dot for it on a number axis', () {
      final m = model('ComposedChart', 500, 300, const [], [
        const XAxis(dataKey: 'x', type: AxisDomainType.number),
        const YAxis(),
        Line(dataKey: 'value', name: 'A', data: [for (final x in [0, 1, 2, 3, 4, 5]) {'x': x, 'value': x + 1}]),
        Line(dataKey: 'value', name: 'B', data: [for (final x in [3, 4, 5]) {'x': x, 'value': x + 2}]),
      ]);
      expect(hover(m, [65, 118.75, 172.5, 226.25]), [
        '0: A : 1, 1 dots',
        '1: A : 2, 1 dots',
        '2: A : 3, 1 dots',
        '3: A : 4, B : 5, 2 dots',
      ]);
    });

    test('leaves the series out of the tooltip on a category axis with allowDuplicatedCategory=false', () {
      final m = model('ComposedChart', 500, 300, const [], const [
        XAxis(dataKey: 'name', allowDuplicatedCategory: false),
        YAxis(),
        Line(dataKey: 'value', name: 'A', data: [
          {'name': 'a', 'value': 1},
          {'name': 'b', 'value': 2},
          {'name': 'c', 'value': 3},
          {'name': 'd', 'value': 4},
        ]),
        Line(dataKey: 'value', name: 'B', data: [
          {'name': 'c', 'value': 10},
          {'name': 'd', 'value': 20},
        ]),
      ]);
      expect(hover(m, [118.75, 333.75]), [
        'a: A : 1, 1 dots',
        'c: A : 3, B : 10, 2 dots',
      ]);
    });
  });
}

class _MoveCounter implements PathSink {
  int moves = 0;
  @override
  void moveTo(double x, double y) => moves++;
  @override
  void lineTo(double x, double y) {}
  @override
  void bezierCurveTo(double x1, double y1, double x2, double y2, double x, double y) {}
  @override
  void closePath() {}
}
