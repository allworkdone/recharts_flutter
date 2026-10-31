// Checks lib/src/core/curve.dart against Recharts' getPath (d3-shape line +
// curve factories): every PathSink call must match the SVG path command for
// command (fixtures from tool/fixtures_gen).


import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/src/core/curve.dart';

import 'fixture_utils.dart';

class _RecordingSink implements PathSink {
  final List<List<Object>> calls = [];

  @override
  void moveTo(double x, double y) => calls.add(['M', x, y]);
  @override
  void lineTo(double x, double y) => calls.add(['L', x, y]);
  @override
  void bezierCurveTo(double x1, double y1, double x2, double y2, double x, double y) =>
      calls.add(['C', x1, y1, x2, y2, x, y]);
  @override
  void closePath() => calls.add(['Z']);
}

final _token = RegExp(r'[MLCZ]|NaN|-?Infinity|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?');
const _arity = {'M': 2, 'L': 2, 'C': 6, 'Z': 0};

/// Parses d3-path output (absolute M/L/C/Z, comma separated) into commands.
List<List<Object>> _parsePath(String? d) {
  if (d == null) return [];
  final tokens = _token.allMatches(d).map((m) => m[0]!).toList();
  final out = <List<Object>>[];
  for (var i = 0; i < tokens.length;) {
    final cmd = tokens[i++];
    final n = _arity[cmd]!;
    out.add([cmd, for (var k = 0; k < n; k++) dn(double.tryParse(tokens[i + k]) ?? tokens[i + k])!]);
    i += n;
  }
  return out;
}

bool _sameCalls(List<List<Object>> a, List<List<Object>> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].length != b[i].length || a[i][0] != b[i][0]) return false;
    for (var k = 1; k < a[i].length; k++) {
      if (!close(a[i][k] as double, b[i][k] as double)) return false;
    }
  }
  return true;
}

void main() {
  final fixtures = loadFixture('curves.json') as List;

  test('drawLine matches Recharts getPath for every curve type', () {
    final m = Mismatches();
    for (final c in fixtures) {
      final points = [
        for (final p in c['points'] as List) p == null ? null : Offset(dn(p[0])!, dn(p[1])!),
      ];
      final type = CurveType.values.byName(c['type'] as String);
      final layout = ChartLayout.values.byName(c['layout'] as String);
      final sink = _RecordingSink();
      drawLine(sink, points, type, layout: layout, connectNulls: c['connectNulls'] as bool);
      final want = _parsePath(c['d'] as String?);
      m.check(
        _sameCalls(sink.calls, want),
        () => '${c['name']} ${type.name} ${layout.name} connectNulls=${c['connectNulls']}:\n'
            '  got  ${sink.calls}\n  want $want',
      );
    }
    m.expectNone();
  });

  test('linePath builds a Flutter Path', () {
    final path = linePath([const Offset(0, 0), const Offset(10, 20), const Offset(20, 5)], CurveType.monotone);
    expect(path.getBounds().right, 20);
  });
}
