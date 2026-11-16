// Symbol dots and their legend icons, ported from Recharts
// test/component/Legend/Legend.dotSymbol.spec.tsx and
// test/component/Dots.symbols.spec.tsx (canary.9): `dot` / `activeDot` take a
// symbol name or an object with `symbol`, the legend payload carries the
// symbol with the dot colors, Radar and Scatter default their legendType to it.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/recharts_flutter.dart';
import 'package:recharts_flutter/src/engine/model.dart' show collectItems, legendPayloadOf;
import 'package:recharts_flutter/src/engine/polar_scene.dart' show radarLegendEntry;
import 'package:recharts_flutter/src/render/shapes.dart' show legendIconDotColors;
import 'package:recharts_flutter/src/widgets/legend.dart' show DefaultLegendContent;

import 'chart_widget_test.dart' show capture, host, pixel;

const white = Color(0xFFFFFFFF), blue3182 = Color(0xFF3182BD), red = Color(0xFFFF0000);
const gold = Color(0xFFFFD700), black = Color(0xFF000000), blue = Color(0xFF0000FF), grey = Color(0xFFCCCCCC);

LegendPayload legendOf(CartesianSeries item) => legendPayloadOf(collectItems([item]), const Legend()).single;

void main() {
  group('Line', () {
    test('a symbol dot puts the symbol with the dot colors into the legend payload', () {
      final p = legendOf(const Line(dataKey: 'uv', dot: SymbolType.star));
      expect(p.type, LegendType.line);
      // without a theme, Line dots have a white fill and the line stroke
      expect(p.dot, (symbol: SymbolType.star, fill: white, stroke: blue3182));
    });

    test('the colors of the dot object win', () {
      final p = legendOf(const Line(dataKey: 'uv', dot: SvgStyle(symbol: SymbolType.star, fill: gold, stroke: black)));
      expect(p.dot, (symbol: SymbolType.star, fill: gold, stroke: black));
    });

    test('keeps the default line icon without a symbol', () {
      for (final dot in <Object>[true, false, const SvgStyle(r: 6), (Canvas c, DotProps p) {}]) {
        expect(legendOf(Line(dataKey: 'uv', dot: dot)).dot, isNull);
      }
    });

    test('an explicit legendType stays', () {
      expect(legendOf(const Line(dataKey: 'uv', dot: SymbolType.star, legendType: LegendType.square)).type,
          LegendType.square);
    });

    test('a hidden item draws the symbol stroke in the inactive color, the white fill stays', () {
      final p = legendOf(const Line(dataKey: 'uv', dot: SymbolType.star, hide: true));
      expect(legendIconDotColors(p.dot!, p, grey), (fill: white, stroke: grey));
    });
  });

  test('Area: the symbol takes the area fill and stroke, like its dots', () {
    final p = legendOf(const Area(dataKey: 'uv', dot: SymbolType.cross));
    expect(p.dot, (symbol: SymbolType.cross, fill: blue3182, stroke: blue3182));
    expect(legendOf(const Area(dataKey: 'uv')).dot, isNull);
  });

  group('Radar', () {
    test('the legend icon is the dot symbol', () {
      expect(radarLegendEntry(const Radar(dataKey: 'uv', dot: SymbolType.star)).type, LegendType.star);
      expect(radarLegendEntry(const Radar(dataKey: 'uv', dot: SvgStyle(symbol: SymbolType.diamond))).type,
          LegendType.diamond);
    });

    test('with the colors from the dot object', () {
      final p = radarLegendEntry(
          const Radar(dataKey: 'uv', stroke: blue, dot: SvgStyle(symbol: SymbolType.diamond, fill: gold)));
      expect(p.dot, (symbol: SymbolType.diamond, fill: gold, stroke: blue));
    });

    test('keeps the rect icon without a dot symbol, and an explicit legendType', () {
      expect(radarLegendEntry(const Radar(dataKey: 'uv', dot: true)).type, LegendType.rect);
      expect(radarLegendEntry(const Radar(dataKey: 'uv', dot: SymbolType.star, legendType: LegendType.line)).type,
          LegendType.line);
    });
  });

  group('Scatter', () {
    test('the legend icon is the shape symbol, with the fill and stroke of the points', () {
      final p = legendOf(const Scatter(shape: SymbolType.star, fill: red, stroke: black));
      expect(p.type, LegendType.star);
      expect(p.dot, (symbol: SymbolType.star, fill: red, stroke: black));
    });

    test('an explicit legendType wins over the shape', () {
      expect(legendOf(const Scatter(shape: SymbolType.star, legendType: LegendType.square)).type, LegendType.square);
    });

    test('the default and a custom shape keep the circle icon without a dot', () {
      for (final s in [const Scatter(), Scatter(shape: (Canvas c, ScatterShapeProps p) {})]) {
        final p = legendOf(s);
        expect(p.type, LegendType.circle);
        expect(p.dot, isNull);
      }
    });

    test('a hidden stroke-only shape draws its stroke in the inactive color', () {
      final p = legendOf(const Scatter(shape: SymbolType.diamond, fill: cssNone, stroke: blue, hide: true));
      expect(legendIconDotColors(p.dot!, p, grey), (fill: cssNone, stroke: grey));
    });
  });

  // 100x100 without axes: both dots at y 5, x 5 and 95.
  const flat = [
    {'uv': 400},
    {'uv': 400},
  ];

  testWidgets('a symbol dot is the symbol 2r across, a dot object without one a circle', (tester) async {
    Future<Color> corner(Object dot) async {
      await tester.pumpWidget(host(LineChart(width: 100, height: 100, data: flat, children: [
        Line(dataKey: 'uv', dot: dot, isAnimationActive: false),
      ])));
      // inside the 12x12 square around (5, 5), outside the circle of r 6
      return pixel(tester, await capture(tester), const Offset(9, 9));
    }

    expect(await corner(const SvgStyle(symbol: SymbolType.square, r: 6, fill: red)), red);
    expect(await corner(const SvgStyle(r: 6, fill: red)), isNot(red));
  });

  testWidgets('activeDot takes a symbol too', (tester) async {
    await tester.pumpWidget(host(LineChart(width: 100, height: 100, data: flat, children: [
      const Line(
          dataKey: 'uv', dot: false, activeDot: SvgStyle(symbol: SymbolType.square, r: 6, fill: red), isAnimationActive: false),
      Tooltip(defaultIndex: 0, isAnimationActive: false, content: (_) => const SizedBox()),
    ])));
    expect(await pixel(tester, await capture(tester), const Offset(9, 9)), red);
  });

  testWidgets('the line legend icon draws the dot symbol in its middle', (tester) async {
    Future<Color> iconCenter(Object dot) async {
      await tester.pumpWidget(host(LineChart(width: 200, height: 100, data: flat, children: [
        Line(dataKey: 'uv', dot: dot, isAnimationActive: false),
        const Legend(),
      ])));
      final icon = tester.getRect(
          find.descendant(of: find.byType(DefaultLegendContent), matching: find.byType(CustomPaint)).first);
      return pixel(tester, await capture(tester), icon.center);
    }

    // the white fill of the Line dots, where the default icon has a hollow circle
    expect(await iconCenter(SymbolType.square), white);
    expect((await iconCenter(true)).a, 0);
  });
}
