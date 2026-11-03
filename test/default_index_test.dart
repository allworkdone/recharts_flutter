// Tooltip.defaultIndex coercion: Tooltip.tsx String(), combineActiveTooltipIndex
// Number() + clamp without flooring, parseInt in the payload lookup, and a
// non-finite index that keeps the string but finds nothing (Tooltip.visibility.spec
// "should ignore invalid defaultIndex value").

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/recharts_flutter.dart';

import 'widgets/chart_widget_test.dart' show host;
import 'widgets/tooltip_item_test.dart' show Probe;

const data = [
  {'name': 'A', 'uv': 400},
  {'name': 'B', 'uv': 300},
  {'name': 'C', 'uv': 200},
];

void main() {
  Future<Probe> line(WidgetTester tester, Object index) async {
    final probe = Probe();
    await tester.pumpWidget(host(LineChart(width: 300, height: 200, data: data, children: [
      const XAxis(dataKey: 'name'),
      const Line(dataKey: 'uv', isAnimationActive: false),
      Tooltip(isAnimationActive: false, defaultIndex: index, content: probe.build),
    ])));
    expect(tester.takeException(), isNull);
    return probe;
  }

  group('LineChart', () {
    for (final idx in <Object>['1.5', 1.5]) {
      testWidgets('$idx: payload of row 1, but no label, coordinate or cursor', (tester) async {
        final probe = await line(tester, idx);
        expect(probe.rows, ['uv : 300']);
        expect(probe.props!.label, isNull);
        expect(probe.props!.coordinate, isNull);
      });
    }

    for (final idx in <Object>['NaN', double.nan, double.infinity, double.negativeInfinity, 'abc']) {
      testWidgets('$idx stays hidden and does not throw', (tester) async {
        final probe = await line(tester, idx);
        expect(probe.visible, isFalse);
      });
    }

    testWidgets("'' is Number('') = 0", (tester) async {
      final probe = await line(tester, '');
      expect(probe.rows, ['uv : 400']);
      expect(probe.props!.label, 'A');
      expect(probe.props!.coordinate, isNotNull);
    });

    testWidgets('an index past the data clamps to the last row, with no tick coordinate', (tester) async {
      final probe = await line(tester, 10);
      expect(probe.rows, ['uv : 200']);
      expect(probe.props!.label, 'C');
      expect(probe.props!.coordinate, isNull);
    });

    testWidgets('a negative index clamps to the first row', (tester) async {
      final probe = await line(tester, -1);
      expect(probe.rows, ['uv : 400']);
      expect(probe.props!.label, 'A');
    });

    testWidgets("'1' and 1 are the same", (tester) async {
      final a = await line(tester, '1');
      final b = await line(tester, 1);
      expect(a.rows, b.rows);
      expect(a.props!.coordinate, isNotNull);
      expect(a.props!.coordinate, b.props!.coordinate);
    });
  });

  testWidgets('PieChart: NaN is hidden, 1.5 shows row 1', (tester) async {
    Future<Probe> pie(Object index) async {
      final probe = Probe();
      await tester.pumpWidget(host(PieChart(width: 300, height: 300, children: [
        const Pie(data: data, dataKey: 'uv', nameKey: 'name', isAnimationActive: false),
        Tooltip(isAnimationActive: false, defaultIndex: index, content: probe.build),
      ])));
      expect(tester.takeException(), isNull);
      return probe;
    }

    expect((await pie(double.nan)).visible, isFalse);
    final probe = await pie('1.5');
    expect(probe.rows, ['B : 300']);
    expect(probe.props!.coordinate, isNull);
  });

  testWidgets('Funnel: the coordinate is the trapezoid tooltipPosition', (tester) async {
    final probe = Probe();
    await tester.pumpWidget(host(FunnelChart(width: 300, height: 300, children: [
      const Funnel(dataKey: 'uv', data: data, isAnimationActive: false),
      Tooltip(isAnimationActive: false, defaultIndex: 1, content: probe.build),
    ])));
    expect(probe.rows, ['B : 300']);
    expect(probe.props!.coordinate, isNotNull);
  });

  group('Treemap (Tooltip.visibility.spec: children[0]children[0])', () {
    Future<Probe> treemap(WidgetTester tester, Object index) async {
      final probe = Probe();
      await tester.pumpWidget(host(Treemap(width: 300, height: 300, isAnimationActive: false, dataKey: 'uv', data: const [
        {
          'name': 'A',
          'children': [
            {'name': 'A1', 'uv': 5},
            {'name': 'A2', 'uv': 6},
          ]
        },
        {'name': 'B', 'uv': 3},
      ], children: [
        Tooltip(isAnimationActive: false, defaultIndex: index, content: probe.build),
      ])));
      return probe;
    }

    testWidgets('a children path shows the node at (0,0)', (tester) async {
      final probe = await treemap(tester, 'children[0]children[1]');
      expect(probe.rows, ['A2 : 6']);
      expect(probe.props!.coordinate, isNull);
      expect(probe.props!.activeIndex, 'children[0]children[1]');
    });

    testWidgets('a numeric index finds nothing', (tester) async {
      final probe = await treemap(tester, 0);
      expect(probe.visible, isFalse);
    });
  });
}
