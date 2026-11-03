// PolarRadiusAxis cases of Recharts 3.10.1 test/polar/PolarRadiusAxis.spec.tsx
// (RadarChart and RadialBarChart): tick text positions, domains and scale
// types, empty data and empty dataKey. Values are the spec's literals.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/recharts_flutter.dart';
import 'package:recharts_flutter/src/engine/pie.dart';
import 'package:recharts_flutter/src/engine/polar_axis.dart';
import 'package:recharts_flutter/src/render/polar_scene_painter.dart';

import 'polar_scene_test.dart' show exampleRadarData, pageData;

PolarModel radar(List<Object?> data, List<RechartsElement> children) => computePolarModel(
      chartName: 'RadarChart',
      size: const Size(500, 500),
      data: data,
      children: children,
      layout: PolarLayout.centric,
      options: const PolarOptions(startAngle: 90, endAngle: -270),
    );

PolarModel radialBar(List<RechartsElement> children) => computePolarModel(
      chartName: 'RadialBarChart',
      size: const Size(500, 500),
      data: pageData,
      children: children,
      layout: PolarLayout.radial,
      options: const PolarOptions(startAngle: 0, endAngle: 360),
    );

List<double> xs(PolarModel m, PolarRadiusAxis a) => [for (final (_, p) in radiusAxisTickPositions(m.scene!, a)) p.dx];
List<Object?> values(PolarModel m, PolarRadiusAxis a) => [for (final (t, _) in radiusAxisTickPositions(m.scene!, a)) t.value];

Matcher near(num v) => closeTo(v, 1e-9);

void main() {
  group('in RadarChart', () {
    test('categorical dataKey: band scale over the names, tick text between the radii', () {
      const axis = PolarRadiusAxis(label: 'test', dataKey: 'name', type: AxisDomainType.category);
      final m = radar(exampleRadarData, const [axis]);
      final a = m.scene!.radiusAxes[0]!;
      expect(a.domain, ['iPhone 3GS', 'iPhone 4', 'iPhone 4s', 'iPhone 5', 'iPhone 5s', 'iPhone 6', 'iPhone 6s', 'iPhone 5se']);
      expect(a.realScaleType, 'band');
      expect(a.domainWithNiceTicks, a.domain);
      expect(values(m, axis), a.domain);
      expect(xs(m, axis), [for (final x in [262.25, 286.75, 311.25, 335.75, 360.25, 384.75, 409.25, 433.75]) near(x)]);
    });

    test('orientation left puts the same ticks on the axis', () {
      const axis = PolarRadiusAxis(orientation: PolarRadiusOrientation.left, label: 'test');
      final m = radar(exampleRadarData, const [Radar(dataKey: 'value'), axis]);
      expect(values(m, axis), [0, 250, 500, 750, 1000]);
      expect(xs(m, axis), [250, 299, 348, 397, 446]);
    });

    test('tickCount: 3', () {
      const axis = PolarRadiusAxis(dataKey: 'value', tickCount: 3);
      final m = radar(exampleRadarData, const [Radar(dataKey: 'value'), axis]);
      expect(values(m, axis), [0, 500, 1000]);
      expect(xs(m, axis), [250, 348, 446]);
    });

    test('no ticks when the data is empty', () {
      const axis = PolarRadiusAxis(orientation: PolarRadiusOrientation.left, label: 'test', dataKey: 'value');
      final m = radar(const [], const [axis]);
      expect(radiusAxisTickPositions(m.scene!, axis), isEmpty);
    });

    test('no ticks when the dataKey is empty', () {
      const axis = PolarRadiusAxis(orientation: PolarRadiusOrientation.left, label: 'test', dataKey: '');
      final m = radar(exampleRadarData, const [axis]);
      expect(radiusAxisTickPositions(m.scene!, axis), isEmpty);
    });
  });

  group('in RadialBarChart (500x500, PageData)', () {
    test('implicit axis: the domain is the data indexes, band scale, nothing to render', () {
      final m = radialBar(const [RadialBar(dataKey: 'ov')]);
      final a = m.scene!.radiusAxes[0]!;
      expect(a.domain, [0, 1, 2, 3, 4, 5]);
      expect(a.realScaleType, 'band');
      expect(a.rangeWithReverse, [0, 196]);
      expect(a.scale!.domain, [0, 1, 2, 3, 4, 5]);
      expect(a.scale!.range, [0, 196]);
      expect(a.settings.type, AxisDomainType.category);
      expect(a.settings.tickCount, 5);
    });

    test('default axis: category ticks at the band centers', () {
      const axis = PolarRadiusAxis();
      final m = radialBar(const [axis, RadialBar(dataKey: 'ov')]);
      expect(values(m, axis), [0, 1, 2, 3, 4, 5]);
      expect(xs(m, axis), [
        near(266.3333333333333),
        near(299),
        near(331.66666666666663),
        near(364.3333333333333),
        near(397),
        near(429.66666666666663),
      ]);
      expect(m.scene!.radiusAxes[0]!.settings.allowDuplicatedCategory, isTrue);
    });

    test('numerical axis: domain [0, 400] with ticks every 100', () {
      const axis = PolarRadiusAxis(dataKey: 'uv', type: AxisDomainType.number, label: 'test');
      final m = radialBar(const [RadialBar(dataKey: 'uv'), axis]);
      final a = m.scene!.radiusAxes[0]!;
      expect(a.domain, [0, 400]);
      expect(a.realScaleType, 'linear');
      expect(a.domainWithNiceTicks, [0, 400]);
      expect(a.scale!.range, [0, 196]);
      expect(values(m, axis), [0, 100, 200, 300, 400]);
      expect(xs(m, axis), [250, 299, 348, 397, 446]);
    });

    test('an axis alone, without a RadialBar: category over the data indexes', () {
      const axis = PolarRadiusAxis(dataKey: 'uv');
      final m = radialBar(const [axis]);
      final a = m.scene!.radiusAxes[0]!;
      expect(a.settings.type, AxisDomainType.category);
      expect(a.domain, [0, 1, 2, 3, 4, 5]);
      expect(a.realScaleType, 'band');
    });
  });
}
