// Coordinates ported from Recharts 3.10.1 specs. Those specs run in jsdom where
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
}
