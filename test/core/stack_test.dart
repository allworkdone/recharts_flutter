// Checks lib/src/core/stack.dart against d3-shape's stackOffsetSilhouette /
// stackOffsetWiggle run through d3 stack() (fixtures from tool/fixtures_gen).

import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/src/core/stack.dart';

import 'fixture_utils.dart';

void main() {
  test('stack offsets match d3-shape', () {
    final m = Mismatches();
    for (final c in loadFixture('stack.json') as List) {
      final rows = [for (final r in c['input'] as List) dnList(r)];
      final n = rows.length;
      // d3 stack(): series[key][point] = [0, value], then the offset.
      final series = [
        for (final r in rows) [for (final v in r) [0.0, v]],
      ];
      final order = c['order'] == 'asc' ? [for (var i = 0; i < n; i++) i] : [for (var i = n - 1; i >= 0; i--) i];
      (c['offset'] == 'silhouette' ? stackOffsetSilhouette : stackOffsetWiggle)(series, order);
      final want = [
        for (final s in c['out'] as List) [for (final p in s as List) dnList(p)],
      ];
      var ok = true;
      for (var i = 0; i < n; i++) {
        for (var j = 0; j < rows[i].length; j++) {
          ok = ok && closeList(series[i][j], want[i][j]);
        }
      }
      m.check(ok, () => '${c['name']} ${c['offset']} ${c['order']}:\n  got  $series\n  want $want');
    }
    m.expectNone();
  });
}
