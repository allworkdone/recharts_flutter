// Touch and DOM mouse handlers of polar items: RadialBar.spec.tsx "calls touch
// handler events", Radar.spec.tsx (onMouseOver / onMouseMove / onMouseOut and
// "should fire onTouchMove and onTouchEnd events when touching the radar
// polygon"), and Pie's sector handlers. Like DOM touch events, touchmove and
// touchend go to the element the touch started on.

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/recharts_flutter.dart';

import '../widgets/chart_widget_test.dart' show host;

const _ring = Offset(100, 60);
const _outside = Offset(3, 3);

void main() {
  testWidgets('RadialBar: touchstart on a sector, touchmove and touchend go to it after the finger leaves', (tester) async {
    final calls = <String>[];
    void log(String name, int index) => calls.add('$name $index');
    await tester.pumpWidget(host(RadialBarChart(width: 200, height: 200, data: const [
      {'v': 10},
    ], children: [
      RadialBar(
        dataKey: 'v',
        isAnimationActive: false,
        onTouchStart: (s, i, e) => log('start', i),
        onTouchMove: (s, i, e) => log('move ${s.value}', i),
        onTouchEnd: (s, i, e) => log('end', i),
      ),
    ])));
    final g = await tester.startGesture(_ring, kind: PointerDeviceKind.touch);
    await g.moveTo(_outside);
    await g.up();
    await tester.pump();
    expect(calls, ['start 0', 'move 10 0', 'end 0']);
  });

  testWidgets('RadialBar: a touch that starts off the sectors fires none of them', (tester) async {
    var n = 0;
    await tester.pumpWidget(host(RadialBarChart(width: 200, height: 200, data: const [
      {'v': 10},
    ], children: [
      RadialBar(
        dataKey: 'v',
        isAnimationActive: false,
        onTouchStart: (s, i, e) => n++,
        onTouchMove: (s, i, e) => n++,
        onTouchEnd: (s, i, e) => n++,
      ),
    ])));
    final g = await tester.startGesture(_outside, kind: PointerDeviceKind.touch);
    await g.moveTo(_ring);
    await g.up();
    await tester.pump();
    expect(n, 0);
  });

  Widget radar(List<String> calls) => RadarChart(width: 200, height: 200, data: const [
        {'k': 'a', 'v': 10},
        {'k': 'b', 'v': 10},
        {'k': 'c', 'v': 10},
        {'k': 'd', 'v': 10},
      ], children: [
        Radar(
          dataKey: 'v',
          fill: const Color(0xFFFF0000),
          isAnimationActive: false,
          onMouseOver: (e) => calls.add('over'),
          onMouseEnter: (p, e) => calls.add('enter'),
          onMouseMove: (e) => calls.add('move'),
          onMouseOut: (e) => calls.add('out'),
          onMouseLeave: (p, e) => calls.add('leave'),
          onTouchStart: (e) => calls.add('touchstart'),
          onTouchMove: (e) => calls.add('touchmove'),
          onTouchEnd: (e) => calls.add('touchend'),
        ),
      ]);

  testWidgets('Radar polygon: mouseover, mouseenter, mousemove on entering, mouseout, mouseleave on leaving', (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(host(radar(calls)));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: _outside);
    await mouse.moveTo(const Offset(100, 100));
    await mouse.moveTo(const Offset(102, 100));
    await mouse.moveTo(_outside);
    await tester.pump();
    expect(calls, ['over', 'enter', 'move', 'move', 'out', 'leave']);
    await mouse.removePointer();
  });

  testWidgets('Radar polygon: touchstart, touchmove and touchend', (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(host(radar(calls)));
    final g = await tester.startGesture(const Offset(100, 100), kind: PointerDeviceKind.touch);
    await g.moveTo(_outside);
    await g.up();
    await tester.pump();
    expect(calls.where((c) => c.startsWith('touch')), ['touchstart', 'touchmove', 'touchend']);
  });

  // Polygon.tsx paints an open outline (a null gap) with fill="none": pointer events hit only its stroke.
  testWidgets('Radar with a null gap: clicks inside the open outline miss it, clicks on its stroke hit it', (tester) async {
    var clicks = 0;
    Future<int> clicksAt(Object? fourth, Offset p) async {
      clicks = 0;
      // 400x400, outerRadius 156 around (200, 200), six spokes 60 degrees apart from the top, all at 100.
      await tester.pumpWidget(host(RadarChart(width: 400, height: 400, data: [
        for (final v in [100, 100, 100, fourth, 100, 100]) {'v': v},
      ], children: [
        Radar(
            dataKey: 'v',
            fill: const Color(0xFFFF0000),
            stroke: const Color(0xFF0000FF),
            isAnimationActive: false,
            onClick: (e) => clicks++),
      ])));
      await tester.tapAt(p);
      await tester.pump();
      return clicks;
    }

    // Inside the first three points' triangle, 45px from any stroke.
    const inside = Offset(290, 148);
    expect(await clicksAt(100, inside), 1);
    expect(await clicksAt(null, inside), 0);
    // On the stroke between the first two points.
    expect(await clicksAt(null, const Offset(267.5, 83)), 1);
  });

  testWidgets('Pie sectors: click, enter / leave and touch handlers get the sector and its index', (tester) async {
    final calls = <String>[];
    void log(String name, PieSector s, int i) => calls.add('$name ${s.value} $i');
    await tester.pumpWidget(host(PieChart(width: 200, height: 200, children: [
      Pie(
        data: const [
          {'name': 'a', 'value': 1},
        ],
        isAnimationActive: false,
        onClick: (s, i, e) => log('click', s, i),
        onMouseEnter: (s, i, e) => log('enter', s, i),
        onMouseLeave: (s, i, e) => log('leave', s, i),
        onTouchStart: (s, i, e) => log('touchstart', s, i),
        onTouchEnd: (s, i, e) => log('touchend', s, i),
      ),
    ])));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: _outside);
    await mouse.moveTo(_ring);
    await mouse.down(_ring);
    await mouse.up();
    await mouse.moveTo(_outside);
    await mouse.removePointer();
    expect(calls, ['enter 1 0', 'click 1 0', 'leave 1 0']);
    calls.clear();
    final g = await tester.startGesture(_ring, kind: PointerDeviceKind.touch);
    await g.up();
    await tester.pump();
    expect(calls.take(2), ['touchstart 1 0', 'touchend 1 0']);
  });
}
