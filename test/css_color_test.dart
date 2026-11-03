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
      expect(cssColorOf('none'), const Color(0x00000000));
      expect(cssColorOf(red), red);
      expect(cssColorOf(3), isNull);
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
      expect(s[1].fill, const Color(0x00000000));
      expect(pieLegendEntries(m.pies.single).map((e) => e.color), [const Color(0xFF008000), const Color(0x00000000)]);
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
  });
}
