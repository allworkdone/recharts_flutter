// Draws the polar items and axes of RadarChart and RadialBarChart in the z
// layers of src/zIndex/DefaultZIndexes.tsx: PolarGrid (-100), RadialBar
// background (-50), Radar polygon (area, 100), RadialBar sectors (bar, 300),
// PolarAngleAxis and PolarRadiusAxis (axis, 500), Radar dots (scatter, 600),
// the active RadialBar sector (activeBar, 1000), the tooltip cursor
// (cursorLine, 1100), the Radar active dot (activeDot, 1200) and labels
// (2000). Follows PolarGrid.tsx, PolarAngleAxis.tsx, PolarRadiusAxis.tsx,
// Radar.tsx, Polygon.tsx, RadialBar.tsx, RadialBarUtils.tsx, Cursor.tsx and
// ActivePoints.tsx.

import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../components.dart';
import '../core/polar_utils.dart';
import '../engine/polar_axis.dart';
import '../engine/polar_items.dart';
import '../engine/get_ticks.dart' show TickItem;
import '../engine/polar_scene.dart';
import '../polar_axes.dart';
import '../polar_components.dart';
import '../util.dart';
import 'label.dart';
import 'painter.dart' show paintDot;
import 'polar_painter.dart';
import 'sector.dart';
import 'shapes.dart';
import 'svg_text.dart';

const _eps = 1e-5;
final _cos45 = math.cos(degreeToRadian(45));

void paintPolarBelowArea(Canvas canvas, PolarFrame frame, PolarHoverState? h) {
  final scene = frame.model.scene;
  if (scene == null) return;
  for (final g in scene.grids) {
    _paintGrid(canvas, scene, g);
  }
  for (final bar in scene.radialBars) {
    if (!bar.settings.hide) _paintRadialBarBackground(canvas, bar);
  }
}

void paintPolarAboveArea(Canvas canvas, PolarFrame frame, PolarHoverState? h) {
  final scene = frame.model.scene;
  if (scene == null) return;
  final stepped = <String, List<RadarPoint>>{};
  for (final r in scene.radars) {
    if (r.settings.hide || r.points == null) continue;
    stepped[r.id] = _paintRadarPolygon(canvas, frame, r);
  }
  for (final bar in scene.radialBars) {
    if (!bar.settings.hide) _paintRadialBar(canvas, frame, bar, h, active: false);
  }
  for (final a in scene.angleAxisElements) {
    _paintAngleAxis(canvas, frame, scene, a);
  }
  for (final a in scene.radiusAxisElements) {
    _paintRadiusAxis(canvas, frame, scene, a);
  }
  for (final r in scene.radars) {
    final points = stepped[r.id];
    if (points != null) _paintRadarDots(canvas, r, points);
  }
  for (final bar in scene.radialBars) {
    if (!bar.settings.hide) _paintRadialBar(canvas, frame, bar, h, active: true);
  }
  _paintCursor(canvas, frame, scene, h);
  for (final r in scene.radars) {
    if (!r.settings.hide) _paintRadarActiveDot(canvas, r, h);
  }
}

void paintPolarSceneLabels(Canvas canvas, PolarFrame frame) {
  final scene = frame.model.scene;
  if (scene == null) return;
  for (final r in scene.radars) {
    if (r.settings.hide || r.points == null) continue;
    // Labels show once the Radar stops animating.
    if (frame.radarAnimators[r.id]?.isAnimating ?? false) continue;
    for (final list in _labelLists(r.settings.label, r.settings.children)) {
      for (final (i, p) in r.points!.indexed) {
        final entry = LabelListEntry(value: p.value ?? '', payload: p.payload, viewBox: Rect.fromLTWH(p.x, p.y, 0, 0));
        paintLabel(canvas, labelOfEntry(list, entry, i), entry.viewBox,
            index: i, baseStyle: frame.textStyle, scaler: frame.textScaler);
      }
    }
  }
  for (final bar in scene.radialBars) {
    if (bar.settings.hide || (frame.radialBarAnimators[bar.id]?.isAnimating ?? false)) continue;
    for (final list in _labelLists(bar.settings.label, bar.settings.children)) {
      for (final (i, s) in bar.sectors.indexed) {
        final viewBox = PolarViewBox(
            cx: s.cx,
            cy: s.cy,
            innerRadius: s.innerRadius,
            outerRadius: s.outerRadius,
            startAngle: s.startAngle,
            endAngle: s.endAngle);
        final fill = s.props['fill'];
        final entry = LabelListEntry(value: s.value, payload: s.entry, viewBox: Rect.zero, fill: fill is Color ? fill : null);
        paintPolarLabel(canvas, labelOfEntry(list, entry, i), viewBox,
            index: i, baseStyle: frame.textStyle, scaler: frame.textScaler, boxes: frame.labelBoxes);
      }
    }
  }
  for (final a in scene.radiusAxisElements) {
    _paintRadiusAxisLabel(canvas, frame, scene, a);
  }
}

/// `LabelListFromLabelProp` then the `LabelList` children.
List<LabelList> _labelLists(Object label, List<RechartsElement> children) {
  final fromProp = switch (label) {
    true => const LabelList(),
    LabelList l => l,
    LabelPainter p => LabelList(content: p),
    _ => null,
  };
  return [?fromProp, ...children.whereType<LabelList>()];
}

// ---------------------------------------------------------------- PolarGrid

Path _polygonPath(double radius, double cx, double cy, List<double> polarAngles) {
  final path = Path();
  for (final (i, angle) in polarAngles.indexed) {
    final p = polarToCartesian(cx, cy, radius, angle);
    i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
  }
  return path..close();
}

void _paintGrid(Canvas canvas, PolarScene scene, PolarGrid g) {
  final angleTicks = scene.angleAxes[g.angleAxisId]?.ticks;
  final radiusTicks = scene.radiusAxes[g.radiusAxisId]?.ticks;
  final polarAngles = g.polarAngles ?? (angleTicks == null ? null : [for (final t in angleTicks) t.coordinate]);
  final polarRadius = g.polarRadius ?? (radiusTicks == null ? null : [for (final t in radiusTicks) t.coordinate]);
  if (polarAngles == null || polarRadius == null) return;
  final vb = scene.viewBox;
  if (vb.outerRadius <= 0) return;
  final stroke = g.stroke;
  Paint? strokeOf() => stroke == null || g.strokeWidth <= 0
      ? null
      : strokePaint(stroke, g.strokeWidth, opacity: g.strokeOpacity ?? 1);
  void stroked(Path path) {
    final paint = strokeOf();
    if (paint != null) drawStroke(canvas, path, paint, g.strokeDasharray);
  }

  Path ring(double radius) => g.gridType == PolarGridType.circle
      ? (Path()..addOval(Rect.fromCircle(center: Offset(vb.cx, vb.cy), radius: radius)))
      : _polygonPath(radius, vb.cx, vb.cy, polarAngles);

  if (polarRadius.isNotEmpty) {
    // The background is its own first child so it never covers the smaller figures' strokes.
    if (g.fill != null) {
      final path = ring(polarRadius.reduce(math.max));
      canvas.drawPath(path, fillPaint(g.fill!, opacity: g.fillOpacity ?? 1));
      stroked(path);
    }
    for (final radius in polarRadius) {
      stroked(ring(radius));
    }
  }
  if (g.radialLines && polarAngles.isNotEmpty) {
    for (final angle in polarAngles) {
      final a = polarToCartesian(vb.cx, vb.cy, vb.innerRadius, angle);
      final b = polarToCartesian(vb.cx, vb.cy, vb.outerRadius, angle);
      stroked(Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy));
    }
  }
}

// ---------------------------------------------------------------- axes

TextAnchor angleTickTextAnchor(double coordinate, PolarAngleOrientation orientation) {
  final cos = math.cos(degreeToRadian(-coordinate));
  final outer = orientation == PolarAngleOrientation.outer;
  if (cos > _eps) return outer ? TextAnchor.start : TextAnchor.end;
  if (cos < -_eps) return outer ? TextAnchor.end : TextAnchor.start;
  return TextAnchor.middle;
}

TextVerticalAnchor _angleTickVerticalAnchor(double coordinate) {
  final cos = math.cos(degreeToRadian(-coordinate)), sin = math.sin(degreeToRadian(-coordinate));
  // The top and bottom sectors: 90±45deg and 270±45deg.
  if (cos.abs() <= _cos45) return sin > 0 ? TextVerticalAnchor.start : TextVerticalAnchor.end;
  return TextVerticalAnchor.middle;
}

void _strokeStyled(Canvas canvas, Path path, Color? stroke, double? width, Object? override, [List<double>? dash]) {
  final style = override is SvgStyle ? override : null;
  final color = style?.stroke ?? stroke;
  final w = style?.strokeWidth ?? width ?? 1;
  if (color == null || w <= 0) return;
  drawStroke(canvas, path, strokePaint(color, w, opacity: style?.strokeOpacity ?? 1), style?.strokeDasharray ?? dash);
}

/// One tick of a [PolarAngleAxis]: its line from the axis to [p2], where the text is anchored.
typedef AngleTickGeometry = ({
  TickItem tick,
  Offset p1,
  Offset p2,
  TextAnchor textAnchor,
  TextVerticalAnchor verticalAnchor
});

/// The ticks PolarAngleAxis draws (`selectPolarAngleAxisTicks`), with `getTickLineCoord`,
/// `getTickTextAnchor` and `getTickTextVerticalAnchor`.
List<AngleTickGeometry> angleAxisTickGeometry(PolarScene scene, PolarAngleAxis a) {
  final runtime = scene.angleAxes[a.angleAxisId];
  final allTicks = runtime?.ticks;
  if (runtime == null || runtime.scale == null || allTicks == null || allTicks.isEmpty) return const [];
  final vb = scene.viewBox;
  final tickSize = a.tickSize == 0 ? 8.0 : a.tickSize;
  return [
    for (final t in dedupeAngleTicks(allTicks))
      (
        tick: t,
        p1: polarToCartesian(vb.cx, vb.cy, vb.outerRadius, t.coordinate),
        p2: polarToCartesian(vb.cx, vb.cy,
            vb.outerRadius + (a.orientation == PolarAngleOrientation.inner ? -1 : 1) * tickSize, t.coordinate),
        textAnchor: angleTickTextAnchor(t.coordinate, a.orientation),
        verticalAnchor: _angleTickVerticalAnchor(t.coordinate),
      ),
  ];
}

void _paintAngleAxis(Canvas canvas, PolarFrame frame, PolarScene scene, PolarAngleAxis a) {
  final geometry = angleAxisTickGeometry(scene, a);
  if (geometry.isEmpty) return;
  final ticks = [for (final g in geometry) g.tick];
  final vb = scene.viewBox;
  final radius = vb.outerRadius;
  if (a.axisLine != false) {
    final path = a.axisLineType == PolarAxisLineType.circle
        ? (Path()..addOval(Rect.fromCircle(center: Offset(vb.cx, vb.cy), radius: radius)))
        : _polygonPath(radius, vb.cx, vb.cy, [for (final t in ticks) t.coordinate]);
    // Polygon closes through getSinglePolygonPath; its points are the ticks at the radius.
    _strokeStyled(canvas, path, a.stroke, a.strokeWidth, a.axisLine);
  }
  final textFill = a.stroke ?? const Color(0xFF808080);
  var base = frame.textStyle;
  if (a.fontSize != null) base = base.copyWith(fontSize: a.fontSize);
  for (final (i, g) in geometry.indexed) {
    final t = g.tick, p1 = g.p1, p2 = g.p2;
    if (a.tickLine != false) {
      _strokeStyled(
          canvas,
          Path()
            ..moveTo(p1.dx, p1.dy)
            ..lineTo(p2.dx, p2.dy),
          a.stroke,
          a.strokeWidth,
          a.tickLine);
    }
    if (a.tick == false) continue;
    final text = a.tickFormatter != null ? a.tickFormatter!(t.value, i) : jsString(t.value);
    final textAnchor = g.textAnchor;
    final verticalAnchor = g.verticalAnchor;
    var style = base.copyWith(color: textFill);
    if (a.tick is TextStyle) style = style.merge(a.tick as TextStyle);
    if (a.tick is TickPainter) {
      (a.tick as TickPainter)(
          canvas,
          TickProps(
            x: p2.dx,
            y: p2.dy,
            index: i,
            value: t.value,
            text: text,
            textAnchor: textAnchor,
            verticalAnchor: verticalAnchor,
            angle: 0,
            fill: textFill,
            style: style,
            visibleTicksCount: ticks.length,
          ));
      continue;
    }
    paintSvgText(canvas, text, p2.dx, p2.dy,
        style: style, textAnchor: textAnchor, verticalAnchor: verticalAnchor, scaler: frame.textScaler);
  }
}

TextAnchor _radiusTickAnchor(PolarRadiusOrientation o) => switch (o) {
      PolarRadiusOrientation.left => TextAnchor.end,
      PolarRadiusOrientation.right => TextAnchor.start,
      PolarRadiusOrientation.middle => TextAnchor.middle,
    };

/// Where PolarRadiusAxis puts each tick's text (`getTickValueCoord`).
List<(TickItem, Offset)> radiusAxisTickPositions(PolarScene scene, PolarRadiusAxis a) {
  final runtime = scene.radiusAxes[a.radiusAxisId];
  final ticks = runtime?.ticks;
  if (runtime == null || runtime.scale == null || ticks == null) return const [];
  final vb = scene.viewBox;
  return [for (final t in ticks) (t, polarToCartesian(vb.cx, vb.cy, t.coordinate, a.angle))];
}

void _paintRadiusAxis(Canvas canvas, PolarFrame frame, PolarScene scene, PolarRadiusAxis a) {
  final runtime = scene.radiusAxes[a.radiusAxisId];
  final ticks = runtime?.ticks;
  if (runtime == null || runtime.scale == null || ticks == null || ticks.isEmpty) return;
  final vb = scene.viewBox;
  if (a.axisLine != false) {
    var lo = double.infinity, hi = double.negativeInfinity;
    for (final t in ticks) {
      lo = math.min(lo, t.coordinate);
      hi = math.max(hi, t.coordinate);
    }
    final p0 = polarToCartesian(vb.cx, vb.cy, lo, a.angle), p1 = polarToCartesian(vb.cx, vb.cy, hi, a.angle);
    _strokeStyled(
        canvas,
        Path()
          ..moveTo(p0.dx, p0.dy)
          ..lineTo(p1.dx, p1.dy),
        a.stroke,
        null,
        a.axisLine);
  }
  if (a.tick == false) return;
  final textAnchor = _radiusTickAnchor(a.orientation);
  var base = frame.textStyle;
  if (a.fontSize != null) base = base.copyWith(fontSize: a.fontSize);
  final fill = a.stroke ?? const Color(0xFF808080);
  for (final (i, t) in ticks.indexed) {
    final coord = polarToCartesian(vb.cx, vb.cy, t.coordinate, a.angle);
    final text = a.tickFormatter != null ? a.tickFormatter!(t.value, i) : jsString(t.value);
    var style = base.copyWith(color: fill);
    if (a.tick is TextStyle) style = style.merge(a.tick as TextStyle);
    if (a.tick is TickPainter) {
      (a.tick as TickPainter)(
          canvas,
          TickProps(
            x: coord.dx,
            y: coord.dy,
            index: i,
            value: t.value,
            text: text,
            textAnchor: textAnchor,
            verticalAnchor: TextVerticalAnchor.end,
            angle: 90 - a.angle,
            fill: fill,
            style: style,
            visibleTicksCount: ticks.length,
          ));
      continue;
    }
    // transform: rotate(90 - angle, x, y)
    paintSvgText(canvas, text, coord.dx, coord.dy,
        style: style, textAnchor: textAnchor, angle: 90 - a.angle, scaler: frame.textScaler);
  }
}

/// `PolarLabelFromLabelProp` inside the ticks' polar view box.
void _paintRadiusAxisLabel(Canvas canvas, PolarFrame frame, PolarScene scene, PolarRadiusAxis a) {
  final label = parseLabel(a.label);
  final ticks = scene.radiusAxes[a.radiusAxisId]?.ticks;
  if (label == null || ticks == null || ticks.isEmpty || scene.radiusAxes[a.radiusAxisId]?.scale == null) return;
  final vb = scene.viewBox;
  var maxTick = ticks.first, minTick = ticks.first;
  for (final t in ticks) {
    if ((t.coordinate.isNaN ? 0 : t.coordinate) > (maxTick.coordinate.isNaN ? 0 : maxTick.coordinate)) maxTick = t;
    if ((t.coordinate.isNaN ? 0 : t.coordinate) < (minTick.coordinate.isNaN ? 0 : minTick.coordinate)) minTick = t;
  }
  final viewBox = PolarViewBox(
      cx: vb.cx,
      cy: vb.cy,
      startAngle: a.angle,
      endAngle: a.angle,
      innerRadius: minTick.coordinate == 0 ? 0 : minTick.coordinate,
      outerRadius: maxTick.coordinate == 0 ? 0 : maxTick.coordinate);
  paintPolarLabel(canvas, label, viewBox, baseStyle: frame.textStyle, scaler: frame.textScaler, boxes: frame.labelBoxes);
}

// ---------------------------------------------------------------- Radar

List<List<Offset>> _segments(List<Offset?> points, bool connectNulls) {
  var segments = <List<Offset>>[[]];
  bool valid(Offset? p) => p != null && p.dx.isFinite && p.dy.isFinite;
  for (final p in points) {
    if (valid(p)) {
      segments.last.add(p!);
    } else if (segments.last.isNotEmpty) {
      segments.add([]);
    }
  }
  if (points.isNotEmpty && valid(points.first)) segments.last.add(points.first!);
  if (segments.last.isEmpty) segments = segments.sublist(0, segments.length - 1);
  if (connectNulls) segments = [segments.expand((s) => s).toList()];
  return segments;
}

Path _segmentsPath(List<List<Offset>> segments) {
  final path = Path();
  for (final seg in segments) {
    for (final (i, p) in seg.indexed) {
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
  }
  if (segments.length == 1) path.close();
  return path;
}

/// `getRanglePath`: the outer path (unclosed) continued into the reversed baseline.
Path _rangePath(List<List<Offset>> outer, List<List<Offset>> base) {
  final path = Path();
  for (final seg in outer) {
    for (final (i, p) in seg.indexed) {
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
  }
  var first = true;
  for (final seg in base) {
    for (final (i, p) in seg.indexed) {
      if (i == 0 && !first) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    first = false;
  }
  if (base.length == 1) path.close();
  return path;
}

List<Offset?> _offsets(List<RadarPoint> points) => [for (final p in points) Offset(p.x, p.y)];

/// StaticPolygon over the animation step; returns the step's points for the dots.
List<RadarPoint> _paintRadarPolygon(Canvas canvas, PolarFrame frame, RadarModel r) {
  final radar = r.settings;
  final composed = r.composed!;
  final points = frame.radarAnimators[r.id]?.step(interpolateRadarPoints) ?? composed.points;
  final baseLine = composed.isRange
      ? (frame.radarBaseLineAnimators[r.id]?.step(interpolateRadarPoints) ?? composed.baseLinePoints)
      : null;
  if (points.isEmpty) return points;
  if (radar.shape != null) {
    radar.shape!(
        canvas,
        RadarShapeProps(
            points: [for (final p in points) Offset(p.x, p.y)],
            baseLinePoints: [for (final p in baseLine ?? const <RadarPoint>[]) Offset(p.x, p.y)],
            fill: radar.fill,
            stroke: radar.stroke));
    return points;
  }
  final stroke = radar.stroke;
  final hasStroke = stroke != null;
  final width = radar.strokeWidth ?? 1;
  Paint? strokeOf() => hasStroke && width > 0 ? strokePaint(stroke, width, opacity: radar.strokeOpacity ?? 1) : null;
  void strokePath(Path path) {
    final paint = strokeOf();
    if (paint != null) drawStroke(canvas, path, paint, radar.strokeDasharray);
  }

  void fillPath(Path path, bool closed) {
    if (closed && radar.fill != null) canvas.drawPath(path, fillPaint(radar.fill!, opacity: radar.fillOpacity ?? 1));
  }

  final outer = _segments(_offsets(points), radar.connectNulls);
  if (baseLine != null && baseLine.isNotEmpty) {
    final base = _segments(_offsets(baseLine), radar.connectNulls);
    final reversed = _segments(_offsets(baseLine.reversed.toList()), radar.connectNulls);
    final range = _rangePath(outer, reversed);
    fillPath(range, reversed.length == 1);
    if (hasStroke) {
      strokePath(_segmentsPath(outer));
      strokePath(_segmentsPath(base));
    }
    return points;
  }
  final path = _segmentsPath(outer);
  fillPath(path, outer.length == 1);
  strokePath(path);
  return points;
}

void _paintRadarDots(Canvas canvas, RadarModel r, List<RadarPoint> points) {
  final radar = r.settings;
  final dot = radar.dot;
  if (!(dot != false || points.length == 1)) return;
  final style = dot is SvgStyle ? dot : null;
  for (final (i, p) in points.indexed) {
    final props = DotProps(
      cx: p.x,
      cy: p.y,
      r: style?.r ?? 3,
      index: i,
      value: p.value,
      payload: p.payload,
      dataKey: radar.dataKey,
      fill: style?.fill ?? radar.fill,
      stroke: style?.stroke ?? radar.stroke,
      strokeWidth: style?.strokeWidth ?? radar.strokeWidth ?? 1,
    );
    if (dot is DotPainter) {
      dot(canvas, props);
    } else {
      paintDot(canvas, props, style?.strokeDasharray ?? radar.strokeDasharray,
          fill: style?.fill ?? radar.fill, fillOpacity: style?.fillOpacity ?? radar.fillOpacity ?? 1);
    }
  }
}

void _paintRadarActiveDot(Canvas canvas, RadarModel r, PolarHoverState? h) {
  final radar = r.settings, activeDot = radar.activeDot, points = r.points;
  if (h == null || h.activeDataPoints.isEmpty || points == null || activeDot == false) return;
  final p = points.where((p) => h.activeDataPoints.any((d) => identical(d, p.payload))).firstOrNull;
  if (p == null) return;
  final style = activeDot is SvgStyle ? activeDot : null;
  final props = DotProps(
    cx: p.x,
    cy: p.y,
    r: style?.r ?? 4,
    index: h.activeIndex ?? 0,
    value: p.value,
    payload: p.payload,
    dataKey: radar.dataKey,
    fill: style?.fill ?? legendItemColor(radar.stroke, radar.fill),
    stroke: style?.stroke ?? const Color(0xFFFFFFFF),
    strokeWidth: style?.strokeWidth ?? 2,
  );
  if (activeDot is DotPainter) {
    activeDot(canvas, props);
  } else {
    paintDot(canvas, props, style?.strokeDasharray);
  }
}

// ---------------------------------------------------------------- RadialBar

/// Sector props with an object option merged over them (`mergeShapeProps`).
SectorGeometry radialBarGeometry(RadialBar bar, RadialBarSector s, [SectorStyle? o]) => SectorGeometry(
      cx: o?.cx ?? s.cx,
      cy: o?.cy ?? s.cy,
      innerRadius: o?.innerRadius ?? s.innerRadius,
      outerRadius: o?.outerRadius ?? s.outerRadius,
      startAngle: o?.startAngle ?? s.startAngle,
      endAngle: o?.endAngle ?? s.endAngle,
      cornerRadius: o?.cornerRadius ?? parseCornerRadius(bar.cornerRadius) ?? 0,
      forceCornerRadius: o?.forceCornerRadius ?? bar.forceCornerRadius,
      cornerIsExternal: o?.cornerIsExternal ?? bar.cornerIsExternal,
    );

/// The sectors a RadialBar shows this frame (mid-animation they are interpolated).
List<RadialBarSector> currentRadialBarSectors(PolarFrame frame, RadialBarModel m) =>
    frame.radialBarAnimators[m.id]?.peek(interpolateRadialBarSectors) ?? m.sectors;

/// The path a sector paints and hit tests; null when it renders nothing.
Path? radialBarPath(RadialBar bar, RadialBarSector s, Object? option) =>
    s.isFinite ? sectorPath(radialBarGeometry(bar, s, option is SectorStyle ? option : null)) : null;

/// `activeShape` applies to the sector at the active tooltip index.
bool isActiveRadialBarSector(RadialBar bar, PolarHoverState? h, int index) =>
    bar.activeShape != null && bar.activeShape != false && h?.activeIndex == index;

void _paintRadialBarBackground(Canvas canvas, RadialBarModel m) {
  final bar = m.settings;
  final background = bar.background;
  if (background == false) return;
  final style = background is SectorStyle ? background : null;
  for (final s in m.sectors) {
    final g = s.background;
    if (g == null) continue;
    final path = sectorPath(SectorGeometry(
      cx: style?.cx ?? g.cx,
      cy: style?.cy ?? g.cy,
      innerRadius: style?.innerRadius ?? g.innerRadius,
      outerRadius: style?.outerRadius ?? g.outerRadius,
      startAngle: style?.startAngle ?? g.startAngle,
      endAngle: style?.endAngle ?? g.endAngle,
      cornerRadius: style?.cornerRadius ?? g.cornerRadius,
      forceCornerRadius: style?.forceCornerRadius ?? false,
      cornerIsExternal: style?.cornerIsExternal ?? false,
    ));
    if (path == null) continue;
    final fill = style?.fill ?? const Color(0xFFEEEEEE);
    canvas.drawPath(path, fillPaint(fill, opacity: style?.fillOpacity ?? (s.props['fillOpacity'] as num?)?.toDouble() ?? 1));
    final stroke = style?.stroke ?? (s.props['stroke'] is Color ? s.props['stroke'] as Color : null);
    final width = style?.strokeWidth ?? (s.props['strokeWidth'] as num?)?.toDouble() ?? 1;
    if (stroke != null && width > 0) {
      drawStroke(canvas, path, strokePaint(stroke, width, opacity: style?.strokeOpacity ?? 1), style?.strokeDasharray);
    }
  }
}

void _paintRadialBar(Canvas canvas, PolarFrame frame, RadialBarModel m, PolarHoverState? h, {required bool active}) {
  final bar = m.settings;
  final sectors = frame.radialBarAnimators[m.id]?.step(interpolateRadialBarSectors) ?? m.sectors;
  for (final (i, s) in sectors.indexed) {
    final isActive = isActiveRadialBarSector(bar, h, i);
    if (isActive != active) continue;
    final option = isActive ? bar.activeShape : bar.shape;
    if (option is RadialBarShapePainter) {
      option(canvas, RadialBarShapeProps(sector: s, index: i, isActive: isActive));
      continue;
    }
    final style = option is SectorStyle ? option : null;
    final path = radialBarPath(bar, s, style);
    if (path == null) continue;
    final fill = style?.fill ?? s.fill;
    if (fill != null) canvas.drawPath(path, fillPaint(fill, opacity: style?.fillOpacity ?? s.fillOpacity ?? 1));
    final stroke = style?.stroke ?? s.stroke;
    final width = style?.strokeWidth ?? s.strokeWidth ?? 1;
    if (stroke != null && width > 0) {
      drawStroke(canvas, path, strokePaint(stroke, width, opacity: style?.strokeOpacity ?? s.strokeOpacity ?? 1),
          style?.strokeDasharray);
    }
  }
}

// ---------------------------------------------------------------- cursor

/// Cursor.tsx for a polar chart: a Sector at the radius (radial layout) or a
/// line across the radii (centric layout), both `#ccc`.
void _paintCursor(Canvas canvas, PolarFrame frame, PolarScene scene, PolarHoverState? h) {
  final tooltip = frame.model.tooltipSettings;
  final c = h?.polarCoordinate;
  if (h == null || tooltip == null || !h.cursorVisible || c == null || tooltip.cursor == false) return;
  final style = tooltip.cursor is SvgStyle ? tooltip.cursor as SvgStyle : null;
  final vb = c.viewBox;
  final Path? path;
  if (scene.layout == PolarLayout.radial) {
    path = sectorPath(SectorGeometry(
        cx: vb.cx, cy: vb.cy, innerRadius: c.radius, outerRadius: c.radius, startAngle: vb.startAngle, endAngle: vb.endAngle));
  } else {
    final a = polarToCartesian(vb.cx, vb.cy, vb.innerRadius, c.angle);
    final b = polarToCartesian(vb.cx, vb.cy, vb.outerRadius, c.angle);
    path = Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy);
  }
  if (path == null) return;
  if (style?.fill != null) canvas.drawPath(path, fillPaint(style!.fill!, opacity: style.fillOpacity ?? 1));
  drawStroke(canvas, path, strokePaint(style?.stroke ?? const Color(0xFFCCCCCC), style?.strokeWidth ?? 1), style?.strokeDasharray);
}
