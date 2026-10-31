import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/recharts_flutter.dart';

import 'package:recharts_flutter_example/parity/fixture_renderer.dart';

void main() {
  final fixtures = Directory('assets/parity/fixtures')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in fixtures) {
    testWidgets('renders ${file.uri.pathSegments.last}', (tester) async {
      final fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Align(alignment: Alignment.topLeft, child: renderFixture(fixture)),
      ));
      await tester.pump(const Duration(seconds: 2));
      expect(find.byWidgetPredicate((w) => w is CategoricalChart), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('resolves url(#id) fills from <defs> linearGradients', (tester) async {
    final fixture = jsonDecode(File('assets/parity/fixtures/area-gradient.json').readAsStringSync());
    final chart = renderFixture(fixture as Map<String, dynamic>) as CategoricalChart;
    final fill = chart.children.whereType<Area>().first.fill as LinearGradient;
    expect(fill.begin, Alignment.topLeft);
    expect(fill.end, Alignment.bottomLeft);
    expect(fill.stops, [0.05, 0.95]);
    expect(fill.colors, [const Color(0xFF8884D8).withValues(alpha: 0.8), const Color(0x008884D8)]);
  });

  test('parses CSS colors', () {
    expect(parseCssColor('#8884d8'), const Color(0xFF8884D8));
    expect(parseCssColor('#ccc'), const Color(0xFFCCCCCC));
    expect(parseCssColor('red'), const Color(0xFFFF0000));
    expect(parseCssColor('rgba(0, 0, 0, 0.5)'), const Color.fromARGB(128, 0, 0, 0));
  });
}
