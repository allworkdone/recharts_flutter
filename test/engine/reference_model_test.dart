// Expectations ported from Recharts 3.10.1 ReferenceArea.spec.tsx and ReferenceDot.spec.tsx.
// The specs render in jsdom where text measures 0x0 and a YAxis keeps its default width of
// 60, which is what `measureFor: Size.zero` reproduces.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/recharts_flutter.dart';
import 'package:recharts_flutter/src/engine/model.dart';

const data = [
  {'name': '201102', 'uv': -6.11, 'pv': 0},
  {'name': '201103', 'uv': 0.39, 'pv': 0},
  {'name': '201104', 'uv': -1.37, 'pv': 0},
  {'name': '201105', 'uv': 1.16, 'pv': 0},
  {'name': '201106', 'uv': 1.29, 'pv': 0},
  {'name': '201107', 'uv': 0.09, 'pv': 0},
  {'name': '201108', 'uv': 0.53, 'pv': 0},
  {'name': '201109', 'uv': 2.52, 'pv': 0},
  {'name': '201110', 'uv': 0.79, 'pv': 0},
  {'name': '201111', 'uv': 2.94, 'pv': 0},
  {'name': '201112', 'uv': 4.3, 'pv': 0},
];

CartesianModel model(double w, double h, List<RechartsElement> children, {Margin margin = const Margin.all(5)}) =>
    computeCartesianModel(
        chartName: 'BarChart',
        size: Size(w, h),
        data: data,
        children: children,
        margin: margin,
        barSize: 6,
        barGap: 2,
        measureFor: (_) => (_) => Size.zero);

String fixed(double v) => double.parse(v.toStringAsFixed(4)).toString();

void main() {
  const wide = Margin(top: 20, right: 60, bottom: 0, left: 20);
  const bar = Bar(dataKey: 'uv');

  group('ReferenceArea', () {
    test('hallucinates the axes from the Bar and spans the missing x side', () {
      final m = model(1100, 250, [const YAxis(tickCount: 7, orientation: AxisOrientation.right), bar, const ReferenceArea(y1: 0, y2: 2)],
          margin: wide);
      final r = m.referenceAreas.single.rect;
      expect([r.left, fixed(r.top), r.width, fixed(r.height)], [20, '109.4444', 960, '25.5556']);
    });

    test('rectangle between two categories (radius spec): x, y, width, height', () {
      final m = model(200, 200, [const XAxis(dataKey: 'name'), const YAxis(), bar,
        const ReferenceArea(x1: '201106', x2: '201110', radius: 20)]);
      final r = m.referenceAreas.single.rect;
      expect([fixed(r.left), r.top, fixed(r.width), r.height], ['112.2727', 5, '59.0909', 160]);
    });

    test('renders nothing without any coordinate', () {
      final m = model(1100, 250, [const XAxis(dataKey: 'name', orientation: AxisOrientation.top), bar, const ReferenceArea(label: '0')],
          margin: wide);
      expect(m.referenceAreas, isEmpty);
    });

    test('ifOverflow: discard drops an area outside the domain, the others keep it', () {
      for (final o in IfOverflow.values) {
        final m = model(200, 200, [const XAxis(dataKey: 'name'), const YAxis(), bar,
          ReferenceArea(y1: 100, y2: 200, ifOverflow: o)]);
        expect(m.referenceAreas, o == IfOverflow.discard ? isEmpty : hasLength(1), reason: o.name);
      }
    });

    test('extendDomain stretches the y domain to the area', () {
      final m = model(1100, 250, [const XAxis(dataKey: 'name'), const YAxis(tickCount: 7), bar,
        const ReferenceArea(y1: 200, y2: 300, ifOverflow: IfOverflow.extendDomain)], margin: wide);
      expect(m.referenceAreas, hasLength(1));
      expect(axisScaleOf(m, isX: false)!.domain.last, greaterThanOrEqualTo(300));
    });

    test('a category outside the domain gives a zero-width rect', () {
      final m = model(1100, 250, [const XAxis(dataKey: 'name'), const YAxis(tickCount: 7, orientation: AxisOrientation.right), bar,
        const ReferenceArea(x1: '20150201', x2: '20150201')], margin: wide);
      expect(m.referenceAreas.single.rect.width, 0);
    });
  });

  group('ReferenceDot', () {
    test('extendDomain puts the dot at cx 472.7272, cy 20 (shape spec)', () {
      final m = model(1100, 250, [const XAxis(dataKey: 'name'), const YAxis(tickCount: 7), bar,
        const ReferenceDot(x: '201106', y: 20, r: 6, ifOverflow: IfOverflow.extendDomain)], margin: wide);
      final c = m.referenceDots.single.center;
      expect([c.dx, c.dy], [472.72727272727275, 20]);
    });

    test('discard drops a dot outside the domain; hidden and visible keep it', () {
      for (final o in IfOverflow.values) {
        final m = model(1100, 250, [const XAxis(dataKey: 'name'), const YAxis(tickCount: 7, orientation: AxisOrientation.right), bar,
          ReferenceDot(x: '201106', y: 20, ifOverflow: o)], margin: wide);
        expect(m.referenceDots, o == IfOverflow.discard ? isEmpty : hasLength(1), reason: o.name);
      }
    });

    test('needs both x and y', () {
      final m = model(1100, 250, [const XAxis(dataKey: 'name'), const YAxis(tickCount: 7), bar,
        const ReferenceDot(x: '201104'), const ReferenceDot(y: 3)], margin: wide);
      expect(m.referenceDots, isEmpty);
    });

    test('renders without an explicit YAxis', () {
      final m = model(1100, 250, [const XAxis(dataKey: 'name'), bar, const ReferenceDot(x: '201104', y: 3)], margin: wide);
      expect(m.referenceDots, hasLength(1));
    });
  });
}
