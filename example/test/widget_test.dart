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

  test('parses CSS colors', () {
    expect(parseCssColor('#8884d8'), const Color(0xFF8884D8));
    expect(parseCssColor('#ccc'), const Color(0xFFCCCCCC));
    expect(parseCssColor('red'), const Color(0xFFFF0000));
    expect(parseCssColor('rgba(0, 0, 0, 0.5)'), const Color.fromARGB(128, 0, 0, 0));
  });
}
