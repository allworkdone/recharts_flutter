// animationBegin follows AnimationHandle.ts: INIT -> PENDING on the frame that
// mounts the item, PENDING -> ACTIVE (progress 0) on the first later frame at
// least `animationBegin` ms after it.

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/recharts_flutter.dart';

void main() {
  testWidgets('progress 0 is the first frame animationBegin ms after mount', (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          child: BarChart(width: 100, height: 50, data: [
            {'uv': 400},
            {'uv': 300},
          ], children: [
            Bar(dataKey: 'uv', fill: Color(0xFF0000FF), animationBegin: 160, animationEasing: 'linear'),
          ]),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 150)); // still PENDING
    await tester.pump(const Duration(milliseconds: 10)); // 160 ms after mount: ACTIVE, progress 0
    await tester.pump(const Duration(milliseconds: 150));
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
    final image = (await tester.runAsync(() => boundary.toImage()))!;
    final bytes = (await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
    int alphaAt(int x, int y) => bytes.getUint8((y * image.width + x) * 4 + 3);
    // Final first bar: y 5..45; 150 of 400 ms grow it to 40 * 0.375 = 15 (top 30).
    expect(alphaAt(20, 31), 255);
    expect(alphaAt(20, 29), 0);
  });
}
