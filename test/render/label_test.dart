// Coordinates ported from Recharts 3.10.1 specs: getCartesianPosition.spec.ts,
// YAxis.label.spec.tsx, Bar.spec.tsx ('label'), Line.animation.spec.tsx
// (expectedUvLabels), YAxis.spec.tsx ('dynamically calculated width') and
// cartesianAxisSlice.spec.ts. The chart specs run in jsdom, where text
// measures 0x0 unless getBoundingClientRect is mocked.

import 'dart:ui' show PictureRecorder;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/recharts_flutter.dart';
import 'package:recharts_flutter/src/engine/model.dart';
import 'package:recharts_flutter/src/render/label.dart';
import 'package:recharts_flutter/src/render/painter.dart';
import 'package:recharts_flutter/src/render/svg_text.dart';

CartesianModel model(String chartName, double w, double h, List<Object?> data, List<RechartsElement> children) =>
    computeCartesianModel(
        chartName: chartName, size: Size(w, h), data: data, children: children, measureFor: (_) => (_) => Size.zero);

List<Object?> pos(CartesianLabelPosition p) =>
    [p.x, p.y, p.horizontalAnchor.name, p.verticalAnchor.name, if (p.width != null) p.width, if (p.height != null) p.height];

/// Rect keeps right/bottom, so widths come back with float noise; compare at 1e-9.
List<Object?> r9(List<Object?> v) => [for (final e in v) e is num ? double.parse(e.toStringAsFixed(9)) : e];

/// `[text, x, y, width]` of every label the series' LabelLists render.
List<List<Object?>> labels(CartesianModel m, int series) {
  final s = m.series[series];
  final entries = labelListEntries(s, m.size);
  return [
    for (final list in seriesLabelLists(s.item.element))
      for (var i = 0; i < entries.length; i++)
        if (layoutLabel(labelOfEntry(list, entries[i], i), entries[i].viewBox, parentViewBox: entries[i].parentViewBox)
            case final l?)
          r9([l.text, l.x, l.y, l.width]),
  ];
}

const pageData = [
  {'name': 'Page A', 'uv': 400, 'pv': 2400, 'amt': 2400},
  {'name': 'Page B', 'uv': 300, 'pv': 4567, 'amt': 2400},
  {'name': 'Page C', 'uv': 300, 'pv': 1398, 'amt': 2400},
  {'name': 'Page D', 'uv': 200, 'pv': 9800, 'amt': 2400},
  {'name': 'Page E', 'uv': 278, 'pv': 3908, 'amt': 2400},
  {'name': 'Page F', 'uv': 189, 'pv': 4800, 'amt': 2400},
];

void main() {
  group('getCartesianPosition in a rectangle', () {
    final viewBox = const Rect.fromLTWH(100, 50, 200, 100);
    final cases = {
      LabelPosition.top: [200, 45, 'middle', 'end'],
      LabelPosition.bottom: [200, 155, 'middle', 'start'],
      LabelPosition.left: [95, 100, 'end', 'middle'],
      LabelPosition.right: [305, 100, 'start', 'middle'],
      LabelPosition.insideLeft: [105, 100, 'start', 'middle'],
      LabelPosition.insideRight: [295, 100, 'end', 'middle'],
      LabelPosition.insideBottom: [200, 145, 'middle', 'end'],
      LabelPosition.insideTopLeft: [105, 55, 'start', 'start'],
      LabelPosition.insideTopRight: [295, 55, 'end', 'start'],
      LabelPosition.insideBottomLeft: [105, 145, 'start', 'end'],
      LabelPosition.insideBottomRight: [295, 145, 'end', 'end'],
      LabelPosition.center: [200, 100, 'middle', 'middle'],
      LabelPosition.middle: [200, 100, 'middle', 'middle'],
      LabelPosition.insideEnd: [200, 100, 'middle', 'middle'],
    };
    for (final MapEntry(key: position, value: expected) in cases.entries) {
      test('position "${position.name}"', () => expect(pos(getCartesianPosition(viewBox, position, 5)), expected));
    }
    test('position "insideTop" with offset 0', () {
      expect(pos(getCartesianPosition(viewBox, LabelPosition.insideTop, 0)), [200, 50, 'middle', 'start']);
    });
  });

  test('negative height flips "top" below the box', () {
    expect(pos(getCartesianPosition(const Rect.fromLTWH(100, 150, 200, -100), LabelPosition.top, 5)),
        [200, 155, 'middle', 'start']);
  });

  test('negative width flips "left" to the right of x', () {
    // The spec's trapezoid gives 292.5; a rectangle's middleX is x itself.
    expect(pos(getCartesianPosition(const Rect.fromLTWH(300, 50, -200, 100), LabelPosition.left, 5)),
        [305, 100, 'start', 'middle']);
  });

  group('with parentViewBox', () {
    const viewBox = Rect.fromLTWH(100, 50, 200, 100);
    const parent = Rect.fromLTWH(0, 0, 500, 500);
    test('clamp=true sizes "top" to the space above', () {
      expect(pos(getCartesianPosition(viewBox, LabelPosition.top, 5, parentViewBox: parent, clamp: true)),
          [200, 45, 'middle', 'end', 200, 50]);
    });
    test('clamp=true sizes "insideLeft" to the box', () {
      expect(pos(getCartesianPosition(viewBox, LabelPosition.insideLeft, 5, parentViewBox: parent, clamp: true)),
          [105, 100, 'start', 'middle', 200, 100]);
    });
    test('clamp=false does not size', () {
      expect(pos(getCartesianPosition(viewBox, LabelPosition.top, 5, parentViewBox: parent)), [200, 45, 'middle', 'end']);
    });
  });

  group('YAxis label (YAxis.label.spec.tsx, LineChart instead of AreaChart)', () {
    List<Object?> yLabel(Object label) {
      final m = model('LineChart', 500, 500, pageData, [YAxis(label: label), const Line(dataKey: 'uv')]);
      final a = m.axes.single;
      final l = layoutLabel(parseLabel(a.settings.label)!, a.rect)!;
      return [l.text, l.x, l.y];
    }

    test('string', () => expect(yLabel('Test Label'), ['Test Label', 35, 250]));
    test('number', () => expect(yLabel(123), ['123', 35, 250]));
    test('Label insideLeft, angle -90 (rotate(-90, 10, 250))', () {
      expect(yLabel(const Label(value: 'Test Label', angle: -90, position: LabelPosition.insideLeft)),
          ['Test Label', 10, 250]);
    });
  });

  test('Bar label: center of each bar, wrapping at the bar width', () {
    const data = [
      {'x': 10, 'y': 50, 'width': 20, 'height': 50, 'value': 100, 'label': 'test1'},
      {'x': 50, 'y': 50, 'width': 20, 'height': 50, 'value': 200, 'label': 'test2'},
      {'x': 90, 'y': 50, 'width': 20, 'height': 50, 'value': 300, 'label': 'test3'},
      {'x': 130, 'y': 50, 'width': 20, 'height': 50, 'value': 400, 'label': 'test4'},
      {'x': 170, 'y': 50, 'width': 20, 'height': 50, 'value': 500, 'label': 'test5'},
    ];
    final m = model('BarChart', 500, 500, data, const [Bar(dataKey: 'value', label: true)]);
    expect(labels(m, 0), [
      r9(['100', 53.8, 454.16666666666663, 78]),
      r9(['200', 151.8, 413.33333333333337, 78]),
      r9(['300', 249.8, 372.5, 78]),
      r9(['400', 347.8, 331.6666666666667, 78]),
      r9(['500', 445.8, 290.83333333333337, 78]),
    ]);
    final first = labelOfEntry(const LabelList(), labelListEntries(m.series[0], m.size)[0], 0);
    expect(labelTextStyle(first, const TextStyle()).color, const Color(0xFF808080));
    expect(layoutLabel(first, Rect.zero)!.textAnchor, TextAnchor.middle);
  });

  test('LabelList dataKey and offset on Bar (LabelList.spec.tsx)', () {
    const data = [
      {'x': 100, 'y': '200'},
      {'x': 120, 'y': '100'},
    ];
    final m = model('BarChart', 400, 400, data, const [
      Bar(dataKey: 'y', children: [LabelList(dataKey: 'x', offset: 40, position: LabelPosition.top)]),
    ]);
    final r = m.series[0].rects!;
    expect(labels(m, 0), [
      r9(['100', r[0].x + r[0].width / 2, r[0].y - 40, r[0].width]),
      r9(['120', r[1].x + r[1].width / 2, r[1].y - 40, r[1].width]),
    ]);
  });

  test('Line label: one label at each point (Line.animation.spec.tsx)', () {
    final m = model('LineChart', 100, 100, pageData, const [Line(dataKey: 'uv', label: true)]);
    expect(labels(m, 0), [
      for (final l in [
        ['400', 5, 5, 0],
        ['300', 23, 27.5, 0],
        ['300', 41, 27.5, 0],
        ['200', 59, 50, 0],
        ['278', 77, 32.45, 0],
        ['189', 95, 52.475, 0],
      ])
        r9(l),
    ]);
  });

  test('Line renders LabelList children before its label prop; Bar after', () {
    const child = LabelList(position: LabelPosition.top);
    expect(seriesLabelLists(const Line(dataKey: 'uv', label: true, children: [child])).first, same(child));
    expect(seriesLabelLists(const Bar(dataKey: 'uv', label: true, children: [child])).last, same(child));
  });

  test('updateYAxisWidth stops a <= 1px oscillation (cartesianAxisSlice.spec.ts)', () {
    final w = AutoYAxisWidth(const YAxis(width: 'auto'));
    for (final next in [50.0, 51.0, 50.0]) {
      expect(w.update(next), isTrue);
    }
    expect(w.update(51), isFalse);
    expect(w.width, 50);

    final wide = AutoYAxisWidth(const YAxis(width: 'auto'));
    for (final next in [50.0, 52.0, 50.0, 52.0]) {
      wide.update(next);
    }
    expect(wide.width, 52);
  });

  group('widget', () {
    tearDown(() => debugTextMeasurerOverride = null);

    Widget host(Widget chart) => MediaQuery(
          data: const MediaQueryData(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: DefaultTextStyle(style: const TextStyle(fontSize: 12), child: Align(alignment: Alignment.topLeft, child: chart)),
          ),
        );

    CartesianModel paintedModel(WidgetTester tester) =>
        (tester.widget<CustomPaint>(find.byType(CustomPaint).first).painter! as CartesianPainter).frame.model;

    testWidgets('YAxis width auto: widest tick + tickSize + tickMargin (YAxis.spec.tsx)', (tester) async {
      debugTextMeasurerOverride = (_, _) => const Size(80, 30);
      const data = [
        {'name': 'Page A', 'uv': 400, 'pv': 2400, 'amt': 2400},
        {'name': 'Page B', 'uv': 300, 'pv': 1398, 'amt': 2400},
        {'name': 'Page C', 'uv': 200, 'pv': 9800, 'amt': 2400},
        {'name': 'Page D', 'uv': 278, 'pv': 3908, 'amt': 2400},
        {'name': 'Page E', 'uv': 189, 'pv': 4800, 'amt': 2400},
      ];
      await tester.pumpWidget(host(const BarChart(width: 400, height: 300, data: data, children: [
        YAxis(width: 'auto', ticks: [0, 800, 1600, 2400]),
        Bar(dataKey: 'amt', isAnimationActive: false),
      ])));
      final m = paintedModel(tester);
      expect(m.axes.single.rect.width, 88);
      expect(m.offset.left, 5 + 88);
    });

    // CartesianGrid.tickFontSize.spec.tsx
    testWidgets('CartesianGrid draws fewer vertical lines when a large tick fontSize makes the axis hide ticks',
        (tester) async {
      debugTextMeasurerOverride = (text, style) => Size(text.length * style.fontSize! * 0.6, style.fontSize!);
      final data = [for (var i = 0; i < 40; i++) {'name': 'FontSizeTick ${i + 1}', 'value': (i * 37) % 100}];
      Future<int> verticalLines(Object tick) async {
        await tester.pumpWidget(host(LineChart(width: 700, height: 400, data: data, children: [
          const CartesianGrid(),
          XAxis(dataKey: 'name', tick: tick),
          const YAxis(),
          const Line(dataKey: 'value', isAnimationActive: false),
        ])));
        return paintedModel(tester).grid!.verticalPoints.length;
      }

      final withDefaultFont = await verticalLines(true);
      final withLargeFont = await verticalLines(const TextStyle(fontSize: 30));
      expect(withLargeFont, lessThan(withDefaultFont));
    });

    testWidgets('YAxis width auto recovers after starting from empty data (YAxis.spec.tsx)', (tester) async {
      debugTextMeasurerOverride = (_, _) => const Size(80, 30);
      const data = [
        {'name': 'Page A', 'uv': 400, 'pv': 2400, 'amt': 2400},
        {'name': 'Page B', 'uv': 300, 'pv': 1398, 'amt': 2400},
      ];
      Widget chart(List<Object?> data) => host(BarChart(width: 400, height: 300, data: data, children: const [
            YAxis(width: 'auto', ticks: [0, 800, 1600, 2400]),
            Bar(dataKey: 'amt'),
          ]));
      await tester.pumpWidget(chart(const []));
      await tester.pumpWidget(chart(data));
      // 80 width + 6 tick size + 2 tick margin
      expect(paintedModel(tester).axes.single.rect.width, 88);
    });

    testWidgets('YAxis width auto adds the label width and a 5px gap', (tester) async {
      debugTextMeasurerOverride = (_, _) => const Size(80, 30);
      await tester.pumpWidget(host(const LineChart(width: 400, height: 300, data: pageData, children: [
        YAxis(width: 'auto', label: 'Views'),
        Line(dataKey: 'uv', isAnimationActive: false),
      ])));
      expect(paintedModel(tester).axes.single.rect.width, 80 + 6 + 2 + 80 + 5);
    });

    testWidgets('LabelList stays hidden while the line animates, then shows', (tester) async {
      final seen = <Offset>[];
      await tester.pumpWidget(host(LineChart(width: 100, height: 100, data: pageData, children: [
        Line(dataKey: 'uv', label: LabelList(content: (_, p) => seen.add(Offset(p.x, p.y)))),
      ])));
      await tester.pump(const Duration(milliseconds: 700));
      expect(seen, isEmpty);
      await tester.pumpAndSettle();
      expect(seen.take(6), const [
        Offset(5, 5),
        Offset(23, 27.5),
        Offset(41, 27.5),
        Offset(59, 50),
        Offset(77, 32.45),
        Offset(95, 52.475),
      ]);
    });
  });

  // LabelList.spec.tsx 'in a graphical item clipped by allowDataOverflow'
  group('LabelList in a graphical item clipped by allowDataOverflow', () {
    const data = [
      {'name': 'a', 'value': 50},
      {'name': 'b', 'value': 150},
      {'name': 'c', 'value': 100},
      {'name': 'd', 'value': -20},
      {'name': 'e', 'value': 0},
    ];
    const rangeData = [
      {'name': 'a', 'range': [20, 50]},
      {'name': 'b', 'range': [120, 150]},
      {'name': 'c', 'range': [90, 100]},
      {'name': 'd', 'range': [80, 130]},
      {'name': 'e', 'range': [-40, -10]},
      {'name': 'f', 'range': [100, 120]},
      {'name': 'g', 'range': [-30, 0]},
    ];
    const scatterData = [
      {'x': 1, 'y': 50},
      {'x': 2, 'y': 150},
      {'x': 3, 'y': 100},
      {'x': 4, 'y': -20},
      {'x': 5, 'y': 0},
    ];

    Future<List<Object?>> painted(WidgetTester tester, Widget Function(LabelPainter content) chart) async {
      final values = <Object?>[];
      await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr, child: chart((_, props) => values.add('${props.index}:${props.value}'))));
      return values;
    }

    testWidgets('Line: all labels without allowDataOverflow; outside the domain skipped, the edges kept', (tester) async {
      Widget chart(LabelPainter p, bool overflow) => LineChart(width: 400, height: 400, data: data, children: [
            const XAxis(dataKey: 'name'),
            YAxis(domain: const [0, 100], allowDataOverflow: overflow),
            Line(dataKey: 'value', label: LabelList(content: p), isAnimationActive: false),
          ]);
      expect(await painted(tester, (p) => chart(p, false)), ['0:50', '1:150', '2:100', '3:-20', '4:0']);
      expect(await painted(tester, (p) => chart(p, true)), ['0:50', '2:100', '4:0']);
    });

    testWidgets('Area: outside the domain skipped, the edges kept', (tester) async {
      expect(
          await painted(
              tester,
              (p) => AreaChart(width: 400, height: 400, data: data, children: [
                    const XAxis(dataKey: 'name'),
                    const YAxis(domain: [0, 100], allowDataOverflow: true),
                    Area(dataKey: 'value', label: LabelList(content: p), isAnimationActive: false),
                  ])),
          ['0:50', '2:100', '4:0']);
    });

    testWidgets('Bar: labels of bars outside the domain skipped, also if they touch its edge', (tester) async {
      Widget chart(LabelPainter p, bool overflow) => BarChart(width: 400, height: 400, data: rangeData, children: [
            const XAxis(dataKey: 'name'),
            YAxis(domain: const [0, 100], allowDataOverflow: overflow),
            Bar(dataKey: 'range', label: LabelList(content: p), isAnimationActive: false),
          ]);
      expect(await painted(tester, (p) => chart(p, false)), ['0:50', '1:150', '2:100', '3:130', '4:-10', '5:120', '6:0']);
      expect(await painted(tester, (p) => chart(p, true)), ['0:50', '2:100', '3:130']);
    });

    testWidgets('Scatter: outside the domain skipped, the edges kept, only in the clipped dimension', (tester) async {
      expect(
          await painted(
              tester,
              (p) => ScatterChart(width: 400, height: 400, children: [
                    const XAxis(dataKey: 'x', type: AxisDomainType.number),
                    const YAxis(dataKey: 'y', domain: [0, 100], allowDataOverflow: true),
                    Scatter(data: scatterData, isAnimationActive: false, children: [LabelList(dataKey: 'y', content: p)]),
                  ])),
          ['0:50', '2:100', '4:0']);
      expect(
          await painted(
              tester,
              (p) => ScatterChart(width: 400, height: 400, children: [
                    const XAxis(dataKey: 'x', type: AxisDomainType.number, domain: [2, 4], allowDataOverflow: true),
                    const YAxis(dataKey: 'y'),
                    Scatter(data: scatterData, isAnimationActive: false, children: [LabelList(dataKey: 'x', content: p)]),
                  ])),
          ['1:2', '2:3', '3:4']);
    });
  });

  test('custom content gets the background setting and draws its own (Label.background.spec.tsx)', () {
    final seen = <LabelProps>[];
    const background = TextBackground(fill: Color(0xFFFFD700));
    paintLabel(Canvas(PictureRecorder()), Label(value: 'text', background: background, content: (_, p) => seen.add(p)),
        const Rect.fromLTWH(50, 50, 200, 200),
        baseStyle: const TextStyle(fontSize: 12), scaler: TextScaler.noScaling);
    expect(seen.single.background, same(background));
  });
}
