// Port of the d3-shape stack offsets Recharts maps 'silhouette' and 'wiggle'
// to (src/util/ChartUtils.ts STACK_OFFSET_MAP): d3-shape 3.2.0 src/offset/
// silhouette.js, wiggle.js and none.js. Series layout matches d3:
// series[key][point] is `[y0, y1]`, and `order` lists series indexes in
// stacking order.

/// JS `x || 0` for a number (NaN -> 0).
double _or0(double v) => v.isNaN ? 0 : v;

/// d3 `stackOffsetNone` (note: m is the first series' length).
void _none(List<List<List<double>>> series, List<int> order) {
  final n = series.length;
  if (n <= 1) return;
  var s1 = series[order[0]];
  final m = s1.length;
  for (var i = 1; i < n; ++i) {
    final s0 = s1;
    s1 = series[order[i]];
    for (var j = 0; j < m; ++j) {
      s1[j][0] = s0[j][1].isNaN ? s0[j][0] : s0[j][1];
      s1[j][1] += s1[j][0];
    }
  }
}

/// d3 `stackOffsetSilhouette(series, order)`; mutates [series] in place.
void stackOffsetSilhouette(List<List<List<double>>> series, List<int> order) {
  final n = series.length;
  if (n <= 0) return;
  final s0 = series[order[0]];
  for (var j = 0; j < s0.length; ++j) {
    var y = 0.0;
    for (var i = 0; i < n; ++i) {
      y += _or0(series[i][j][1]);
    }
    s0[j][0] = -y / 2;
    s0[j][1] += s0[j][0];
  }
  _none(series, order);
}

/// d3 `stackOffsetWiggle(series, order)`; mutates [series] in place.
void stackOffsetWiggle(List<List<List<double>>> series, List<int> order) {
  final n = series.length;
  if (n <= 0) return;
  final s0 = series[order[0]];
  final m = s0.length;
  if (m <= 0) return;
  var y = 0.0, j = 1;
  for (; j < m; ++j) {
    var s1 = 0.0, s2 = 0.0;
    for (var i = 0; i < n; ++i) {
      final si = series[order[i]];
      final sij0 = _or0(si[j][1]), sij1 = _or0(si[j - 1][1]);
      var s3 = (sij0 - sij1) / 2;
      for (var k = 0; k < i; ++k) {
        final sk = series[order[k]];
        s3 += _or0(sk[j][1]) - _or0(sk[j - 1][1]);
      }
      s1 += sij0;
      s2 += s3 * sij0;
    }
    s0[j - 1][0] = y;
    s0[j - 1][1] += y;
    if (s1 != 0 && !s1.isNaN) y -= s2 / s1;
  }
  s0[j - 1][0] = y;
  s0[j - 1][1] += y;
  _none(series, order);
}
