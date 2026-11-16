// Pie geometry, legend, tooltip and animation steps, ported from Recharts
// 3.10.1 test/polar/Pie/Pie.spec.tsx, Pie.animation.spec.tsx and
// test/chart/PieChart.spec.tsx. Sectors are compared the way the specs read
// them: the rendered `d` attribute (after the animation step, which rounds
// each sector's angle to 4 decimals), and angles recovered from its points
// (test/helper/expectPieSectors.ts).

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:recharts_flutter/recharts_flutter.dart';
import 'package:recharts_flutter/src/animation.dart';
import 'package:recharts_flutter/src/core/polar_utils.dart';
import 'package:recharts_flutter/src/engine/pie.dart';
import 'package:recharts_flutter/src/render/polar_painter.dart';
import 'package:recharts_flutter/src/render/sector.dart';
import 'package:recharts_flutter/src/util.dart';

const pageData = [
  {'name': 'Page A', 'uv': 400, 'pv': 2400, 'amt': 2400},
  {'name': 'Page B', 'uv': 300, 'pv': 4567, 'amt': 2400},
  {'name': 'Page C', 'uv': 300, 'pv': 1398, 'amt': 2400},
  {'name': 'Page D', 'uv': 200, 'pv': 9800, 'amt': 2400},
  {'name': 'Page E', 'uv': 278, 'pv': 3908, 'amt': 2400},
  {'name': 'Page F', 'uv': 189, 'pv': 4800, 'amt': 2400},
];

const sectorsData = [
  {'cx': 250, 'cy': 250, 'innerRadius': 50, 'outerRadius': 100, 'startAngle': 0, 'endAngle': 72, 'name': 'A', 'value': 40},
  {'cx': 250, 'cy': 250, 'innerRadius': 50, 'outerRadius': 100, 'startAngle': 72, 'endAngle': 144, 'name': 'B'},
  {'cx': 250, 'cy': 250, 'innerRadius': 50, 'outerRadius': 100, 'startAngle': 144, 'endAngle': 216, 'name': 'C'},
  {'cx': 250, 'cy': 250, 'innerRadius': 50, 'outerRadius': 100, 'startAngle': 216, 'endAngle': 288},
  {'cx': 250, 'cy': 250, 'innerRadius': 50, 'outerRadius': 100, 'startAngle': 288, 'endAngle': 360},
];

const groupData = [
  {'name': 'Group A', 'value': 400, 'v': 89},
  {'name': 'Group B', 'value': 300, 'v': 100},
  {'name': 'Group C', 'value': 200, 'v': 200},
  {'name': 'Group D', 'value': 200, 'v': 20},
  {'name': 'Group E', 'value': 278, 'v': 40},
  {'name': 'Group F', 'value': 189, 'v': 60},
];

PolarModel model(List<RechartsElement> children, {Size size = const Size(500, 500), List<Object?> data = const []}) =>
    computePolarModel(chartName: 'PieChart', size: size, data: data, children: children);

/// What PieSectors renders once the animation is over (or switched off).
List<PieSector> rendered(List<PieSector> sectors) =>
    interpolatePieSectors(matchAnimationItems(null, sectors, MatchBy.append), 1);

List<String> paths(List<PieSector> sectors) => [
      for (final (i, s) in sectors.indexed)
        if (rendersSector(sectors, i)) ?sectorPathData(sectorGeometry(s)),
    ];

/// `calculateAnglesFromPath` of test/helper/expectPieSectors.ts.
({double startAngle, double endAngle}) anglesOf(PieSector s) {
  final d = sectorPathData(sectorGeometry(s))!;
  final m = RegExp(r'M\s*([-\d.]+)[,\s]+([-\d.]+)\s*A(?:[\s\d,.]*?)\s*([-\d.]+)[,\s]+([-\d.]+)\s*L').firstMatch(d)!;
  double angle(double x, double y) {
    var deg = math.atan2(-(y - s.cy), x - s.cx) * 180 / math.pi;
    if (deg < 0) deg += 360;
    return round4(deg);
  }

  final [x1, y1, x2, y2] = [for (var i = 1; i <= 4; i++) double.parse(m[i]!)];
  return (startAngle: angle(x1, y1), endAngle: angle(x2, y2));
}

List<({double startAngle, double endAngle})> angles(List<PieSector> sectors) => [
      for (final (i, s) in sectors.indexed)
        if (rendersSector(sectors, i) && sectorPathData(sectorGeometry(s)) != null) anglesOf(s),
    ];

({double startAngle, double endAngle}) a(double startAngle, double endAngle) =>
    (startAngle: startAngle, endAngle: endAngle);

/// The animation step at mocked progress [p] (MockProgressAnimationManager).
final _ease = createEasingFunction('ease')!;
double tAt(double p) => p >= 1 ? 1 : _ease(round4(p));

void main() {
  group('Pie.spec.tsx rendering', () {
    test('sectors of a simple Pie', () {
      final m = model(const [
        Pie(isAnimationActive: false, cx: 250, cy: 250, innerRadius: 0, outerRadius: 200, data: pageData, dataKey: 'uv'),
      ]);
      expect(paths(rendered(m.pies.single.sectors!)), [
        'M 455,255 A 200,200,0, 0,0, 267.6184,55.3985 L 255,255 Z',
        'M 267.6184,55.3985 A 200,200,0, 0,0, 79.7896,158.5566 L 255,255 Z',
        'M 79.7896,158.5566 A 200,200,0, 0,0, 93.1078,372.4347 L 255,255 Z',
        'M 93.1078,372.4347 A 200,200,0, 0,0, 217.3458,451.4234 L 255,255 Z',
        'M 217.3458,451.4234 A 200,200,0, 0,0, 406.3627,385.7261 L 255,255 Z',
        'M 406.3627,385.7261 A 200,200,0, 0,0, 455,255.0003 L 255,255 Z',
      ]);
    });

    test('a hidden Pie and empty data render nothing', () {
      expect(computePolarModel(chartName: 'PieChart', size: const Size(500, 500), data: const [], children: const [
        Pie(data: [], dataKey: 'uv'),
      ]).pies.single.sectors, isNull);
    });

    test('the label function receives the sector and the label point', () {
      final m = model(const [
        Pie(cx: 250, cy: 250, innerRadius: 0, outerRadius: 200, data: sectorsData, dataKey: 'value', id: 'pie-value'),
      ]);
      final s = m.pies.single.sectors!.first;
      expect(
          (s.cx, s.cy, s.innerRadius, s.outerRadius, s.startAngle, s.endAngle, s.midAngle, s.middleRadius, s.percent),
          (255.0, 255.0, 0.0, 200.0, 0.0, 360.0, 180.0, 100.0, 1.0));
      expect(s.maxRadius, 346.4823227814083);
      expect((s.name, s.value, s.fill, s.paddingAngle, s.cornerRadius), ('A', 40, const Color(0xFF808080), 0.0, null));
      expect(s.tooltipPosition, const Offset(155, 255));
      // PieLabels: offsetRadius 20 outside the middle angle.
      final end = polarToCartesian(s.cx, s.cy, s.outerRadius + 20, s.midAngle);
      expect((end.dx, end.dy), (35.0, 254.99999999999997));
      final e = s.tooltipPayload;
      expect((e.name, e.value, e.dataKey, e.color, e.fill, e.type), ('A', 40, 'value', const Color(0xFF808080), const Color(0xFF808080), null));
      expect(identical(e.payload, sectorsData.first), isTrue);
    });

    test('when data.length <= 1 the paddingAngle is 0', () {
      final m = model(const [
        Pie(cx: 250, cy: 250, outerRadius: 200, paddingAngle: 10, data: [{'value': 100}]),
      ]);
      expect(m.pies.single.sectors!.single.paddingAngle, 0);
      expect(m.pies.single.sectors!.single.endAngle, 360);
    });
  });

  group('pieSelectors.spec.tsx when maxRadius is set', () {
    PieSector sector(double? maxRadius) => model([
          Pie(dataKey: 'value', data: const [{'name': 'A', 'value': 400}], outerRadius: '80%', maxRadius: maxRadius),
        ], size: const Size(800, 800)).pies.single.sectors!.single;

    test('a percentage outerRadius resolves against maxRadius', () {
      expect(sector(100).outerRadius, 80);
    });

    test('without maxRadius it resolves against the chart size', () {
      expect(sector(null).outerRadius, 316);
    });

    test('a zero maxRadius is kept', () {
      expect((sector(0).outerRadius, sector(0).maxRadius), (0, 0));
    });
  });

  group('pieSelectors.spec.tsx zero and null values with paddingAngle', () {
    List<(double, double, double)> anglesOf(List<Object?> data,
            {double startAngle = 0, double endAngle = 360, double paddingAngle = 10}) =>
        [
          for (final s in model([
            Pie(
                data: data,
                cx: 200,
                cy: 200,
                outerRadius: 80,
                startAngle: startAngle,
                endAngle: endAngle,
                paddingAngle: paddingAngle),
          ], size: const Size(400, 400)).pies.single.sectors!)
            (s.startAngle, s.endAngle, s.paddingAngle),
        ];

    test('a null value is treated like a zero value', () {
      expect(
          anglesOf(const [
            {'name': 'A', 'value': 1},
            {'name': 'Missing', 'value': null},
            {'name': 'B', 'value': 1},
          ], paddingAngle: 5),
          [(0, 175, 5), (175, 175, 0), (180, 355, 5)]);
    });

    test('no padding in front of the first non-zero sector', () {
      expect(
          anglesOf(const [
            {'name': 'Zero', 'value': 0},
            {'name': 'A', 'value': 1},
            {'name': 'B', 'value': 1},
          ], startAngle: 180, endAngle: 0),
          [(180, 180, 0), (180, 95, 0), (85, 0, -10)]);
    });

    test('the only non-zero value after a zero closes the full circle', () {
      expect(
          anglesOf(const [
            {'name': 'Zero', 'value': 0},
            {'name': 'A', 'value': 1},
          ]),
          [(0, 0, 0), (0, 360, 0)]);
    });
  });

  group('PieChart.spec.tsx', () {
    Pie pie(List<Object?> data, {double minAngle = 0}) => Pie(
        dataKey: 'value', data: data, cx: 200, cy: 200, outerRadius: 80, fill: const Color(0xFFFF7300), minAngle: minAngle);

    test('1 sector', () {
      final m = model([pie(const [{'name': 'Group A', 'value': 400}])], size: const Size(800, 400));
      expect(paths(rendered(m.pies.single.sectors!)), ['M 285,205 A 80,80,0, 1,0, 285,205.0014 L 205,205 Z']);
    });

    test('4 equal sectors', () {
      final m = model([
        pie(const [
          {'name': 'Group A', 'value': 100},
          {'name': 'Group B', 'value': 100},
          {'name': 'Group C', 'value': 100},
          {'name': 'Group D', 'value': 100},
        ])
      ], size: const Size(800, 400));
      expect(angles(rendered(m.pies.single.sectors!)), [a(0, 90), a(90, 180), a(180, 270), a(270, 0)]);
    });

    test('minAngle does not shift segments already above it (#6814)', () {
      final m = model([
        pie(const [
          {'name': 'A', 'value': 300},
          {'name': 'B', 'value': 30},
          {'name': 'C', 'value': 20},
          {'name': 'D', 'value': 10},
        ], minAngle: 9)
      ], size: const Size(800, 400));
      expect(angles(rendered(m.pies.single.sectors!)), [a(0, 300), a(300, 330), a(330, 350), a(350, 0)]);
    });

    const sparseData = [
      {'name': 'A', 'value': 1},
      {'name': 'Missing'},
      {'name': 'B', 'value': 1},
    ];

    group('missing values with a function dataKey', () {
      Object? getValue(Object? entry) => (entry as Map)['value'];

      for (final dataKey in <Object>['value', getValue]) {
        test('does not allocate a minimum-angle slice for dataKey ${dataKey is String ? dataKey : 'getValue'}', () {
          final m = model([Pie(data: sparseData, dataKey: dataKey, minAngle: 10, isAnimationActive: false)],
              size: const Size(400, 400));
          expect(angles(rendered(m.pies.single.sectors!)), [a(0, 180), a(180, 0)]);
        });

        test('does not allocate padding for missing data with dataKey ${dataKey is String ? dataKey : 'getValue'}', () {
          final m = model([Pie(data: sparseData, dataKey: dataKey, paddingAngle: 5, isAnimationActive: false)],
              size: const Size(400, 400));
          expect(angles(rendered(m.pies.single.sectors!)), [a(0, 175), a(180, 355)]);
        });
      }
    });

    test('a nameKey function that returns nothing names the sector by its index, like a missing key', () {
      final m = model([Pie(data: sparseData, dataKey: 'value', nameKey: (Object? e) => null, isAnimationActive: false)],
          size: const Size(400, 400));
      expect([for (final s in m.pies.single.sectors!) s.name], [0, 1, 2]);
    });

    test('minAngle widens the small sectors', () {
      final m = model([
        pie(const [
          {'value': 1000},
          {'value': 1},
        ], minAngle: 10)
      ], size: const Size(800, 400));
      final s = m.pies.single.sectors!;
      expect(s[1].endAngle - s[1].startAngle, closeTo(10 + 1 / 1001 * 340, 1e-9));
    });

    group('null values', () {
      const nullData = [
        {'name': 'A', 'value': 1},
        {'name': 'Missing', 'value': null},
        {'name': 'B', 'value': 1},
      ];
      Object? getValue(Object? e) => (e as Map)['value'];
      List<({double startAngle, double endAngle})> pieAngles(Object dataKey,
              {double minAngle = 0, double paddingAngle = 0}) =>
          angles(rendered(model([
            Pie(data: nullData, dataKey: dataKey, minAngle: minAngle, paddingAngle: paddingAngle),
          ], size: const Size(400, 400)).pies.single.sectors!));

      for (final dataKey in <Object>['value', getValue]) {
        test('no minimum-angle slice for a null value (dataKey $dataKey)', () {
          expect(pieAngles(dataKey, minAngle: 10), [a(0, 180), a(180, 0)]);
        });
        test('no padding for a null value (dataKey $dataKey)', () {
          expect(pieAngles(dataKey, paddingAngle: 5), [a(0, 175), a(180, 355)]);
        });
      }
    });

    group('zero values at the start with paddingAngle', () {
      const dataStartingWithZero = [
        {'name': 'Zero', 'value': 0},
        {'name': 'A', 'value': 1},
        {'name': 'B', 'value': 1},
      ];
      test('keeps a half pie between startAngle and endAngle', () {
        final m = model(const [
          Pie(data: dataStartingWithZero, startAngle: 180, endAngle: 0, paddingAngle: 10),
        ], size: const Size(400, 400));
        expect(angles(rendered(m.pies.single.sectors!)), [a(180, 95), a(85, 0)]);
      });
      test('starts a full pie at startAngle', () {
        final m = model(const [Pie(data: dataStartingWithZero, paddingAngle: 10)], size: const Size(400, 400));
        expect(angles(rendered(m.pies.single.sectors!)), [a(0, 170), a(180, 350)]);
      });
    });

    test('6 sectors', () {
      final m = model([pie(groupData)], size: const Size(800, 400));
      expect(paths(rendered(m.pies.single.sectors!)), [
        'M 285,205 A 80,80,0, 0,0, 202.3541,125.0438 L 205,205 Z',
        'M 202.3541,125.0438 A 80,80,0, 0,0, 129.4422,178.7128 L 205,205 Z',
        'M 129.4422,178.7128 A 80,80,0, 0,0, 133.5708,241.026 L 205,205 Z',
        'M 133.5708,241.026 A 80,80,0, 0,0, 181.2263,281.3859 L 205,205 Z',
        'M 181.2263,281.3859 A 80,80,0, 0,0, 263.1063,259.9878 L 205,205 Z',
        'M 263.1063,259.9878 A 80,80,0, 0,0, 285,205 L 205,205 Z',
      ]);
    });

    test('all values zero: no sectors, legend still lists the entries', () {
      const emptyData = [
        {'name': 'Group A', 'value': 0},
        {'name': 'Group B', 'value': 0},
      ];
      final m = model(const [Pie(dataKey: 'value', data: emptyData, cx: 200, cy: 200, outerRadius: 80, id: 'empty-pie')],
          size: const Size(800, 400));
      expect(m.pies.single.sectors, isNull);
      final legend = pieLegendPayload(m, const Legend());
      expect([for (final p in legend) (p.value, p.color, p.type, p.dataKey)], [
        ('Group A', const Color(0xFF808080), LegendType.rect, 'value'),
        ('Group B', const Color(0xFF808080), LegendType.rect, 'value'),
      ]);
    });

    test('legend payload: Cell fill, then entry fill, then the Pie fill; sorted by value', () {
      final m = model(const [
        Pie(dataKey: 'value', data: [
          {'name': 'b', 'value': 1, 'fill': Color(0xFF00FF00)},
          {'name': 'a', 'value': 1},
          {'name': 'c', 'value': 1},
        ], children: [
          Cell(),
          Cell(fill: Color(0xFF0000FF)),
        ]),
      ]);
      expect([for (final p in pieLegendPayload(m, const Legend())) (p.value, p.color)], [
        ('a', const Color(0xFF0000FF)),
        ('b', const Color(0xFF00FF00)),
        ('c', const Color(0xFF808080)),
      ]);
    });

    test('legend value falls back to the Pie name, then the dataKey', () {
      final m = model(const [
        Pie(dataKey: 'value', name: 'My pie', data: [{'value': 1}]),
        Pie(dataKey: 'value', data: [{'value': 1}]),
      ]);
      expect([for (final p in pieLegendPayload(m, const Legend(itemSorter: null))) p.value], ['My pie', 'value']);
    });
  });

  group('tooltip payload', () {
    test('a sector without a name is named by its index', () {
      final m = model(const [Pie(data: sectorsData, dataKey: 'cy', id: 'cy-pie')], size: const Size(400, 400));
      expect([for (final s in m.pies.single.sectors!) s.tooltipPayload.name], ['A', 'B', 'C', '3', '4']);
      final p = pieTooltipPayload(m, m.pies, 0).single;
      expect((p.name, p.value), ('A', 250));
      // Pie.spec 'should update tooltip state after hovering over a sector'
      expect(m.pies.single.sectors!.first.tooltipPosition.dx, 263.1033255612459);
      expect(m.pies.single.sectors!.first.tooltipPosition.dy, 154.15275032118709);
    });

    test('per-sector fill colors the row', () {
      final m = model(const [
        Pie(dataKey: 'value', fill: Color(0xFF8884D8), data: [
          {'name': 'A', 'value': 100, 'fill': Color(0xFFFF0000)},
          {'name': 'B', 'value': 100, 'fill': Color(0xFF00FF00)},
        ]),
      ]);
      expect(pieTooltipPayload(m, m.pies, 0).single.color, const Color(0xFFFF0000));
    });

    test('an activeShape fill recolors every row', () {
      final m = model(const [
        Pie(dataKey: 'uv', activeShape: SectorStyle(fill: Color(0xFFFF0000)), data: [
          {'name': 'Page A', 'uv': 590},
          {'name': 'Page B', 'uv': 590},
          {'name': 'Page C', 'uv': 868},
        ]),
      ]);
      final p = pieTooltipPayload(m, m.pies, 2).single;
      expect((p.name, p.value, p.color, p.fill), ('Page C', 868, const Color(0xFFFF0000), const Color(0xFFFF0000)));
    });
  });

  group('Pie.animation.spec.tsx', () {
    final smallerData = pageData.sublist(0, 3);
    List<PieSector> sectorsOf(String dataKey, [List<Object?>? data]) => computePolarModel(
        chartName: 'PieChart',
        size: const Size(100, 100),
        data: const [],
        children: [Pie(data: data ?? smallerData, dataKey: dataKey)]).pies.single.sectors!;
    List<PieSector> step(List<PieSector>? prev, List<PieSector> next, double p) =>
        interpolatePieSectors(matchAnimationItems(prev, next, MatchBy.append), tAt(p));

    test('final paths', () {
      expect(paths(rendered(sectorsOf('amt'))), [
        'M 86,50 A 36,36,0, 0,0, 32,18.8231 L 50,50 Z',
        'M 32,18.8231 A 36,36,0, 0,0, 32,81.1769 L 50,50 Z',
        'M 32,81.1769 A 36,36,0, 0,0, 86,50 L 50,50 Z',
      ]);
    });

    test('the entrance renders nothing at progress 0', () {
      expect(paths(step(null, sectorsOf('amt'), 0)), isEmpty);
    });

    test('the entrance sweeps the sectors from the start angle', () {
      final next = sectorsOf('amt');
      expect([for (final p in [0.28, 0.46, 0.64, 0.82]) paths(step(null, next, p))], [
        [
          'M 86,50 A 36,36,0, 0,0, 69.7423,19.8961 L 50,50 Z',
          'M 69.7423,19.8961 A 36,36,0, 0,0, 35.6532,16.9823 L 50,50 Z',
          'M 35.6532,16.9823 A 36,36,0, 0,0, 14.5223,43.8902 L 50,50 Z',
        ],
        [
          'M 86,50 A 36,36,0, 0,0, 49.2784,14.0072 L 50,50 Z',
          'M 49.2784,14.0072 A 36,36,0, 0,0, 14.0289,51.443 L 50,50 Z',
          'M 14.0289,51.443 A 36,36,0, 0,0, 52.1638,85.9349 L 50,50 Z',
        ],
        [
          'M 86,50 A 36,36,0, 0,0, 38.1402,16.0096 L 50,50 Z',
          'M 38.1402,16.0096 A 36,36,0, 0,0, 21.8141,72.3955 L 50,50 Z',
          'M 21.8141,72.3955 A 36,36,0, 0,0, 80.4308,69.2345 L 50,50 Z',
        ],
        [
          'M 86,50 A 36,36,0, 0,0, 33.2853,18.1156 L 50,50 Z',
          'M 33.2853,18.1156 A 36,36,0, 0,0, 29.5212,79.6078 L 50,50 Z',
          'M 29.5212,79.6078 A 36,36,0, 0,0, 85.7312,54.3908 L 50,50 Z',
        ],
      ]);
      expect([for (final p in [0.325, 0.55, 0.775]) angles(step(null, next, p))], [
        [a(0, 67.2973), a(67.2973, 134.5946), a(134.5946, 201.8918)],
        [a(0, 101.7302), a(101.7302, 203.4603), a(203.4603, 305.1906)],
        [a(0, 116.2289), a(116.2289, 232.4579), a(232.4579, 348.6866)],
      ]);
    });

    test('a dataKey change after the entrance animates the angles', () {
      final prev = rendered(sectorsOf('amt'));
      final next = sectorsOf('pv');
      expect([for (final p in [0.4, 0.7]) angles(step(prev, next, p))], [
        [a(0, 108.593), a(108.593, 280.8398), a(280.8398, 0)],
        [a(0, 104.2775), a(104.2775, 296.2907), a(296.2907, 0)],
      ]);
      expect(angles(step(prev, next, 1)), [a(0, 103.2874), a(103.2874, 299.835), a(299.835, 0)]);
    });

    test('a dataKey change mid-entrance continues from the rendered sectors', () {
      final prev = step(null, sectorsOf('amt'), 0.5);
      final next = sectorsOf('pv');
      expect([for (final p in [0.4, 0.7]) angles(step(prev, next, p))], [
        [a(0, 101.0656), a(101.0656, 265.785), a(265.785, 337.4176)],
        [a(0, 102.8729), a(102.8729, 293.4815), a(293.4815, 355.7862)],
      ]);
    });

    test('2 to 3 sectors after the entrance', () {
      final prev = rendered(sectorsOf('amt', smallerData.sublist(0, 2)));
      final next = sectorsOf('amt');
      expect([for (final p in [0.4, 0.7, 1.0]) angles(step(prev, next, p))], [
        [a(0, 139.0477), a(139.0477, 278.0953), a(278.0953, 0.0002)],
        [a(0, 123.5542), a(123.5542, 247.1082), a(247.1082, 0)],
        [a(0, 120), a(120, 240), a(240, 0)],
      ]);
    });

    // PiePaddingAngleAnimation.spec.tsx
    test('the closing gap stays at paddingAngle while a middle value animates to zero', () {
      List<PieSector> sectors(int z, int b) => computePolarModel(
          chartName: 'PieChart',
          size: const Size(100, 100),
          data: const [],
          children: [
            Pie(paddingAngle: 10, data: [
              {'name': 'A', 'value': 40},
              {'name': 'Z', 'value': z},
              {'name': 'B', 'value': b},
            ], children: const [Cell(), Cell(), Cell()]),
          ]).pies.single.sectors!;
      final prev = rendered(sectors(10, 50));
      final next = sectors(0, 60);
      for (final p in [0.1, 0.3, 0.5, 0.7, 0.9, 1.0]) {
        final gap = 360 - angles(step(prev, next, p)).last.endAngle;
        expect(gap, allOf(greaterThan(9.9), lessThanOrEqualTo(10)), reason: 'progress $p');
      }
    });

    test('2 to 3 sectors mid-entrance', () {
      final prev = step(null, sectorsOf('amt', smallerData.sublist(0, 2)), 0.5);
      final next = sectorsOf('amt');
      expect([for (final p in [0.4, 0.7]) angles(step(prev, next, p))], [
        [a(0, 127.7564), a(127.7564, 255.5128), a(255.5128, 337.4176)],
        [a(0, 121.4473), a(121.4473, 242.8946), a(242.8946, 355.7864)],
      ]);
    });
  });
}
