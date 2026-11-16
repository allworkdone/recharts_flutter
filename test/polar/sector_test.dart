// Polar math and the Sector shape, ported from Recharts 3.11.0-canary.9
// test/util/PolarUtils.spec.ts and test/shape/Sector.spec.tsx (+ snapshots).

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/src/core/polar_utils.dart';
import 'package:recharts_flutter/src/render/sector.dart';

void main() {
  group('PolarUtils.spec.ts', () {
    test('degreeToRadian / radianToDegree', () {
      for (final (deg, rad) in [(0.0, 0.0), (180.0, math.pi), (360.0, math.pi * 2), (90.0, math.pi / 2)]) {
        expect(degreeToRadian(deg), rad);
        expect(radianToDegree(rad), deg);
      }
    });

    test('polarToCartesian', () {
      expect(polarToCartesian(0, 0, 0, 0), Offset.zero);
      for (final (cx, cy, r, angle, x, y) in [
        (0.0, 0.0, 1.0, radian / 2, 1.0, 0.0),
        (0.0, 0.0, 1.0, radian, 1.0, 0.0),
        (5.0, 7.0, 1.0, radian, 6.0, 7.0),
        (0.0, 0.0, 15.0, 0.0, 15.0, 0.0),
      ]) {
        final p = polarToCartesian(cx, cy, r, angle);
        expect(p.dx, closeTo(x, 1e-3));
        expect(p.dy, closeTo(y, 1e-3));
      }
    });

    test('getMaxRadius', () {
      expect(getMaxRadius(0, 0), 0);
      for (final (w, h, r) in [(10.0, 10.0, 5.0), (4.0, 10.0, 2.0), (10.0, 6.0, 3.0), (-10.0, 10.0, 5.0), (-10.0, -10.0, 5.0)]) {
        expect(getMaxRadius(w, h), r);
      }
      expect(getMaxRadius(10, 8, top: 2, right: 2, bottom: 2, left: 2), 2);
    });

    test('inRangeOfSector', () {
      const v = PolarViewBox(cx: 100, cy: 100, innerRadius: 10, outerRadius: 50, startAngle: 90, endAngle: -270);
      expect(inRangeOfSector(const Offset(130, 100), v)?.angle, 0);
      // reverseFormatAngleOfSector shifts back by the turns removed from the range.
      expect(inRangeOfSector(const Offset(100, 70), v)?.angle, -270);
      expect(inRangeOfSector(const Offset(100, 105), v), isNull); // inside innerRadius
      expect(inRangeOfSector(const Offset(100, 160), v), isNull); // outside outerRadius
      const half = PolarViewBox(cx: 0, cy: 0, innerRadius: 0, outerRadius: 10, startAngle: 0, endAngle: 180);
      expect(inRangeOfSector(const Offset(0, 5), half), isNull); // below the x axis
      expect(inRangeOfSector(const Offset(0, -5), half)?.angle, 90);
    });
  });

  group('Sector.spec.tsx', () {
    group('when the sector is too narrow for the full cornerRadius', () {
      String path(SectorGeometry Function(double cx, double cy) g) => sectorPathData(g(200, 200))!;
      List<double> arcRadii(String d) => [for (final m in RegExp(r'A\s*([\d.]+),').allMatches(d)) double.parse(m[1]!)];

      for (final (startAngle, endAngle) in [(0.0, 10.0), (10.0, 0.0)]) {
        test('shrinks the corners so that they still fit ($startAngle to $endAngle)', () {
          final d = path((cx, cy) => SectorGeometry(
              cx: cx, cy: cy, outerRadius: 100, startAngle: startAngle, endAngle: endAngle, cornerRadius: 20));
          expect(arcRadii(d), [8.0169, 100, 8.0169]);
        });
      }

      test('shrinks the outer and inner corners separately', () {
        final d = path((cx, cy) => SectorGeometry(
            cx: cx, cy: cy, innerRadius: 50, outerRadius: 100, endAngle: 30, cornerRadius: 25));
        expect(arcRadii(d), [20.5605, 100, 20.5605, 17.4599, 50, 17.4599]);
      });

      test('shrinks only the inner corners when the outer corners fit', () {
        final d = path((cx, cy) => SectorGeometry(
            cx: cx, cy: cy, innerRadius: 50, outerRadius: 100, endAngle: 18, cornerRadius: 10));
        expect(arcRadii(d), [10, 100, 10, 9.2722, 50, 9.2722]);
      });

      test('renders a circle with the full cornerRadius when forceCornerRadius is true', () {
        final d = path((cx, cy) => SectorGeometry(
            cx: cx, cy: cy, outerRadius: 100, endAngle: 10, cornerRadius: 20, forceCornerRadius: true));
        expect(arcRadii(d), isEmpty);
        expect(d, contains('a20,20,0,0,1,40,0'));
        expect(d, contains('a20,20,0,0,1,-40,0'));
      });
    });

    test('a simple sector', () {
      expect(
          sectorPathData(const SectorGeometry(cx: 200, cy: 300, innerRadius: 150, outerRadius: 200, endAngle: 90)),
          'M 400,300 A 200,200,0, 0,0, 200,100 L 200,150 A 150,150,0, 0,1, 350,300 Z');
    });

    test('cornerRadius draws six arcs', () {
      expect(
          sectorPathData(const SectorGeometry(
              cx: 200, cy: 300, innerRadius: 150, outerRadius: 200, cornerRadius: 10, endAngle: 90)),
          'M 389.7367,300 A10,10,0,0,0,399.7228,289.4737 A200,200,0,0,0,210.5263,100.2772 '
          'A10,10,0,0,0,200,110.2633 L200,140.3128 A10,10,0,0,0,209.375,150.2933 '
          'A150,150,0,0,1,349.7067,290.625 A10,10,0,0,0,359.6872,300Z');
    });

    test('renders nothing for invalid props', () {
      expect(sectorPathData(const SectorGeometry(cx: 200, cy: 300, innerRadius: 200, outerRadius: 150, endAngle: 90)),
          isNull);
      expect(
          sectorPathData(const SectorGeometry(
              cx: 200, cy: 300, innerRadius: 150, outerRadius: 200, startAngle: 90, endAngle: 90)),
          isNull);
    });

    test('forceCornerRadius draws a dot for a sector thinner than its corners', () {
      expect(
          sectorPathData(const SectorGeometry(
              cx: 0, cy: 0, outerRadius: 100, cornerRadius: 10, forceCornerRadius: true, endAngle: 1)),
          startsWith('M '));
      expect(
          sectorPathData(const SectorGeometry(
              cx: 0, cy: 0, outerRadius: 100, cornerRadius: 10, forceCornerRadius: true, endAngle: 1))!,
          contains('a10,10,0,0,1,20,0 a10,10,0,0,1,-20,0'));
    });

    test('a non-finite sector paints nothing', () {
      const g = SectorGeometry(cx: 0, cy: 0, outerRadius: 100, endAngle: double.nan);
      expect(sectorPathData(g), isNull);
      expect(sectorPath(g), isNull);
    });

    test('a NaN innerRadius draws a full slice to the centre; NaN elsewhere draws nothing', () {
      final d = sectorPathData(const SectorGeometry(cx: 0, cy: 0, innerRadius: double.nan, outerRadius: 100, endAngle: 90));
      expect(d, endsWith('L 0,0 Z'));
      expect(sectorPathData(const SectorGeometry(cx: 0, cy: 0, innerRadius: double.negativeInfinity, outerRadius: 100, endAngle: 90)), endsWith('L 0,0 Z'));
      expect(sectorPathData(const SectorGeometry(cx: double.nan, cy: 0, outerRadius: 100, endAngle: 90)), isNull);
      expect(sectorPathData(const SectorGeometry(cx: 0, cy: 0, outerRadius: double.infinity, endAngle: 90)), isNull);
    });

    test('SVG path data reads into the same Path as Skia arcs', () {
      final path = parseSvgPathData('M 400,300 A 200,200,0, 0,0, 200,100 L 200,150 A 150,150,0, 0,1, 350,300 Z');
      expect(path.contains(const Offset(320, 200)), isTrue);
      expect(path.contains(const Offset(220, 280)), isFalse); // inside the inner radius
      expect(path.getBounds().left, closeTo(200, 1e-3));
      expect(path.getBounds().top, closeTo(100, 1e-3));
    });
  });

}
