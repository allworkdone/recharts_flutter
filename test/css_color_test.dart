// parseCssColor, and a CSS color string as the `fill` / `stroke` of a data
// entry or a Cell in every chart family that reads one.

import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/recharts_flutter.dart';
import 'package:recharts_flutter/src/css_color.dart';
import 'package:recharts_flutter/src/engine/pie.dart';
import 'package:recharts_flutter/src/sunburst.dart';

import 'engine/funnel_model_test.dart' show trapezoids;
import 'polar/polar_chart_ports_test.dart' show radialBarModel;
import 'widgets/chart_widget_test.dart' show capture, host, pixel;
import 'widgets/tooltip_item_test.dart' show Probe, mouseAt;

const red = Color(0xFFFF0000);

void main() {
  group('parseCssColor', () {
    test('hex forms', () {
      expect(parseCssColor('#f00'), red);
      expect(parseCssColor('#f008'), const Color(0x88FF0000));
      expect(parseCssColor('#FF0000'), red);
      expect(parseCssColor('#ff000080'), const Color(0x80FF0000));
      expect(parseCssColor('#ff'), isNull);
      expect(parseCssColor('#gg0000'), isNull);
    });

    test('rgb and rgba, commas or spaces, percentages and alpha', () {
      expect(parseCssColor('rgb(255, 0, 0)'), red);
      expect(parseCssColor('rgb(255 0 0)'), red);
      expect(parseCssColor('rgba(255,0,0,0.5)'), const Color(0x80FF0000));
      expect(parseCssColor('rgb(255 0 0 / 50%)'), const Color(0x80FF0000));
      expect(parseCssColor('rgb(100%, 0%, 0%)'), red);
      expect(parseCssColor('rgb(300, -4, 0)'), red);
      expect(parseCssColor('rgb(1, 2)'), isNull);
    });

    test('hsl and hsla', () {
      expect(parseCssColor('hsl(0, 100%, 50%)'), red);
      expect(parseCssColor('hsl(120 100% 25%)'), const Color(0xFF008000));
      expect(parseCssColor('hsl(240deg, 100%, 50%)'), const Color(0xFF0000FF));
      expect(parseCssColor('hsl(0.5turn 100% 50%)'), const Color(0xFF00FFFF));
      expect(parseCssColor('hsla(0, 100%, 50%, 0.5)'), const Color(0x80FF0000));
      expect(parseCssColor('hsl(-120, 100%, 50%)'), const Color(0xFF0000FF));
      expect(parseCssColor('hsl(0, 0%, 100%)'), const Color(0xFFFFFFFF));
    });

    test('named colors, case and whitespace; none and transparent', () {
      expect(parseCssColor(' Red '), red);
      expect(parseCssColor('rebeccapurple'), const Color(0xFF663399));
      expect(parseCssColor('lightgoldenrodyellow'), const Color(0xFFFAFAD2));
      expect(parseCssColor('grey'), parseCssColor('gray'));
      expect(parseCssColor('transparent'), const Color(0x00000000));
      expect(parseCssColor('none'), isNull);
      expect(parseCssColor('not-a-color'), isNull);
      expect(isCssNone(cssFillOf('none')), isTrue);
      expect(cssFillOf('none'), isNot(parseCssColor('transparent')));
      expect(cssFillOf(red), red);
      expect(cssFillOf(3), isNull);
      expect(textColorOf(cssNone), isNull);
      expect(textColorOf(red), red);
    });

    test('an invalid string: black fill, no stroke, never the fallback', () {
      expect(cssFillOf('not-a-color'), const Color(0xFF000000));
      expect(isCssNone(cssStrokeOf('not-a-color')), isTrue);
      expect(cssFillOf(null), isNull);
      expect(cssStrokeOf(null), isNull);
    });

    test('grammar Chrome rejects', () {
      for (final bad in [
        'rgb(255, 0 0)', 'rgb(255 0 0 0.5)', 'rgb(255, 0, 0 / 0.5)', 'rgb(100%, 0, 0)', 'rgb(5., 0, 0)', 'rgb(1, 2)',
        'rgb(255 0 0 /)', 'rgb(none, 0, 0)', 'hsl(120, 100, 50)', 'hsl(0, 100%, 50%, 0.5, 1)', 'rgb(255,0,0)x', '# fff',
        'hwb(0 0% 0%)', 'oklch(0.6 0.2 30)', 'rgb(NaN, 0, 0)', 'rgb(Infinity, 0, 0)',
      ]) {
        expect(parseCssColor(bad), isNull, reason: bad);
      }
    });

    test('grammar Chrome accepts', () {
      expect(parseCssColor('rgb(none 0 0)'), const Color(0xFF000000));
      expect(parseCssColor('rgb(255 0 0 / 50%)'), const Color(0x80FF0000));
      expect(parseCssColor('rgba(255,0,0)'), red);
      expect(parseCssColor('rgb(255,0,0,0.5)'), const Color(0x80FF0000));
      expect(parseCssColor('rgb(1e2, 0, 0)'), const Color(0xFF640000));
      expect(parseCssColor('rgb(50%, 0%, 0%)'), const Color(0xFF800000));
      expect(parseCssColor('hsl(120 100 25)'), const Color(0xFF008000));
      expect(parseCssColor('hsl(none 100% 50%)'), red);
      expect(parseCssColor('hsl(200grad 100% 50%)'), parseCssColor('hsl(180 100% 50%)'));
      expect(parseCssColor('HSL(120DEG 100% 50%)'), const Color(0xFF00FF00));
      expect(parseCssColor('currentColor'), const Color(0xFF000000));
    });
  });

  group('a string fill in data entries', () {
    test('Pie: entry fill and stroke, Cell.css, legend', () {
      final m = computePolarModel(chartName: 'PieChart', size: const Size(200, 200), data: const [], children: [
        Pie(data: const [
          {'name': 'a', 'value': 1, 'fill': 'rgb(0, 128, 0)', 'stroke': '#00f'},
          {'name': 'b', 'value': 1, 'fill': 'none'},
        ], dataKey: 'value', id: 'p'),
      ]);
      final s = m.pies.single.sectors!;
      expect(s[0].fill, const Color(0xFF008000));
      expect(s[0].stroke, const Color(0xFF0000FF));
      expect(isCssNone(s[1].fill), isTrue);
      expect(pieLegendEntries(m.pies.single).map((e) => isCssNone(e.color)), [false, true]);
      expect(Cell.css(fill: 'red', stroke: 'blue').fill, red);
    });

    test('Funnel: entry fill and Cell.css', () {
      final t = trapezoids(
          Funnel(dataKey: 'value', data: const [
            {'name': 'a', 'value': 2, 'fill': 'red'},
            {'name': 'b', 'value': 1, 'stroke': 'hsl(240, 100%, 50%)'},
          ], children: [
            Cell.css(),
            Cell.css(fill: 'lime'),
          ]));
      expect(t[0].fill, red);
      expect(t[1].fill, const Color(0xFF00FF00));
      expect(t[1].stroke, const Color(0xFF0000FF));
    });

    test('RadialBar: entry fill and stroke', () {
      final m = radialBarModel(const [
        {'name': 'a', 'v': 3, 'fill': 'red', 'stroke': '#00ff00'},
      ], const [
        RadialBar(isAnimationActive: false, dataKey: 'v'),
      ]);
      final s = m.scene!.radialBars.single.sectors.single;
      expect(s.fill, red);
      expect(s.stroke, const Color(0xFF00FF00));
    });

    test('Sunburst: node fill is inherited by children', () {
      final l = computeSunburst(
        data: {
          'name': 'Root',
          'value': 3,
          'children': [
            {
              'name': 'a',
              'value': 2,
              'fill': 'red',
              'children': [
                {'name': 'a1', 'value': 1}
              ]
            },
          ],
        },
        width: 300,
        height: 300,
        dataKey: 'value',
        padding: 2,
        ringPadding: 2,
        innerRadius: 50,
        startAngle: 0,
        endAngle: 360,
        fill: const Color(0xFF333333),
      );
      expect([for (final s in l.sectors) s.fill], [red, red]);
    });

    testWidgets('Treemap: node fill and stroke', (tester) async {
      await tester.pumpWidget(host(const Treemap(
        width: 100,
        height: 100,
        isAnimationActive: false,
        dataKey: 'value',
        data: [
          {'name': 'a', 'value': 1, 'fill': 'rgb(255 0 0)', 'stroke': 'blue'},
        ],
      )));
      final image = await capture(tester);
      expect(await pixel(tester, image, const Offset(50, 50)), red);
      expect((await pixel(tester, image, const Offset(0, 50))).b, greaterThan(0.4)); // the stroke is centred on the edge
    });

    testWidgets('Sankey: SvgStyle.css node and link', (tester) async {
      await tester.pumpWidget(host(Sankey(
        width: 100,
        height: 100,
        margin: const Margin.all(0),
        data: SankeyData(nodes: const [
          {'name': 'a'},
          {'name': 'b'}
        ], links: [
          SankeyLinkDatum(source: 0, target: 1, value: 1)
        ]),
        node: SvgStyle.css(fill: 'red', fillOpacity: 1),
        link: SvgStyle.css(stroke: 'lime', strokeOpacity: 1),
      )));
      final image = await capture(tester);
      expect(await pixel(tester, image, const Offset(2, 50)), red);
      expect(await pixel(tester, image, const Offset(50, 50)), const Color(0xFF00FF00));
    });

    testWidgets('Scatter: data fill', (tester) async {
      await tester.pumpWidget(host(const ScatterChart(width: 100, height: 100, data: [
        {'x': 1, 'y': 1, 'fill': 'red'},
      ], children: [
        XAxis(dataKey: 'x', hide: true, domain: [0, 2]),
        YAxis(dataKey: 'y', hide: true, domain: [0, 2]),
        Scatter(isAnimationActive: false),
      ])));
      final image = await capture(tester);
      expect(await pixel(tester, image, const Offset(50, 50)), red);
    });

    testWidgets('Bar: data fill and stroke sit between the Cell and the series', (tester) async {
      await tester.pumpWidget(host(const BarChart(width: 100, height: 100, data: [
        {'v': 50, 'fill': '#ff0000', 'stroke': 'blue'},
      ], children: [
        YAxis(hide: true, domain: [0, 100]),
        Bar(dataKey: 'v', fill: Color(0xFF00FF00), strokeWidth: 4, isAnimationActive: false),
      ])));
      final image = await capture(tester);
      expect(await pixel(tester, image, const Offset(50, 80)), red);
    });

    testWidgets('Scatter: data stroke', (tester) async {
      await tester.pumpWidget(host(const ScatterChart(width: 100, height: 100, data: [
        {'x': 1, 'y': 1, 'fill': 'red', 'stroke': 'blue'},
      ], children: [
        XAxis(dataKey: 'x', hide: true, domain: [0, 2]),
        YAxis(dataKey: 'y', hide: true, domain: [0, 2]),
        Scatter(isAnimationActive: false, strokeWidth: 3),
      ])));
      final image = await capture(tester);
      var blue = false;
      for (var x = 40; x <= 60; x++) {
        final c = await pixel(tester, image, Offset(x.toDouble(), 50));
        if (c.b > 0.5 && c.r < 0.5) blue = true;
      }
      expect(blue, isTrue);
    });

    testWidgets("Pie: fill 'none' paints nothing and its interior takes no pointer", (tester) async {
      final probe = Probe();
      await tester.pumpWidget(host(PieChart(width: 200, height: 200, children: [
        const Pie(
            data: [
              {'name': 'a', 'value': 1, 'fill': 'none', 'stroke': 'none'},
            ],
            dataKey: 'value',
            isAnimationActive: false),
        Tooltip(isAnimationActive: false, content: probe.build),
      ])));
      final mouse = await mouseAt(tester, const Offset(100, 60));
      expect(probe.visible, isFalse);
      expect(await pixel(tester, await capture(tester), const Offset(100, 60)), const Color(0x00000000));
      await mouse.removePointer();
    });

    testWidgets('a NaN value renders, hovers and labels without throwing', (tester) async {
      await tester.pumpWidget(host(PieChart(width: 200, height: 200, children: [
        Pie(
            data: const [
              {'name': 'a', 'value': 1},
              {'name': 'b', 'value': double.nan},
            ],
            dataKey: 'value',
            label: true,
            isAnimationActive: false),
        const Tooltip(isAnimationActive: false),
      ])));
      final mouse = await mouseAt(tester, const Offset(100, 60));
      await mouse.moveTo(const Offset(150, 100));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await mouse.removePointer();
    });
  });
}
