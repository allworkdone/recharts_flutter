# recharts_flutter

Recharts 3.11.0-canary.9 ported to Flutter, with Recharts' own layout, tick, animation and
interaction logic, drawn with `CustomPainter` and no chart dependencies.

3.11 is not a stable Recharts release yet. Its themes, fill objects (gradient and
pattern `fill` props) and zoom are not ported yet. Its other fixes and features
are, apart from a few small gaps named in the commit messages, so charts that
don't use those three render as canary.9 does.

| Family | Charts | Components |
|---|---|---|
| Cartesian | `LineChart`, `BarChart`, `AreaChart`, `ComposedChart`, `ScatterChart`, `FunnelChart` | `XAxis`, `YAxis`, `ZAxis`, `CartesianGrid`, `Line`, `Bar`, `Area`, `Scatter`, `Funnel`, `ErrorBar`, `ReferenceLine`, `ReferenceArea`, `ReferenceDot`, `Brush` |
| Polar | `PieChart`, `RadarChart`, `RadialBarChart` | `Pie`, `Radar`, `RadialBar`, `PolarGrid`, `PolarAngleAxis`, `PolarRadiusAxis` |
| Hierarchy and flow | `Treemap`, `Sankey`, `SunburstChart` | |
| Shared | `ResponsiveContainer` | `Tooltip`, `Legend`, `Label`, `LabelList`, `Cell` |

Charts with the same `syncId` share their tooltip (and Brush range), across cartesian
and polar charts alike.

Children are configuration objects named exactly like Recharts components and
props, with Recharts' defaults:

```dart
import 'package:flutter/material.dart' hide Tooltip; // Recharts' Tooltip clashes with material's
import 'package:recharts_flutter/recharts_flutter.dart';

final chart = LineChart(
  width: 500,
  height: 300,
  data: const [
    {'name': 'Page A', 'uv': 4000, 'pv': 2400},
    {'name': 'Page B', 'uv': 3000, 'pv': 1398},
    {'name': 'Page C', 'uv': 2000, 'pv': 9800},
  ],
  margin: const Margin(top: 5, right: 30, left: 20, bottom: 5),
  children: const [
    CartesianGrid(strokeDasharray: [3, 3]),
    XAxis(dataKey: 'name'),
    YAxis(),
    Tooltip(),
    Legend(),
    Line(type: CurveType.monotone, dataKey: 'pv', stroke: Color(0xFF8884D8)),
    Line(type: CurveType.monotone, dataKey: 'uv', stroke: Color(0xFF82CA9D)),
  ],
);
```

Wrap a chart in `ResponsiveContainer(width: '100%', aspect: 2, child: ...)`, or
omit `width`/`height` to fill the incoming constraints.

Where Dart's types differ from Recharts' JavaScript props (colors are `Color`,
`strokeDasharray` is `List<double>`, `isAnimationActive: null` means `'auto'`,
`interval` is an `AxisInterval`, ...) the field's doc comment says so. Where
Recharts takes `fill="url(#gradient)"`, `Area` and `Bar` take a Flutter
`Gradient`, laid over the shape's bounding box like SVG's default
`objectBoundingBox` units.

Text inherits `DefaultTextStyle` the way SVG text inherits CSS; Recharts'
presentation attributes (for example the `#666` tick fill) are applied on top.
`isAnimationActive: 'auto'` follows `MediaQuery.disableAnimations`.

The example app renders the parity fixtures in `example/assets/parity/fixtures`
(`?fixture=<name>` on the web build renders one fixture alone for pixel diffs).
`tool/parity/run.sh [filter] [--anim]` renders every fixture with real Recharts in Chrome
and with the Flutter web build, then writes a pixel-diff report to
`tool/parity/out/report.html`.

Ported code keeps the license notices of Recharts, d3 and decimal.js-light; see
`THIRD_PARTY_NOTICES.md`.
