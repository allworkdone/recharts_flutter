// Checks lib/src/core/symbols.dart against Recharts' <Symbols> (calculateAreaSize
// + d3-shape symbols through d3-path with 3 digits): every SymbolPathSink call
// must match the rendered `d` command for command (fixtures from tool/fixtures_gen).

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/src/core/symbols.dart';

import 'fixture_utils.dart';

class _RecordingSink implements SymbolPathSink {
  final List<List<Object>> calls = [];

  @override
  void moveTo(double x, double y) => calls.add(['M', x, y]);
  @override
  void lineTo(double x, double y) => calls.add(['L', x, y]);
  @override
  void arcTo(double rx, double ry, bool largeArc, bool sweep, double x, double y) =>
      calls.add(['A', rx, ry, 0.0, largeArc ? 1.0 : 0.0, sweep ? 1.0 : 0.0, x, y]);
  @override
  void closePath() => calls.add(['Z']);
}

final _token = RegExp(r'[MLAhvZ]|NaN|-?Infinity|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?');
const _arity = {'M': 2, 'L': 2, 'A': 7, 'h': 1, 'v': 1, 'Z': 0};

/// Parses d3-path output into absolute commands: `h` / `v` become `L` from the
/// current point, the way the SVG renderer resolves them.
List<List<Object>> _parsePath(String? d) {
  if (d == null) return [];
  final tokens = _token.allMatches(d).map((m) => m[0]!).toList();
  final out = <List<Object>>[];
  var x = 0.0, y = 0.0, x0 = 0.0, y0 = 0.0;
  for (var i = 0; i < tokens.length;) {
    final cmd = tokens[i++];
    final args = [for (var k = 0; k < _arity[cmd]!; k++) dn(double.tryParse(tokens[i + k]) ?? tokens[i + k])!];
    i += args.length;
    switch (cmd) {
      case 'h':
        x += args[0];
        out.add(['L', x, y]);
      case 'v':
        y += args[0];
        out.add(['L', x, y]);
      case 'Z':
        x = x0;
        y = y0;
        out.add(['Z']);
      default:
        x = args[args.length - 2];
        y = args[args.length - 1];
        if (cmd == 'M') {
          x0 = x;
          y0 = y;
        }
        out.add([cmd, ...args]);
    }
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
  test('drawSymbol matches Recharts Symbols for every type, size and sizeType', () {
    final m = Mismatches();
    for (final c in loadFixture('symbols.json') as List) {
      final type = SymbolType.values.byName(c['type'] as String);
      final sizeType = SymbolSizeType.values.byName(c['sizeType'] as String);
      final sink = _RecordingSink();
      drawSymbol(sink, type, calculateAreaSize(dn(c['size'])!, sizeType, type));
      final want = _parsePath(c['d'] as String?);
      m.check(_sameCalls(sink.calls, want),
          () => '${type.name} ${sizeType.name} ${c['size']}:\n  got  ${sink.calls}\n  want $want');
    }
    m.expectNone();
  });

  test('symbolPath builds a Flutter Path centered at the origin', () {
    // Scatter.animation.spec.tsx: size 64 is a circle of radius 4.514 (Path bounds are float32).
    final b = symbolPath(SymbolType.circle, 64).getBounds();
    expect(b.left, closeTo(-4.514, 1e-5));
    expect(b.bottom, closeTo(4.514, 1e-5));
    expect(symbolPath(SymbolType.square, 64).getBounds(), const Rect.fromLTRB(-4, -4, 4, 4));
  });
}
