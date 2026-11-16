// Brush layout and data slicing, ported from Recharts 3.11.0-canary.9:
// test/cartesian/Brush.spec.tsx (expectBrush), Brush.stacked.spec.tsx,
// test/cartesian/XAxis/XAxis.brush.spec.tsx, test/state/selectors/brushSelectors.spec.tsx,
// and from 3.11: test/util/getSliced.spec.ts.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/src/components.dart';
import 'package:recharts_flutter/src/engine/model.dart';
import 'package:recharts_flutter/src/util.dart';
import 'package:recharts_flutter/src/widgets/brush.dart';

import 'cartesian_model_test.dart' show model, pageData, zero;

CartesianModel brushModel(String chart, double w, double h, List<Object?> data, List<RechartsElement> children,
        {Margin margin = const Margin.all(5), int start = 0, int? end}) =>
    computeCartesianModel(
        chartName: chart,
        size: Size(w, h),
        data: data,
        children: children,
        margin: margin,
        measureFor: zero,
        dataStartIndex: start,
        dataEndIndex: end);

/// `expectBrush`: x, y, width, height of the background rect.
List<double> brushOf(CartesianModel m, {double dy = 0}) {
  final r = m.brushRect!.translate(0, dy);
  return [r.left, r.top, r.width, r.height];
}

const data14 = [
  {'date': '2023-01-01', 'value': 10, 'name': 'A'},
  {'date': '2023-01-02', 'value': 20, 'name': 'B'},
  {'date': '2023-01-03', 'value': 10, 'name': 'C'},
  {'date': '2023-01-04', 'value': 30, 'name': 'D'},
  {'date': '2023-01-05', 'value': 50, 'name': 'E'},
  {'date': '2023-01-06', 'value': 10, 'name': 'F'},
  {'date': '2023-01-07', 'value': 30, 'name': 'G'},
  {'date': '2023-01-08', 'value': 20, 'name': 'H'},
  {'date': '2023-01-09', 'value': 10, 'name': 'I'},
  {'date': '2023-01-10', 'value': 70, 'name': 'J'},
  {'date': '2023-01-11', 'value': 40, 'name': 'K'},
  {'date': '2023-01-12', 'value': 20, 'name': 'L'},
  {'date': '2023-01-13', 'value': 10, 'name': 'M'},
  {'date': '2023-01-14', 'value': 10, 'name': 'N'},
];

void main() {
  group('selectBrushDimensions', () {
    test('explicit x, y, width, height', () {
      final m = brushModel('BarChart', 400, 100, data14, const [Brush(dataKey: 'value', x: 100, y: 50, width: 400)]);
      expect(brushOf(m), [100, 50, 400, 40]);
    });

    test('defaults to the plot area, below the bottom offset', () {
      final m = brushModel('BarChart', 500, 100, data14, const [Brush(dataKey: 'date', height: 90)]);
      expect(brushOf(m), [5, 5, 490, 90]);
    });

    test('margin without top/bottom', () {
      final m = brushModel('BarChart', 500, 100, data14, const [Brush(height: 90)],
          margin: const Margin(right: 100, left: 100));
      expect(brushOf(m), [100, 10, 300, 90]);
    });

    test('stacked BarChart', () {
      final m = brushModel(
          'BarChart', 500, 300, pageData, const [Bar(dataKey: 'pv', stackId: 'a'), Bar(dataKey: 'uv', stackId: 'a'), Brush()]);
      expect(brushOf(m), [5, 255, 490, 40]);
    });

    test('panorama integration margins', () {
      final m = brushModel('ComposedChart', 200, 100, pageData, const [Brush()],
          margin: const Margin(top: 10, right: 20, left: 30, bottom: 40));
      expect(brushOf(m), [30, 20, 150, 40]);
    });

    test('brush height joins the bottom offset; root viewBox', () {
      final m = brushModel('ComposedChart', 500, 300, pageData, const [Brush()],
          margin: const Margin(top: 11, right: 22, left: 33, bottom: 44));
      expect(brushOf(m), [33, 216, 445, 40]);
      expect(m.viewBox, const Rect.fromLTWH(33, 11, 445, 205));
      expect(computeCartesianModel(chartName: 'BarChart', size: const Size(100, 100), data: const [], children: const [
        Brush(height: 7),
      ], measureFor: zero).offset.bottom, 5 + 7);
    });

    test('dy is added to the given and to the computed y', () {
      final a = brushModel('BarChart', 400, 100, data14, const [Brush(x: 100, y: 50, dy: 30, width: 400)]);
      expect(brushOf(a, dy: 30), [100, 80, 400, 40]);
      final b = brushModel('BarChart', 400, 100, data14, const [Brush(x: 100, dy: 30, width: 400)],
          margin: const Margin());
      expect(brushOf(b, dy: 30), [100, 90, 400, 40]);
    });

    test('the brush sits under the X axis and above a bottom legend', () {
      final m = brushModel('LineChart', 500, 300, pageData, const [XAxis(dataKey: 'name'), Brush()]);
      // offset.bottom = 5 + 30 (axis) + 40 (brush)
      expect(m.offset.bottom, 75);
      expect(m.axes.single.rect.top, 225);
      expect(brushOf(m), [5, 255, 490, 40]);
    });
  });

  group('XAxis.brush.spec.tsx: data slice', () {
    const data = [
      {'x': 90, 'y': 90, 'z': 90},
      {'x': 100, 'y': 200, 'z': 200},
      {'x': 120, 'y': 100, 'z': 260},
      {'x': 170, 'y': 300, 'z': 400},
      {'x': 140, 'y': 250, 'z': 280},
      {'x': 150, 'y': 400, 'z': 500},
      {'x': 110, 'y': 280, 'z': 200},
    ];
    const children = [XAxis(dataKey: 'x'), Brush()];

    test('full range', () {
      final m = brushModel('BarChart', 300, 300, data, children);
      final ticks = m.axes.single.ticks;
      expect([for (final t in ticks) t.value], [90, 100, 120, 170, 140, 150, 110]);
      expect([for (final t in ticks) round4(t.coordinate)], [25.7143, 67.1429, 108.5714, 150, 191.4286, 232.8571, 274.2857]);
    });

    test('startIndex 1, endIndex 4', () {
      final m = brushModel('BarChart', 300, 300, data, children, start: 1, end: 4);
      final axis = m.axes.single;
      expect(axis.runtime.domain, [100, 120, 170, 140]);
      expect([for (final t in axis.ticks) t.coordinate], [41.25, 113.75, 186.25, 258.75]);
      expect([for (final t in axis.ticks) t.offset], everyElement(36.25));
      // tick label y: 300 - 75 + tickSize 6 + tickMargin 2
      expect(axis.rect.top + 8, 233);
    });
  });

  group('Brush.stacked.spec.tsx', () {
    const children = [Bar(dataKey: 'pv', stackId: 'a'), Bar(dataKey: 'uv', stackId: 'a'), Brush(dataKey: 'name')];

    test('stacked data covers all points; bars use the slice', () {
      final m = brushModel('BarChart', 500, 300, pageData, children, start: 3, end: 5);
      // 3 bars per series, for pages D, E, F
      expect(m.series.map((s) => s.rects!.length), [3, 3]);
      expect([for (final r in m.series[1].rects!) r.value], [
        [9800, 10000],
        [3908, 4186],
        [4800, 4989],
      ]);
    });

    test('the numeric domain follows the slice', () {
      final full = brushModel('BarChart', 500, 300, pageData, [...children, const YAxis()]);
      final sliced = brushModel('BarChart', 500, 300, pageData, [...children, const YAxis()], start: 4, end: 5);
      expect(full.axes.single.runtime.domain, [0, 10000]);
      // stacks of pages E and F only: max(4186, 4989)
      expect(sliced.axes.single.runtime.domain, [0, 4989]);
    });

    test('Brush.spec.tsx: the selection of the first data point only gives the axis domain of that point', () {
      const data = [
        {'value': 10},
        {'value': 200},
        {'value': 300},
        {'value': 400},
      ];
      final m = brushModel('BarChart', 400, 300, data, const [YAxis(), Bar(dataKey: 'value', stackId: 'stack'), Brush()],
          start: 0, end: 0);
      expect([for (final t in m.axes.single.ticks) (t.value, t.coordinate)], [
        (0, 255),
        (3, 192.5),
        (6, 130),
        (9, 67.5),
        (12, 5),
      ]);
    });

    test('a chart whose items bring their own data keeps all of it in the stack domain and the tooltip', () {
      final m = brushModel('AreaChart', 400, 300, const [], end: 0, const [
        YAxis(),
        Area(dataKey: 'v', stackId: 's', data: [
          {'v': 1},
          {'v': 5},
        ]),
      ]);
      expect(m.axes.single.runtime.domain, [0, 5]);
      expect(tooltipPayloadOf(m, 1).single.value, 5);
    });
  });

  group('getSliced.spec.ts', () {
    const array = ['a', 'b', 'c', 'd'];
    test('the elements between the two indexes, inclusive on both ends', () {
      expect(getSliced(array, 1, 2), ['b', 'c']);
      expect(getSliced(array, 2, 2), ['c']);
      expect(getSliced(array, 0, 0), ['a']);
      expect(getSliced(array, 0, array.length - 1), array);
      expect(getSliced(array, 2, 1), isEmpty);
    });

    test('getBrushSliceIndexes: the whole range without chart data', () {
      final (start, end) = getBrushSliceIndexes(const [], 0, 0);
      expect(getSliced(array, start, end), array);
      expect(getBrushSliceIndexes(array, 0, 0), (0, 0));
    });
  });

  group('line points and tooltip use the slice', () {
    test('LineChart', () {
      final m = brushModel('LineChart', 400, 100, data14, const [Line(dataKey: 'value'), Brush()], start: 6);
      expect(m.series.single.points!.length, 8);
      expect(identical(m.series.single.points!.first.payload, data14[6]), isTrue);
      expect(tooltipPayloadOf(m, 0).single.value, 30);
      expect(tooltipDisplayedData(m).length, 8);
    });

    test('model without brush renders all data', () {
      final m = model('LineChart', 400, 100, data14, const [Line(dataKey: 'value')]);
      expect(m.series.single.points!.length, 14);
      expect(m.brushRect, isNull);
    });
  });

  group('panorama model', () {
    test('viewBox is the brush minus padding; Y range ignores axis padding', () {
      final m = computeCartesianModel(
        chartName: 'ComposedChart',
        size: const Size(445, 40),
        data: pageData,
        children: const [YAxis(padding: AxisPadding(top: 20)), Line(dataKey: 'uv')],
        margin: const Margin.all(1),
        measureFor: zero,
        panorama: true,
      );
      expect(m.viewBox, const Rect.fromLTWH(1, 1, 443, 38));
      expect(m.axes, isEmpty);
      final y = m.series.single.points!.first.y!;
      // uv 400 is the max of [0, 400] -> top of the range [39, 1]
      expect(y, 1);
    });
  });

  test('panorama CartesianGrid reads the main chart offset and size', () {
    final main = brushModel('LineChart', 500, 300, pageData, const [Brush()]);
    final m = computeCartesianModel(
      chartName: 'LineChart',
      size: main.brushRect!.size,
      data: pageData,
      children: const [CartesianGrid(), Line(dataKey: 'uv')],
      margin: const Margin.all(1),
      measureFor: zero,
      panorama: true,
      rootOffset: main.offset,
      rootSize: main.size,
    );
    expect(m.grid!.rect, main.viewBox);
    // getCoordinatesOfGrid adds the main offset bounds to the panorama ticks
    expect(m.grid!.verticalPoints, containsAll([main.offset.left, main.offset.left + main.offset.width]));
  });

  group('Brush.tsx getIndex', () {
    // scalePoint over 14 indexes on [100, 495]
    final values = [for (var i = 0; i < 14; i++) 100 + i * 395 / 13];

    test('getIndexInRange returns the last value <= x', () {
      expect(getIndexInRange(values, 100), 0);
      expect(getIndexInRange(values, 300), 6);
      expect(getIndexInRange(values, 495), 13);
      expect(getIndexInRange(values, 50), 0);
    });

    test('gap rounds both ends down, except the last index', () {
      expect(getBrushIndex(startX: 300, endX: 495, scaleValues: values, gap: 1, dataLength: 14),
          (startIndex: 6, endIndex: 13));
      expect(getBrushIndex(startX: 495, endX: 300, scaleValues: values, gap: 1, dataLength: 14),
          (startIndex: 6, endIndex: 13));
      expect(getBrushIndex(startX: 300, endX: 420, scaleValues: values, gap: 4, dataLength: 14),
          (startIndex: 4, endIndex: 8));
      expect(getBrushIndex(startX: 300, endX: 495, scaleValues: values, gap: 4, dataLength: 14),
          (startIndex: 4, endIndex: 13));
    });
  });
}
