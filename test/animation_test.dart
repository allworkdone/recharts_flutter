import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/recharts_flutter.dart';
import 'package:recharts_flutter/src/animation.dart';
import 'package:recharts_flutter/src/engine/model.dart';

void main() {
  group('useAnimatedLineLength.spec.ts', () {
    test('initial animation interpolates linearly and ends with null', () {
      final l = AnimatedLineLength();
      expect(l.visibleLength(0, 0, 100), 0);
      expect(l.visibleLength(0, 0.1, 100), 10);
      expect(l.visibleLength(0, 0.5, 100), 50);
      expect(l.visibleLength(0, 1, 100), isNull);
    });

    test('continues from the last animated length after a data change', () {
      final l = AnimatedLineLength();
      l.visibleLength(0, 0.5, 100);
      expect(l.visibleLength(1, 0, 200), 50);
      expect(l.visibleLength(1, 0.25, 200), 100);
      expect(l.visibleLength(1, 0.75, 200), isNull);
    });
  });

  group('Line.animation.spec.tsx stroke-dasharray', () {
    test('plain reveal', () => expect(animatedStrokeDasharray(10, 100, null), [10, 100]));
    test('keeps the user dash pattern while growing', () {
      expect(animatedStrokeDasharray(0, 100, [7, 3]), [0, 100]);
      expect(animatedStrokeDasharray(10, 100, [7, 3]), [7, 3, 0, 100]);
      expect(animatedStrokeDasharray(20, 100, [7, 3]), [7, 3, 7, 3, 0, 100]);
      expect(animatedStrokeDasharray(10, 100, [5]), [5, 5, 0, 100]);
    });
  });

  group('matchBy.ts', () {
    test('matchByIndex spreads the previous items over the next ones', () {
      final items = matchAnimationItems<int>([10, 20, 30], [1, 2, 3, 4, 5, 6], MatchBy.byIndex)!;
      expect([for (final i in items) (i as Matched<int>).prev], [10, 10, 20, 20, 30, 30]);
    });

    test('matchAppend pairs by position and adds the rest', () {
      final items = matchAnimationItems<int>([10, 20], [1, 2, 3], MatchBy.append)!;
      expect(items[0], isA<Matched<int>>());
      expect(items[2], isA<Added<int>>());
    });

    test('bars enter growing from stackedBarStart', () {
      final next = BarRect(
          x: 10, y: 5, width: 18, height: 40, value: 1, payload: null, background: null, stackedBarStart: 45,
          originalDataIndex: 0);
      final step = interpolateBarRects([Added(next)], 0.5, ChartLayout.horizontal).single;
      expect((step.y, step.height), (25.0, 20.0));
    });
  });

  testWidgets("bar entrance follows 400ms 'ease' (JavascriptAnimate timing)", (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          child: BarChart(width: 100, height: 50, data: [
            {'uv': 400},
            {'uv': 300},
          ], children: [
            Bar(dataKey: 'uv', fill: Color(0xFF0000FF)),
          ]),
        ),
      ),
    ));
    // First frame after mount is where Recharts reaches progress 0 (INIT -> PENDING -> ACTIVE).
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 150));
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
    final image = (await tester.runAsync(() => boundary.toImage()))!;
    final bytes = (await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
    int alphaAt(int x, int y) => bytes.getUint8((y * image.width + x) * 4 + 3);
    // Final first bar: y 5..45 at x ~ 9.5..38. Height grows as 40 * ease(0.375).
    final top = 45 - 40 * createEasingFunction('ease')!(0.375);
    expect(alphaAt(20, top.ceil() + 1), 255);
    expect(alphaAt(20, top.floor() - 1), 0);
  });
}
