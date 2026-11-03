import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter_example/parity/fixture_renderer.dart';
import 'package:recharts_flutter_example/tooltip_modes.dart';

void main() {
  final fixture = jsonDecode(File('assets/parity/fixtures/line-simple.json').readAsStringSync());

  /// Touches line-simple at (300, [y]), drags a little, waits for the card to
  /// settle, and returns the tooltip label's top edge.
  Future<double> labelTopAfterTouch(WidgetTester tester, TooltipMode mode, double y) async {
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: renderFixture(withTooltipMode(fixture, mode) as Map<String, dynamic>),
      ),
    ));
    await tester.pump(const Duration(seconds: 2));
    final finger = await tester.startGesture(Offset(300, y), kind: PointerDeviceKind.touch);
    await finger.moveTo(Offset(305, y));
    // On first display Recharts glides the card in from the chart's top-left
    // corner over 400ms (Tooltip.animation.spec "should start at 0,0").
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final label = find.byWidgetPredicate((w) => w is Text && (w.data ?? '').startsWith('Page'));
    expect(label, findsOneWidget, reason: 'tooltip shows while the finger is down ($mode)');
    final top = tester.getTopLeft(label).dy;
    await finger.up();
    return top;
  }

  testWidgets('below (Recharts default) puts the card under the finger', (tester) async {
    expect(await labelTopAfterTouch(tester, TooltipMode.below, 60), greaterThan(60 + 10));
  });

  testWidgets('above puts the card over the finger', (tester) async {
    // Same finger height as the pinned case, so only the mode differs.
    final top = await labelTopAfterTouch(tester, TooltipMode.above, 250);
    expect(top, lessThan(250 - 16));
    expect(top, greaterThan(30));
  });

  testWidgets('pinned top puts the card at the top of the chart', (tester) async {
    expect(await labelTopAfterTouch(tester, TooltipMode.pinnedTop, 250), lessThan(30));
  });

  test('modes only touch Tooltip props', () {
    final out = withTooltipMode(fixture, TooltipMode.above) as Map<String, dynamic>;
    final chart = out['chart'] as Map<String, dynamic>;
    final tooltip = (chart['children'] as List).cast<Map<String, dynamic>>().firstWhere((c) => c['type'] == 'Tooltip');
    expect(tooltip['props'], containsPair('offset', 16));
    expect(jsonEncode(chart['props']), jsonEncode((fixture['chart'] as Map)['props']));
  });
}
