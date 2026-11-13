// zIndex layering of polar charts: RadialBar.spec.tsx "RadialBar background
// zIndex" (background behind its sectors unless its zIndex puts it in front;
// 0 draws it inline in the bar's layer) and the zIndex prop of RadialBar,
// Radar and PolarGrid (src/zIndex/ZIndexLayer.tsx, AllZIndexPortals).

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/recharts_flutter.dart';

import '../widgets/chart_widget_test.dart' show capture, host, pixel;

const _red = Color(0xFFFF0000);
const _green = Color(0xFF00FF00);

/// The color in the middle of the opaque run on the vertical line above the
/// chart center: the sector and its background cover the same ring there.
Future<Color> ringColor(WidgetTester tester, Widget chart) async {
  await tester.pumpWidget(host(chart));
  final image = await capture(tester);
  final run = <int>[];
  for (var y = 1; y < 100; y++) {
    if ((await pixel(tester, image, Offset(100, y.toDouble()))).a == 1) run.add(y);
  }
  expect(run, isNotEmpty);
  return pixel(tester, image, Offset(100, run[run.length ~/ 2].toDouble()));
}

Widget radialBar({Object background = false, int zIndex = 300}) => RadialBarChart(
      width: 200,
      height: 200,
      data: const [
        {'v': 10},
      ],
      children: [
        RadialBar(dataKey: 'v', fill: _red, background: background, zIndex: zIndex, isAnimationActive: false),
      ],
    );

void main() {
  group('RadialBar background zIndex', () {
    testWidgets('default zIndex: background behind the sectors', (tester) async {
      expect(await ringColor(tester, radialBar(background: const SectorStyle(fill: _green))), _red);
    });
    testWidgets('custom zIndex above the bar layer: background in front', (tester) async {
      expect(await ringColor(tester, radialBar(background: const SectorStyle(fill: _green, zIndex: 301))), _green);
    });
    testWidgets('zIndex 0: inline in the bar layer, still behind its sectors', (tester) async {
      expect(await ringColor(tester, radialBar(background: const SectorStyle(fill: _green, zIndex: 0))), _red);
    });
    testWidgets('negative zIndex: behind', (tester) async {
      expect(await ringColor(tester, radialBar(background: const SectorStyle(fill: _green, zIndex: -150))), _red);
    });
    testWidgets('a RadialBar zIndex below barBackground puts the sectors under the background', (tester) async {
      expect(await ringColor(tester, radialBar(background: const SectorStyle(fill: _green), zIndex: -200)), _green);
    });
    testWidgets('RadialBar and background both at 0: background first, as inline content', (tester) async {
      expect(await ringColor(tester, radialBar(background: const SectorStyle(fill: _green, zIndex: 0), zIndex: 0)), _red);
    });
  });

  testWidgets('PolarGrid zIndex above the Radar layer paints the grid fill over the polygon', (tester) async {
    Widget chart(int gridZ) => RadarChart(
          width: 200,
          height: 200,
          data: const [
            {'k': 'a', 'v': 10},
            {'k': 'b', 'v': 10},
            {'k': 'c', 'v': 10},
            {'k': 'd', 'v': 10},
          ],
          children: [
            PolarGrid(fill: _green, stroke: null, gridType: PolarGridType.circle, zIndex: gridZ),
            const Radar(dataKey: 'v', fill: _red, isAnimationActive: false),
          ],
        );
    await tester.pumpWidget(host(chart(-100)));
    expect(await pixel(tester, await capture(tester), const Offset(100, 100)), _red);
    await tester.pumpWidget(host(chart(200)));
    expect(await pixel(tester, await capture(tester), const Offset(100, 100)), _green);
  });
}
