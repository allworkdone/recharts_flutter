// getCartesianPosition.spec.ts: 'in regular Funnel' (x 100, y 50, upper 200, lower 150,
// height 100, offset 5), 'with negative width' and 'with parentViewBox and clamp=true'.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/recharts_flutter.dart';
import 'package:recharts_flutter/src/render/label.dart';

List<Object?> at(Rect viewBox, LabelPosition p, double upper, double lower,
    {double offset = 5, Rect? parent}) {
  final r = getCartesianPosition(viewBox, p, offset,
      parentViewBox: parent, clamp: parent != null, trapezoid: (upper: upper, lower: lower));
  return [r.x, r.y, r.horizontalAnchor.name, r.verticalAnchor.name, if (r.width != null) r.width, if (r.height != null) r.height];
}

void main() {
  const box = Rect.fromLTWH(100, 50, 175, 100);
  test('regular funnel', () {
    final expected = {
      LabelPosition.insideTop: [200, 50, 'middle', 'start'],
      LabelPosition.top: [200, 45, 'middle', 'end'],
      LabelPosition.bottom: [200, 155, 'middle', 'start'],
      LabelPosition.left: [107.5, 100, 'end', 'middle'],
      LabelPosition.right: [292.5, 100, 'start', 'middle'],
      LabelPosition.insideLeft: [117.5, 100, 'start', 'middle'],
      LabelPosition.insideRight: [282.5, 100, 'end', 'middle'],
      LabelPosition.insideBottom: [200, 145, 'middle', 'end'],
      LabelPosition.insideTopLeft: [105, 55, 'start', 'start'],
      LabelPosition.insideTopRight: [295, 55, 'end', 'start'],
      LabelPosition.insideBottomLeft: [130, 145, 'start', 'end'],
      LabelPosition.insideBottomRight: [270, 145, 'end', 'end'],
      LabelPosition.middle: [200, 100, 'middle', 'middle'],
    };
    expected.forEach((p, v) {
      expect(at(box, p, 200, 150, offset: p == LabelPosition.insideTop ? 0 : 5), v, reason: p.name);
    });
  });

  test('negative width flips the horizontal anchors', () {
    expect(at(const Rect.fromLTWH(300, 50, -175, 100), LabelPosition.left, -200, -150), [292.5, 100, 'start', 'middle']);
  });

  test('clamp keeps the label inside the parent box', () {
    const parent = Rect.fromLTWH(0, 0, 500, 500);
    const rect = Rect.fromLTWH(100, 50, 200, 100);
    expect(at(rect, LabelPosition.top, 200, 200, parent: parent), [200, 45, 'middle', 'end', 200, 50]);
    expect(at(rect, LabelPosition.insideLeft, 200, 200, parent: parent), [105, 100, 'start', 'middle', 200, 100]);
  });
}
