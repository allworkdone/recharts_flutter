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

CartesianModel model(double w, double h, List<RechartsElement> children,
        {Margin margin = const Margin.all(5),
        ChartLayout layout = ChartLayout.horizontal,
        (int, int)? brush}) =>
    computeCartesianModel(
        chartName: 'BarChart',
        size: Size(w, h),
        data: data,
        children: children,
        margin: margin,
        layout: layout,
        barSize: 6,
        barGap: 2,
        dataStartIndex: brush?.$1 ?? 0,
        dataEndIndex: brush?.$2,
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

    // 3.10.1 kept a zero-width rect at x 0 here, which rendered nothing.
    test('a category outside the domain gives no rect', () {
      final m = model(1100, 250, [const XAxis(dataKey: 'name'), const YAxis(tickCount: 7, orientation: AxisOrientation.right), bar,
        const ReferenceArea(x1: '20150201', x2: '20150201')], margin: wide);
      expect(m.referenceAreas, isEmpty);
    });

    group('with an edge that is not a category on the axis', () {
      const overflows = [IfOverflow.discard, IfOverflow.hidden, IfOverflow.visible];
      for (final o in overflows) {
        test('should not render a rect when x1 is before the brushed range and ifOverflow=${o.name}', () {
          final m = model(400, 300, [const XAxis(dataKey: 'name'), const YAxis(), bar,
            ReferenceArea(x1: '201102', x2: '201107', ifOverflow: o)], brush: (4, 8));
          expect(m.referenceAreas, isEmpty);
        });
        test('should not render a rect when x2 is after the brushed range and ifOverflow=${o.name}', () {
          final m = model(400, 300, [const XAxis(dataKey: 'name'), const YAxis(), bar,
            ReferenceArea(x1: '201104', x2: '201110', ifOverflow: o)], brush: (0, 4));
          expect(m.referenceAreas, isEmpty);
        });
      }

      test('should not render a rect when y1 is not a category on the YAxis', () {
        final m = model(400, 300, [const XAxis(type: AxisDomainType.number),
          const YAxis(type: AxisDomainType.category, dataKey: 'name'), bar,
          const ReferenceArea(y1: '201201', y2: '201104')], layout: ChartLayout.vertical);
        expect(m.referenceAreas, isEmpty);
      });

      test('should still render a rect when both edges are in the brushed range', () {
        final m = model(400, 300, [const XAxis(dataKey: 'name'), const YAxis(), bar,
          const ReferenceArea(x1: '201107', x2: '201108')], brush: (4, 8));
        expect(m.referenceAreas, hasLength(1));
      });
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

    group('when a coordinate is not a category on the axis', () {
      const zero = Margin();
      for (final o in IfOverflow.values) {
        test('should not render a dot when x is not on the XAxis and ifOverflow=${o.name}', () {
          final m = model(400, 300, [const XAxis(dataKey: 'name'), const YAxis(), bar,
            ReferenceDot(x: '201201', y: 0, ifOverflow: o)], margin: zero);
          expect(m.referenceDots, isEmpty);
        });
        test('should not render a dot when x is outside the brushed range and ifOverflow=${o.name}', () {
          final m = model(400, 300, [const XAxis(dataKey: 'name'), const YAxis(), bar,
            ReferenceDot(x: '201102', y: 0, ifOverflow: o)], brush: (4, 8));
          expect(m.referenceDots, isEmpty);
        });
        test('should not render a dot when y is not a category on the YAxis and ifOverflow=${o.name}', () {
          final m = model(400, 300, [const XAxis(type: AxisDomainType.number),
            const YAxis(type: AxisDomainType.category, dataKey: 'name'), bar,
            ReferenceDot(x: 0, y: '201201', ifOverflow: o)], margin: zero, layout: ChartLayout.vertical);
          expect(m.referenceDots, isEmpty);
        });
      }

      test('should still render a dot when both coordinates are on the axes', () {
        final m = model(400, 300, [const XAxis(dataKey: 'name'), const YAxis(), bar,
          const ReferenceDot(x: '201106', y: 0)], brush: (4, 8));
        expect(m.referenceDots, hasLength(1));
      });

      test('should still render a dot when a numeric coordinate is outside the domain and ifOverflow is visible', () {
        final m = model(400, 300, [const XAxis(dataKey: 'name'), const YAxis(), bar,
          const ReferenceDot(x: '201106', y: 20, ifOverflow: IfOverflow.visible)]);
        expect(m.referenceDots.single.center.dx, greaterThan(0));
      });
    });
  });
}
