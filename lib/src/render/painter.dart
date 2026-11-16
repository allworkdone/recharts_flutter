// Draws the SVG part of a cartesian chart, split into layers that follow
// Recharts' DefaultZIndexes (src/zIndex/DefaultZIndexes.tsx):
//   background: grid (-100), bar background (-50)
//   cursorBelow: BarChart cursor rectangle (200)
//   main: areas (100), bars (300), lines + reference lines + error bars (400),
//     axis lines (500), dots and scatters (600)
//   activeBar: Bar `activeBar` (1000)
//   overlay: cursor line or cross (1100), active dots and scatter points (1200)
//   labels: tick labels, Label and LabelList (2000)
// Geometry follows CartesianAxis.tsx (getTickLineCoord, AxisLine),
// CartesianGrid.tsx, Line.tsx/LineDrawShape.tsx, Area.tsx/AreaRevealShape.tsx,
// Dots.tsx, ActivePoints.tsx,
// Bar.tsx/Rectangle.tsx (BarRectangleWithActiveState), ActiveShapeUtils.tsx,
// Scatter.tsx (ScatterLine, ScatterPoint) with ScatterUtils.tsx and Symbols.tsx,
// ErrorBar.tsx, ReferenceLine.tsx, Cursor.tsx and Cross.tsx.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../animation.dart';
import '../components.dart';
import '../core/curve.dart';
import '../core/symbols.dart';
import '../engine/axis.dart';
import '../engine/get_ticks.dart';
import '../engine/funnel.dart';
import '../engine/model.dart';
import '../util.dart';
import 'label.dart';
import 'shapes.dart';
import 'svg_text.dart';
import '../css_color.dart';

/// The trapezoids to draw now (the animation's step, else the target ones).
List<FunnelTrapezoid>? currentTrapezoids(ChartFrame frame, FunnelModel f, {bool record = false}) {
  final a = frame.funnelAnimators[f.id];
  if (a == null) return f.trapezoids;
  return record ? a.step(interpolateFunnelTrapezoids) : a.peek(interpolateFunnelTrapezoids);
}

enum ChartLayer { background, cursorBelow, main, activeBar, overlay, labels }

/// What the overlay needs from the tooltip state.
class HoverState {
  const HoverState({
    this.cursorVisible = false,
    this.coordinate,
    this.activeDataPoints = const [],
    this.activeIndex,
    this.activeDataKey,
    this.activeBarLayer = const {},
  });
  final bool cursorVisible;
  final Offset? coordinate;

  /// Payloads of the active tooltip entries (`selectActiveTooltipDataPoints`).
  final List<Object?> activeDataPoints;

  /// `selectActiveTooltipIndex` / `selectActiveTooltipDataKey`.
  final int? activeIndex;
  final Object? activeDataKey;

  /// Bars drawn in the activeBar z-layer: the active ones and those staying there ([nextActiveBarLayer]).
  final Set<BarKey> activeBarLayer;
}

/// A bar rectangle as React keys it (`rectangle-x-y-value-i`): new geometry is a new element.
typedef BarKey = (String id, int index, double x, double y);

BarKey barKey(GraphicalItem item, BarRect r) => (item.id, r.originalDataIndex, r.x, r.y);

/// `isActive` of BarRectangleWithActiveState.
bool isActiveBar(Bar bar, BarRect r, int? activeIndex, Object? activeDataKey) =>
    bar.activeBar != false &&
    r.originalDataIndex == activeIndex &&
    (activeDataKey == null || bar.dataKey == activeDataKey);

/// `isAnotherBarActive` of BarRectangleWithActiveState.
bool isAnotherBarActive(Bar bar, BarRect r, int? activeIndex, Object? activeDataKey) =>
    activeIndex != null &&
    (r.originalDataIndex != activeIndex || (activeDataKey != null && bar.dataKey != activeDataKey));

/// `stayInLayer`: an active bar moves to the activeBar layer and leaves it only
/// once another bar is active; its exit transition never ends (Rectangle has
/// no CSS transition), so it stays there after the tooltip hides.
Set<BarKey> nextActiveBarLayer(CartesianModel m, Set<BarKey> previous, int? activeIndex, Object? activeDataKey) => {
      for (final s in m.series)
        if (s.item.element case final Bar bar when bar.activeBar != false && !s.item.hide)
          for (final r in s.rects ?? const <BarRect>[])
            if (isActiveBar(bar, r, activeIndex, activeDataKey) ||
                (previous.contains(barKey(s.item, r)) && !isAnotherBarActive(bar, r, activeIndex, activeDataKey)))
              barKey(s.item, r),
    };

/// The rectangles a Bar shows this frame (mid-animation they are interpolated).
List<BarRect>? currentBarRects(ChartFrame frame, SeriesModel s) =>
    frame.barAnimators[s.item.id]?.peek((items, t) => interpolateBarRects(items, t, frame.model.layout)) ?? s.rects;

/// Whether [r] renders in the activeBar layer rather than with the other bars.
bool inActiveBarLayer(HoverState? h, GraphicalItem item, Bar bar, BarRect r) =>
    h != null &&
    bar.activeBar != false &&
    (isActiveBar(bar, r, h.activeIndex, h.activeDataKey) || h.activeBarLayer.contains(barKey(item, r)));

/// The option a bar renders with: `activeBar` props are merged over the bar's
/// (`mergeShapeProps`); `activeBar={true}` renders the bar's own shape.
SvgStyle? activeBarStyle(HoverState? h, Bar bar, BarRect r) =>
    h != null && bar.activeBar is SvgStyle && isActiveBar(bar, r, h.activeIndex, h.activeDataKey)
        ? bar.activeBar as SvgStyle
        : null;

/// The Rectangle path of a bar, as painted and hit tested.
Path barPath(Bar bar, BarRect r, SvgStyle? active) =>
    rectanglePath(r.x, r.y, r.width, r.height, active?.radius ?? bar.radius);

/// Everything painters need for one build of the chart.
class ChartFrame {
  ChartFrame({
    required this.model,
    required this.children,
    required this.textStyle,
    required this.textScaler,
    required this.barAnimators,
    required this.lineAnimators,
    required this.lineLengths,
    this.areaBaseLines = const {},
    this.funnelAnimators = const {},
    this.scatterAnimators = const {},
    this.errorBarAnimations = const {},
  });
  final CartesianModel model;
  final List<RechartsElement> children;
  final TextStyle textStyle;
  final TextScaler textScaler;
  final Map<String, SeriesAnimator<BarRect>> barAnimators;

  /// Line and Area points.
  final Map<String, SeriesAnimator<LinePoint>> lineAnimators;
  final Map<String, AnimatedLineLength> lineLengths;
  final Map<String, AreaBaseLineAnimation> areaBaseLines;
  final Map<String, SeriesAnimator<ScatterPoint>> scatterAnimators;

  /// By [errorBarAnimationKey].
  final Map<String, ErrorBarAnimation> errorBarAnimations;

  /// Funnel trapezoids by funnel id.
  final Map<String, SeriesAnimator<FunnelTrapezoid>> funnelAnimators;

  /// The tick text style: inherited font + `fontSize` + tick props, filled with `stroke`.
  TextStyle tickStyle(CartesianAxisElement? axis) {
    var style = textStyle;
    if (axis == null) return style;
    style = style.copyWith(color: axis.stroke);
    if (axis.fontSize != null) style = style.copyWith(fontSize: axis.fontSize);
    if (axis.tick is TextStyle) style = style.merge(axis.tick as TextStyle);
    return style;
  }
}

/// `<Dot>`, or `<DotSymbol>` for a [symbol] (`2 * r` across); [fill] (a
/// Color or Gradient) overrides [DotProps.fill].
void paintDot(Canvas canvas, DotProps d, List<double>? dash, {Object? fill, double fillOpacity = 1, SymbolType? symbol}) {
  // Dot.tsx renders nothing without a numeric position.
  if (d.cx.isNaN || d.cy.isNaN || d.r.isNaN) return;
  final center = Offset(d.cx, d.cy);
  final path = symbol == null
      ? (Path()..addOval(Rect.fromCircle(center: center, radius: d.r)))
      : symbolPath(symbol, 2 * d.r, sizeType: SymbolSizeType.diameter).shift(center);
  final f = fill ?? d.fill;
  if (f != null) {
    final paint = fillPaintOf(f, path.getBounds(), opacity: fillOpacity);
    symbol == null ? canvas.drawCircle(center, d.r, paint) : canvas.drawPath(path, paint);
  }
  if (d.stroke != null && d.strokeWidth > 0) drawStroke(canvas, path, strokePaint(d.stroke!, d.strokeWidth), dash);
}

/// `getEntrySvgProps` for a Dot: the SVG props of a data entry that paint a
/// circle. They win over the series props and the `dot` option.
// ponytail: opacity, strokeOpacity and strokeDasharray of the entry are not read.
({Color? fill, Color? stroke, double? fillOpacity, double? strokeWidth, double? r}) entryDotStyle(Object? payload) {
  final e = payload is Map ? payload : null;
  double? n(String key) => e?[key] is num ? (e![key] as num).toDouble() : null;
  return (
    fill: cssFillOf(e?['fill']),
    stroke: cssStrokeOf(e?['stroke']),
    fillOpacity: n('fillOpacity'),
    strokeWidth: n('strokeWidth'),
    r: n('r'),
  );
}

class CartesianPainter extends CustomPainter {
  CartesianPainter(this.layer, this.frame, {this.hover, super.repaint});

  final ChartLayer layer;
  final ChartFrame frame;
  final ValueListenable<HoverState>? hover;

  CartesianModel get m => frame.model;

  @override
  void paint(Canvas canvas, Size size) {
    switch (layer) {
      case ChartLayer.background:
        _paintGrid(canvas);
        _paintBarBackgrounds(canvas);
      case ChartLayer.cursorBelow:
        _paintCursor(canvas, rectangle: true);
      case ChartLayer.main:
        _paintMain(canvas);
      case ChartLayer.activeBar:
        _paintActiveBars(canvas);
      case ChartLayer.overlay:
        _paintCursor(canvas, rectangle: false);
        _paintActiveDots(canvas);
        _paintActiveScatterPoints(canvas);
      case ChartLayer.labels:
        _paintLabels(canvas);
    }
  }

  @override
  bool shouldRepaint(CartesianPainter old) => old.frame != frame || old.layer != layer;

  /// Pointer input is handled by the chart's Listener and the Brush below these layers.
  @override
  bool? hitTest(Offset position) => false;

  // ---------------------------------------------------------------- grid

  void _paintGrid(Canvas canvas) {
    final grid = m.grid;
    if (grid == null) return;
    final g = grid.settings;
    final r = grid.rect;
    if (g.fill != null) {
      canvas.drawRect(r, fillPaint(g.fill!, opacity: g.fillOpacity ?? 1));
    }
    if (g.horizontal != false && g.horizontalFill.isNotEmpty) {
      final pts = [for (final e in grid.horizontalPoints) jsRound(e)]..sort();
      if (pts.isEmpty || r.top != pts.first) pts.insert(0, 0);
      for (var i = 0; i < pts.length; i++) {
        final h = i + 1 < pts.length ? pts[i + 1] - pts[i] : r.top + r.height - pts[i];
        if (h <= 0) continue;
        canvas.drawRect(Rect.fromLTWH(r.left, pts[i], r.width, h),
            fillPaint(g.horizontalFill[i % g.horizontalFill.length], opacity: g.fillOpacity ?? 1));
      }
    }
    if (g.vertical != false && g.verticalFill.isNotEmpty) {
      final pts = [for (final e in grid.verticalPoints) jsRound(e)]..sort();
      if (pts.isEmpty || r.left != pts.first) pts.insert(0, 0);
      for (var i = 0; i < pts.length; i++) {
        final w = i + 1 < pts.length ? pts[i + 1] - pts[i] : r.left + r.width - pts[i];
        if (w <= 0) continue;
        canvas.drawRect(Rect.fromLTWH(pts[i], r.top, w, r.height),
            fillPaint(g.verticalFill[i % g.verticalFill.length], opacity: g.fillOpacity ?? 1));
      }
    }
    void lines(Object option, List<double> points, bool horizontal) {
      if (option == false || points.isEmpty) return;
      final style = option is SvgStyle ? option : null;
      final paint = strokePaint(style?.stroke ?? g.stroke, style?.strokeWidth ?? g.strokeWidth,
          opacity: style?.strokeOpacity ?? 1);
      final dash = style?.strokeDasharray ?? g.strokeDasharray;
      for (final p in points) {
        final path = Path();
        if (horizontal) {
          path
            ..moveTo(r.left, p)
            ..lineTo(r.left + r.width, p);
        } else {
          path
            ..moveTo(p, r.top)
            ..lineTo(p, r.top + r.height);
        }
        drawStroke(canvas, path, paint, dash);
      }
    }

    lines(g.horizontal, grid.horizontalPoints, true);
    lines(g.vertical, grid.verticalPoints, false);
  }

  void _paintBarBackgrounds(Canvas canvas) {
    for (final s in m.series) {
      final bar = s.item.element;
      if (bar is! Bar || bar.background == false || s.item.hide) continue;
      final style = bar.background is SvgStyle ? bar.background as SvgStyle : null;
      for (final rect in s.rects ?? const <BarRect>[]) {
        final b = rect.background;
        if (b == null) continue;
        // The background gets the entry's rectangle props, not the Bar's `radius`.
        if (b.width == 0 || b.height == 0) continue;
        final path = rectanglePath(b.left, b.top, b.width, b.height, 0);
        canvas.drawPath(path, fillPaint(style?.fill ?? const Color(0xFFEEEEEE), opacity: style?.fillOpacity ?? 1));
        if (style?.stroke != null) {
          drawStroke(canvas, path, strokePaint(style!.stroke!, style.strokeWidth ?? 1), style.strokeDasharray);
        }
      }
    }
  }

  // ---------------------------------------------------------------- main

  Rect? _clipFor(GraphicalItem item) => _clipAreaOf(item)?.area;

  /// `useGraphicalItemClipArea`: the clip rect, and the dimensions it clips.
  ({Rect area, bool x, bool y})? _clipAreaOf(GraphicalItem item) {
    final x = _axisSettings(true, item.xAxisId);
    final y = _axisSettings(false, item.yAxisId);
    final needX = x?.allowDataOverflow ?? false, needY = y?.allowDataOverflow ?? false;
    if (!needX && !needY) return null;
    final p = m.offset.plotArea;
    final area = Rect.fromLTRB(
      needX ? p.left : p.left - p.width / 2,
      needY ? p.top : p.top - p.height / 2,
      needX ? p.right : p.right + p.width / 2,
      needY ? p.bottom : p.bottom + p.height / 2,
    );
    return (area: area, x: needX, y: needY);
  }

  CartesianAxisElement? _axisSettings(bool isX, Object id) {
    for (final c in frame.children) {
      if (c is CartesianAxisElement && c.isX == isX && c.id == id) return c;
    }
    return null;
  }

  void _withClip(Canvas canvas, Rect? clip, void Function() draw) {
    if (clip == null) return draw();
    canvas.save();
    canvas.clipRect(clip);
    draw();
    canvas.restore();
  }

  SeriesModel? _seriesOf(CartesianSeries c) => m.series.where((s) => identical(s.item.element, c)).firstOrNull;

  void _paintMain(Canvas canvas) {
    final lineSteps = <String, List<LinePoint>>{};
    // Areas (z 100), in document order.
    for (final c in frame.children) {
      if (c is ReferenceArea) {
        _paintReferenceArea(canvas, c);
        continue;
      }
      if (c is! Area) continue;
      final s = _seriesOf(c);
      if (s == null || s.item.hide || s.points == null) continue;
      final animator = frame.lineAnimators[s.item.id];
      final isEntrance = animator?.isEntrance ?? false;
      final t = animator?.t ?? 1.0;
      final points = animator?.step(interpolateAreaPoints) ?? s.points!;
      final baseLine = frame.areaBaseLines[s.item.id]?.step(s.baseLine!, t, isEntrance: isEntrance) ?? s.baseLine!;
      lineSteps[s.item.id] = points;
      final reveal = isEntrance && (animator!.isAnimating || t < 1);
      _withClip(canvas, _clipFor(s.item), () => _paintArea(canvas, c, s.isRange, points, baseLine, reveal ? t : null));
    }
    // Bars (z 300)
    for (final s in m.series) {
      if (!s.item.isBar || s.item.hide) continue;
      final rects = frame.barAnimators[s.item.id]?.step((items, t) => interpolateBarRects(items, t, m.layout)) ??
          s.rects;
      if (rects == null) continue;
      final bar = s.item.element as Bar;
      _withClip(canvas, _clipFor(s.item), () {
        for (final r in rects) {
          if (!inActiveBarLayer(hover?.value, s.item, bar, r)) _paintBar(canvas, bar, r, null);
        }
      });
    }
    // Funnels (no zIndex: the default layer), in document order.
    for (final f in m.funnels) {
      if (f.settings.hide) continue;
      final ts = currentTrapezoids(frame, f, record: true);
      if (ts == null) continue;
      final active = hover?.value.activeIndex;
      for (final t in ts) {
        if (!trapezoidVisible(t)) continue;
        _paintTrapezoid(canvas, f.settings, t, f.settings.activeShape != null && active == t.index);
      }
    }
    // Lines, reference lines and error bars (z 400), in document order; an
    // item's error bars mount into the layer before the item's own line, in
    // the item's clip.
    for (final c in frame.children) {
      if (c is Bar || c is Scatter || c is Line) {
        final s = _seriesOf(c as CartesianSeries);
        if (s != null) _withClip(canvas, _clipFor(s.item), () => _paintErrorBars(canvas, s));
      }
      if (c is Line) {
        final s = _seriesOf(c);
        if (s == null || s.item.hide || s.points == null) continue;
        final animator = frame.lineAnimators[s.item.id];
        final points = animator?.step(interpolateLinePoints) ?? s.points!;
        lineSteps[s.item.id] = points;
        _withClip(canvas, _clipFor(s.item), () => _paintCurve(canvas, s.item, c, points, animator));
      } else if (c is ReferenceLine) {
        final r = m.referenceLines.where((r) => r.settings == c).firstOrNull;
        if (r == null) continue;
        final path = Path()
          ..moveTo(r.p1.dx, r.p1.dy)
          ..lineTo(r.p2.dx, r.p2.dy);
        _withClip(canvas, c.ifOverflow == IfOverflow.hidden ? m.offset.plotArea : null,
            () => drawStroke(canvas, path, strokePaint(c.stroke, c.strokeWidth), c.strokeDasharray));
      }
    }
    // Axis lines and tick lines (z 500)
    for (final a in m.axes) {
      _paintAxisLines(canvas, a);
    }
    // Dots and scatters (z 600)
    for (final s in m.series) {
      if (s.item.element case final Scatter scatter when !s.item.hide) {
        final points = frame.scatterAnimators[s.item.id]?.step(interpolateScatterPoints) ?? s.scatterPoints;
        if (points != null) _withClip(canvas, _clipFor(s.item), () => _paintScatter(canvas, scatter, points));
        continue;
      }
      final points = lineSteps[s.item.id];
      if (points == null) continue;
      _withClip(canvas, _clipFor(s.item), () => _paintDots(canvas, s.item.element, points));
    }
    for (final c in frame.children) {
      if (c is ReferenceDot) _paintReferenceDot(canvas, c);
    }
  }

  /// FunnelTrapezoid: the default shape, with the SvgStyle `activeShape` merged over it.
  void _paintTrapezoid(Canvas canvas, Funnel f, FunnelTrapezoid t, bool active) {
    final a = active && f.activeShape is SvgStyle ? f.activeShape as SvgStyle : null;
    final path = trapezoidPath(t.x, t.y, t.upperWidth, t.lowerWidth, t.height);
    canvas.drawPath(path, fillPaint(a?.fill ?? t.fill, opacity: a?.fillOpacity ?? t.fillOpacity ?? 1));
    final stroke = a?.stroke ?? t.stroke;
    if (stroke != null) {
      drawStroke(canvas, path, strokePaint(stroke, a?.strokeWidth ?? t.strokeWidth ?? 1, opacity: a?.strokeOpacity ?? 1),
          a?.strokeDasharray);
    }
  }

  /// ReferenceArea.tsx: a Rectangle, clipped to the plot area for `ifOverflow: hidden`.
  void _paintReferenceArea(Canvas canvas, ReferenceArea c) {
    final r = m.referenceAreas.where((r) => r.settings == c).firstOrNull?.rect;
    if (r == null || r.width == 0 || r.height == 0) return;
    _withClip(canvas, c.ifOverflow == IfOverflow.hidden ? m.offset.plotArea : null, () {
      final path = rectanglePath(r.left, r.top, r.width, r.height, c.radius);
      canvas.drawPath(path, fillPaint(c.fill, opacity: c.fillOpacity));
      if (c.stroke != null) drawStroke(canvas, path, strokePaint(c.stroke!, c.strokeWidth, opacity: c.strokeOpacity), null);
    });
  }

  /// ReferenceDot.tsx: a Dot (circle).
  void _paintReferenceDot(Canvas canvas, ReferenceDot c) {
    final d = m.referenceDots.where((d) => d.settings == c).firstOrNull;
    if (d == null) return;
    _withClip(canvas, c.ifOverflow == IfOverflow.hidden ? m.offset.plotArea : null, () {
      canvas.drawCircle(d.center, c.r, fillPaint(c.fill, opacity: c.fillOpacity));
      if (c.stroke != null) canvas.drawCircle(d.center, c.r, strokePaint(c.stroke!, c.strokeWidth));
    });
  }

  /// AreaRevealShape: the fill curve down to [baseLine], the stroke curve over
  /// the points and, for range areas, over the baseline; inside the growing
  /// clip rect while the entrance runs ([revealAlpha]).
  void _paintArea(Canvas canvas, Area area, bool isRange, List<LinePoint> points, Object baseLine, double? revealAlpha) {
    if (points.length <= 1) return;
    final layout = m.layout;
    void draw() {
      if (area.fill != null) {
        final path = areaPath(pointOffsets(points), areaBaseLineOf(baseLine), area.type,
            layout: layout, connectNulls: area.connectNulls);
        canvas.drawPath(path, fillPaintOf(area.fill!, path.getBounds(), opacity: area.fillOpacity));
      }
      if (area.stroke == null) return;
      final paint = strokePaint(area.stroke!, area.strokeWidth);
      drawStroke(canvas, linePath(pointOffsets(points), area.type, layout: layout, connectNulls: area.connectNulls), paint,
          area.strokeDasharray);
      if (isRange && baseLine is List<LinePoint>) {
        drawStroke(canvas, linePath(pointOffsets(baseLine), area.type, layout: layout, connectNulls: area.connectNulls),
            paint, area.strokeDasharray);
      }
    }

    if (revealAlpha == null) return draw();
    // An empty clipPath hides everything.
    final clip = revealClipRect(revealAlpha, points, baseLine, layout, area.strokeWidth);
    if (clip == null) return;
    canvas.save();
    canvas.clipRect(clip);
    draw();
    canvas.restore();
  }

  /// Rectangle with `{...barProps, ...entry (incl. Cell props), ...active}`.
  void _paintBar(Canvas canvas, Bar bar, BarRect r, SvgStyle? active) {
    if (!r.x.isFinite || !r.y.isFinite || r.width == 0 || r.height == 0) return;
    final path = barPath(bar, r, active);
    final entry = r.payload is Map ? r.payload as Map : null;
    final fill = active?.fill ?? r.cell?.fill ?? cssFillOf(entry?['fill']) ?? bar.fill ?? const Color(0xFF000000);
    canvas.drawPath(path,
        fillPaintOf(fill, path.getBounds(), opacity: active?.fillOpacity ?? r.cell?.fillOpacity ?? bar.fillOpacity ?? 1));
    final stroke = active?.stroke ?? r.cell?.stroke ?? cssStrokeOf(entry?['stroke']) ?? bar.stroke;
    if (stroke != null) {
      drawStroke(
          canvas,
          path,
          strokePaint(stroke, active?.strokeWidth ?? r.cell?.strokeWidth ?? bar.strokeWidth ?? 1,
              opacity: active?.strokeOpacity ?? 1),
          active?.strokeDasharray);
    }
  }

  /// The activeBar ZIndexLayer: a portal, so outside the bars' clip path.
  void _paintActiveBars(Canvas canvas) {
    final h = hover?.value;
    for (final s in m.series) {
      final bar = s.item.element;
      if (bar is! Bar || bar.activeBar == false || s.item.hide) continue;
      for (final r in currentBarRects(frame, s) ?? const <BarRect>[]) {
        if (inActiveBarLayer(h, s.item, bar, r)) _paintBar(canvas, bar, r, activeBarStyle(h, bar, r));
      }
    }
  }

  void _paintCurve(
      Canvas canvas, GraphicalItem item, Line line, List<LinePoint> points, SeriesAnimator<LinePoint>? animator) {
    if (points.length <= 1 || line.stroke == null) return;
    final path = linePath(pointOffsets(points), line.type, layout: m.layout, connectNulls: line.connectNulls);
    List<double>? dash = line.strokeDasharray;
    if (animator != null) {
      final t = animator.t;
      if (animator.isAnimating || t < 1) {
        var total = 0.0;
        for (final metric in path.computeMetrics()) {
          total += metric.length;
        }
        final visible = frame.lineLengths[item.id]?.visibleLength(animator.animationId, t, total);
        if (visible != null) dash = animatedStrokeDasharray(visible, total, line.strokeDasharray);
      }
    }
    drawStroke(canvas, path, strokePaint(line.stroke!, line.strokeWidth), dash);
  }

  /// Dots.tsx with the series' svg props as base props (Line: fill `#fff`;
  /// Area: its fill), and `fillOpacity: 1` over them.
  void _paintDots(Canvas canvas, CartesianSeries series, List<LinePoint> points) {
    final (dot, fill, stroke, strokeWidth, dash) = switch (series) {
      Area a => (a.dot, a.fill, a.stroke, a.strokeWidth, a.strokeDasharray),
      Line l => (l.dot, l.fill, l.stroke, l.strokeWidth, l.strokeDasharray),
      _ => (false, null, null, 1.0, null),
    };
    if (!(dot != false || points.length == 1)) return;
    final style = dot is SvgStyle ? dot : null;
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      if (p.x == null || p.y == null) continue;
      final entry = entryDotStyle(p.payload);
      final dotFill = entry.fill ?? style?.fill ?? fill;
      final props = DotProps(
        cx: p.x!,
        cy: p.y!,
        r: entry.r ?? style?.r ?? 3,
        index: i,
        value: p.value,
        payload: p.payload,
        dataKey: series.dataKey,
        fill: solidColor(dotFill),
        stroke: entry.stroke ?? style?.stroke ?? stroke,
        strokeWidth: entry.strokeWidth ?? style?.strokeWidth ?? strokeWidth,
      );
      if (dot is DotPainter) {
        dot(canvas, props);
      } else {
        paintDot(canvas, props, style?.strokeDasharray ?? dash,
            fill: dotFill, fillOpacity: entry.fillOpacity ?? style?.fillOpacity ?? 1, symbol: dotSymbol(dot));
      }
    }
  }

  /// ScatterSymbols: the line, then a symbol per point; the active point
  /// moves to the activeDot layer ([_paintActiveScatterPoints]).
  void _paintScatter(Canvas canvas, Scatter scatter, List<ScatterPoint> points) {
    if (points.isEmpty) return;
    _paintScatterLine(canvas, scatter, points);
    final h = hover?.value;
    for (var i = 0; i < points.length; i++) {
      if (!isActiveScatterPoint(h, scatter, i)) paintScatterPoint(canvas, scatter, points[i], i);
    }
  }

  /// ScatterLine, stroked with the fill unless `line` sets a stroke (no stroke, no line).
  void _paintScatterLine(Canvas canvas, Scatter scatter, List<ScatterPoint> points) {
    final line = scatter.line;
    if (line == false) return;
    final style = line is SvgStyle ? line : null;
    final stroke = style?.stroke ?? scatter.fill;
    if (stroke == null) return;
    final curve = scatterLine(scatter, points);
    drawStroke(
        canvas,
        linePath(curve.points, curve.type),
        strokePaint(stroke, style?.strokeWidth ?? scatter.strokeWidth ?? 1, opacity: style?.strokeOpacity ?? 1),
        style?.strokeDasharray);
  }

  /// ErrorBarImpl: `<line>`s stroked with the ErrorBar's props, each scaled
  /// around its origin while it animates in.
  void _paintErrorBars(Canvas canvas, SeriesModel s) {
    for (var b = 0; b < s.errorBars.length; b++) {
      final (bar, lines) = s.errorBars[b];
      if (bar.stroke == null || bar.strokeWidth <= 0) continue;
      final animation = frame.errorBarAnimations[errorBarAnimationKey(s.item, b)];
      final paint = strokePaint(bar.stroke!, bar.strokeWidth);
      final horizontal = errorBarDirection(bar, m.layout) == ErrorBarDirection.x;
      for (final l in lines) {
        final scale = animation?.scaleOf(l.key) ?? 1;
        if (scale <= 0) continue;
        final path = Path()
          ..moveTo(l.p1.dx, l.p1.dy)
          ..lineTo(l.p2.dx, l.p2.dy);
        if (scale == 1) {
          canvas.drawPath(path, paint);
          continue;
        }
        canvas.save();
        canvas.translate(l.origin.dx, l.origin.dy);
        canvas.scale(horizontal ? scale : 1, horizontal ? 1 : scale);
        canvas.translate(-l.origin.dx, -l.origin.dy);
        canvas.drawPath(path, paint);
        canvas.restore();
      }
    }
  }

  // ---------------------------------------------------------------- axes

  void _paintAxisLines(Canvas canvas, AxisLayout a) {
    final s = a.settings;
    final r = a.rect;
    if (r.width <= 0 || r.height <= 0) return;
    if (s.axisLine != false) {
      final style = s.axisLine is SvgStyle ? s.axisLine as SvgStyle : null;
      final path = Path();
      if (s.orientation == AxisOrientation.top || s.orientation == AxisOrientation.bottom) {
        final need = (s.orientation == AxisOrientation.top && !s.mirror) || (s.orientation == AxisOrientation.bottom && s.mirror);
        final y = r.top + (need ? r.height : 0);
        path
          ..moveTo(r.left, y)
          ..lineTo(r.left + r.width, y);
      } else {
        final need = (s.orientation == AxisOrientation.left && !s.mirror) || (s.orientation == AxisOrientation.right && s.mirror);
        final x = r.left + (need ? r.width : 0);
        path
          ..moveTo(x, r.top)
          ..lineTo(x, r.top + r.height);
      }
      drawStroke(canvas, path, strokePaint(style?.stroke ?? s.stroke, style?.strokeWidth ?? 1, opacity: style?.strokeOpacity ?? 1),
          style?.strokeDasharray);
    }
    if (s.tickLine != false && s.tick != false) {
      final style = s.tickLine is SvgStyle ? s.tickLine as SvgStyle : null;
      final paint = strokePaint(style?.stroke ?? s.stroke, style?.strokeWidth ?? 1, opacity: style?.strokeOpacity ?? 1);
      for (final t in a.ticks) {
        final c = getTickLineCoord(a, t);
        final path = Path()
          ..moveTo(c.p1.dx, c.p1.dy)
          ..lineTo(c.p2.dx, c.p2.dy);
        drawStroke(canvas, path, paint, style?.strokeDasharray);
      }
    }
  }

  TextAnchor _tickTextAnchor(CartesianAxisElement s) => s.textAnchor ??
      switch (s.orientation) {
        AxisOrientation.left => s.mirror ? TextAnchor.start : TextAnchor.end,
        AxisOrientation.right => s.mirror ? TextAnchor.end : TextAnchor.start,
        _ => TextAnchor.middle,
      };

  TextVerticalAnchor _tickVerticalAnchor(CartesianAxisElement s) => switch (s.orientation) {
        AxisOrientation.left || AxisOrientation.right => TextVerticalAnchor.middle,
        AxisOrientation.top => s.mirror ? TextVerticalAnchor.start : TextVerticalAnchor.end,
        AxisOrientation.bottom => s.mirror ? TextVerticalAnchor.end : TextVerticalAnchor.start,
      };

  void _paintTickLabels(Canvas canvas, AxisLayout a) {
    final s = a.settings;
    if (s.tick == false || a.rect.width <= 0 || a.rect.height <= 0) return;
    final style = frame.tickStyle(s);
    final anchor = _tickTextAnchor(s), vAnchor = _tickVerticalAnchor(s);
    for (var i = 0; i < a.ticks.length; i++) {
      final t = a.ticks[i];
      final pos = getTickLineCoord(a, t).tick;
      final text = '${s.tickFormatter != null ? s.tickFormatter!(t.value, i) : jsString(t.value)}${s.unit ?? ''}';
      if (s.tick is TickPainter) {
        (s.tick as TickPainter)(
          canvas,
          TickProps(
            x: pos.dx,
            y: pos.dy,
            index: i,
            value: t.value,
            text: text,
            textAnchor: anchor,
            verticalAnchor: vAnchor,
            angle: s.angle,
            fill: style.color ?? s.stroke,
            style: style,
            visibleTicksCount: a.ticks.length,
          ),
        );
        continue;
      }
      paintSvgText(canvas, text, pos.dx, pos.dy,
          style: style,
          textAnchor: anchor,
          verticalAnchor: vAnchor,
          angle: s.angle,
          width: s is YAxis && s.width is num ? (s.width as num).toDouble() : null,
          scaler: frame.textScaler);
    }
  }

  void _paintLabels(Canvas canvas) {
    for (final c in frame.children) {
      if (c is CartesianAxisElement) {
        for (final a in m.axes.where((a) => a.settings == c)) {
          _paintTickLabels(canvas, a);
          if (a.rect.width > 0 && a.rect.height > 0) {
            paintLabel(canvas, parseLabel(c.label), a.rect, baseStyle: frame.textStyle, scaler: frame.textScaler);
          }
        }
      } else if (c is ReferenceLine && c.label != null) {
        final r = m.referenceLines.where((r) => r.settings == c).firstOrNull;
        if (r == null) continue;
        paintLabel(canvas, parseLabel(c.label), Rect.fromPoints(r.p1, r.p2),
            baseStyle: frame.textStyle, scaler: frame.textScaler);
      } else if (c is Funnel) {
        final f = m.funnels.where((f) => identical(f.settings, c)).firstOrNull;
        if (f == null || f.settings.hide || (frame.funnelAnimators[f.id]?.isAnimating ?? false)) continue;
        paintFunnelLabelLists(canvas, f, baseStyle: frame.textStyle, scaler: frame.textScaler);
      } else if (c is ReferenceArea && c.label != null) {
        final r = m.referenceAreas.where((r) => r.settings == c).firstOrNull;
        if (r == null) continue;
        paintLabel(canvas, parseLabel(c.label), r.rect, baseStyle: frame.textStyle, scaler: frame.textScaler);
      } else if (c is ReferenceDot && c.label != null) {
        final d = m.referenceDots.where((d) => d.settings == c).firstOrNull;
        if (d == null) continue;
        paintLabel(canvas, parseLabel(c.label), Rect.fromLTWH(d.center.dx - c.r, d.center.dy - c.r, 2 * c.r, 2 * c.r),
            baseStyle: frame.textStyle, scaler: frame.textScaler);
      } else if (c is CartesianSeries) {
        // Labels show once the series stops animating (`showLabels={!isAnimating}`).
        final s = _seriesOf(c);
        if (s == null || s.item.hide) continue;
        final animator = s.item.isBar
            ? frame.barAnimators[s.item.id]
            : s.item.isScatter
                ? frame.scatterAnimators[s.item.id]
                : frame.lineAnimators[s.item.id];
        if (animator?.isAnimating ?? false) continue;
        paintLabelLists(canvas, s, m.size,
            viewBox: m.viewBox, clip: _clipAreaOf(s.item), baseStyle: frame.textStyle, scaler: frame.textScaler);
      }
    }
  }

  // ---------------------------------------------------------------- tooltip overlay

  void _paintCursor(Canvas canvas, {required bool rectangle}) {
    final h = hover?.value;
    final tooltip = m.tooltipSettings;
    if (h == null || tooltip == null || !h.cursorVisible || h.coordinate == null || tooltip.cursor == false) return;
    final isBarChart = m.chartName == 'BarChart';
    if (isBarChart != rectangle) return;
    final style = tooltip.cursor is SvgStyle ? tooltip.cursor as SvgStyle : null;
    if (isBarChart) {
      final r = cursorRectangle(m.layout, h.coordinate!, m.offset, m.tooltipAxisBandSize);
      if (r.width == 0 || r.height == 0) return;
      final path = rectanglePath(r.left, r.top, r.width, r.height, 0);
      canvas.drawPath(path, fillPaint(style?.fill ?? const Color(0xFFCCCCCC), opacity: style?.fillOpacity ?? 1));
      // The legacy cursor stroke (#ccc) reaches the rectangle too since getCursorRectangle dropped `stroke: 'none'`.
      drawStroke(canvas, path, strokePaint(style?.stroke ?? const Color(0xFFCCCCCC), style?.strokeWidth ?? 1),
          style?.strokeDasharray);
    } else if (m.chartName == 'ScatterChart') {
      // Cross: `M${x},${top}v${height}M${left},${y}h${width}`.
      final c = h.coordinate!, o = m.offset;
      final path = Path()
        ..moveTo(c.dx, o.top)
        ..lineTo(c.dx, o.top + o.height)
        ..moveTo(o.left, c.dy)
        ..lineTo(o.left + o.width, c.dy);
      drawStroke(canvas, path, strokePaint(style?.stroke ?? const Color(0xFFCCCCCC), style?.strokeWidth ?? 1),
          style?.strokeDasharray);
    } else {
      final pts = cursorPoints(m.layout, h.coordinate!, m.offset);
      final path = Path()
        ..moveTo(pts[0].dx, pts[0].dy)
        ..lineTo(pts[1].dx, pts[1].dy);
      drawStroke(canvas, path, strokePaint(style?.stroke ?? const Color(0xFFCCCCCC), style?.strokeWidth ?? 1),
          style?.strokeDasharray);
    }
  }

  /// ActivePoints: the point whose payload is active, filled with the fill of
  /// its data entry, else the item's main color (Line's stroke, Area's
  /// `getLegendItemColor`). Range areas also mark their baseline.
  void _paintActiveDots(Canvas canvas) {
    final h = hover?.value;
    if (h == null || h.activeDataPoints.isEmpty) return;
    for (final s in m.series) {
      final el = s.item.element;
      final activeDot = switch (el) {
        Line l => l.activeDot,
        Area a => a.activeDot,
        _ => false,
      };
      if (s.item.hide || activeDot == false || s.points == null) continue;
      final baseLine = s.baseLine;
      for (final points in [s.points!, if (el is Area && s.isRange && baseLine is List<LinePoint>) baseLine]) {
        final p = points.where((p) => h.activeDataPoints.any((d) => identical(d, p.payload))).firstOrNull;
        if (p == null || p.x == null || p.y == null) continue;
        final style = activeDot is SvgStyle ? activeDot : null;
        final props = DotProps(
          cx: p.x!,
          cy: p.y!,
          r: style?.r ?? 4,
          index: points.indexOf(p),
          value: p.value,
          payload: p.payload,
          dataKey: el.dataKey,
          fill: style?.fill ?? entryDotStyle(p.payload).fill ?? el.tooltipColor,
          stroke: style?.stroke ?? const Color(0xFFFFFFFF),
          strokeWidth: style?.strokeWidth ?? 2,
        );
        _withClip(canvas, _clipFor(s.item), () {
          if (activeDot is DotPainter) {
            activeDot(canvas, props);
          } else {
            paintDot(canvas, props, style?.strokeDasharray, symbol: dotSymbol(activeDot));
          }
        });
      }
    }
  }

  /// Active ScatterPoints render in the activeDot ZIndexLayer: a portal,
  /// outside the scatter's clip.
  void _paintActiveScatterPoints(Canvas canvas) {
    final h = hover?.value;
    if (h == null || h.activeIndex == null) return;
    for (final s in m.series) {
      final scatter = s.item.element;
      if (scatter is! Scatter || s.item.hide) continue;
      final points = currentScatterPoints(frame, s);
      final i = h.activeIndex!;
      if (points == null || i >= points.length || !isActiveScatterPoint(h, scatter, i)) continue;
      paintScatterPoint(canvas, scatter, points[i], i, active: true);
    }
  }
}

/// The points a Scatter shows this frame (mid-animation they are interpolated).
List<ScatterPoint>? currentScatterPoints(ChartFrame frame, SeriesModel s) =>
    frame.scatterAnimators[s.item.id]?.peek(interpolateScatterPoints) ?? s.scatterPoints;

/// ScatterPoint's `isActive`: an `activeShape` is set and the point's index is
/// the active tooltip index (of any item).
bool isActiveScatterPoint(HoverState? h, Scatter scatter, int index) =>
    h != null && scatter.activeShape != null && scatter.activeShape != false && h.activeIndex == index;

String errorBarAnimationKey(GraphicalItem item, int errorBarIndex) => '${item.id}/errorBar$errorBarIndex';

/// The option a point renders with ([Scatter.shape], or [Scatter.activeShape]
/// when active) as `(symbol type, style merged over the point, painter)`:
/// Shape renders `true` and object options with its DefaultShape, a circle.
(SymbolType, SvgStyle?, ScatterShapePainter?) _scatterOption(Scatter scatter, bool active) {
  final option = active ? scatter.activeShape : scatter.shape;
  return switch (option) {
    SymbolType t => (t, null, null),
    SvgStyle style => (SymbolType.circle, style, null),
    ScatterShapePainter p => (SymbolType.circle, null, p),
    _ => (SymbolType.circle, null, null),
  };
}

/// The `<Symbols>` path of point [p] at its center, as painted and hit
/// tested; null where Symbols renders nothing.
Path? scatterSymbolPath(Scatter scatter, ScatterPoint p, {bool active = false}) {
  final cx = p.cx, cy = p.cy, size = p.size;
  if (cx == null || cy == null || size == null || size.isNaN) return null;
  return symbolPath(_scatterOption(scatter, active).$1, size).shift(Offset(cx, cy));
}

/// ScatterSymbol: `{...scatterProps, ...entry (data fields, Cell), ...option}`.
/// A Color under `fill` in a Map entry counts like Recharts' data `fill`.
void paintScatterPoint(Canvas canvas, Scatter scatter, ScatterPoint p, int index, {bool active = false}) {
  final (_, style, painter) = _scatterOption(scatter, active);
  final dataFill = p.payload is Map ? (p.payload as Map)['fill'] : null;
  final fill = style?.fill ?? p.cell?.fill ?? cssFillOf(dataFill) ?? scatter.fill;
  final dataStroke = p.payload is Map ? (p.payload as Map)['stroke'] : null;
  final stroke = style?.stroke ?? p.cell?.stroke ?? cssStrokeOf(dataStroke) ?? scatter.stroke;
  final strokeWidth = style?.strokeWidth ?? p.cell?.strokeWidth ?? scatter.strokeWidth;
  if (painter != null) {
    if (p.cx == null || p.cy == null || p.size == null) return;
    painter(
        canvas,
        ScatterShapeProps(
          cx: p.cx!,
          cy: p.cy!,
          size: p.size!,
          index: index,
          payload: p.payload,
          isActive: active,
          fill: fill,
          stroke: stroke,
          strokeWidth: strokeWidth,
        ));
    return;
  }
  final path = scatterSymbolPath(scatter, p, active: active);
  if (path == null) return;
  canvas.drawPath(path,
      fillPaint(fill ?? const Color(0xFF000000), opacity: style?.fillOpacity ?? p.cell?.fillOpacity ?? scatter.fillOpacity ?? 1));
  if (stroke != null) {
    drawStroke(canvas, path, strokePaint(stroke, strokeWidth ?? 1, opacity: style?.strokeOpacity ?? 1),
        style?.strokeDasharray);
  }
}

/// ScatterLine's Curve: through the points (`joint`, `lineJointType`) or
/// along their linear regression (`fitting`).
({List<Offset?> points, CurveType type}) scatterLine(Scatter scatter, List<ScatterPoint> points) {
  // The Curve gets no layout, so getCurveFactory has no monotone or bump to resolve.
  final type = switch (scatter.lineJointType) {
    CurveType.monotone || CurveType.bump => CurveType.linear,
    final t => t,
  };
  if (scatter.lineType == ScatterLineType.fitting) {
    final r = getLinearRegression(points);
    return (points: [Offset(r.xmin, r.a * r.xmin + r.b), Offset(r.xmax, r.a * r.xmax + r.b)], type: type);
  }
  return (points: [for (final p in points) p.cx == null || p.cy == null ? null : Offset(p.cx!, p.cy!)], type: type);
}

/// `getLinearRegression` over the points' centers (a missing one counts as 0).
({double xmin, double xmax, double a, double b}) getLinearRegression(List<ScatterPoint> data) {
  final len = data.length;
  var xsum = 0.0, ysum = 0.0, xysum = 0.0, xxsum = 0.0;
  var xmin = double.infinity, xmax = double.negativeInfinity;
  for (final p in data) {
    final x = p.cx == null || p.cx!.isNaN ? 0.0 : p.cx!;
    final y = p.cy == null || p.cy!.isNaN ? 0.0 : p.cy!;
    xsum += x;
    ysum += y;
    xysum += x * y;
    xxsum += x * x;
    xmin = math.min(xmin, x);
    xmax = math.max(xmax, x);
  }
  final a = len * xxsum != xsum * xsum ? (len * xysum - xsum * ysum) / (len * xxsum - xsum * xsum) : 0.0;
  return (xmin: xmin, xmax: xmax, a: a, b: (ysum - a * xsum) / len);
}

/// AreaRevealShape `RevealClipRect`: grows from the first point towards the
/// last one (left to right, or top to bottom in vertical layout) over the full
/// value extent. Null is an empty clipPath, which hides the area.
Rect? revealClipRect(double alpha, List<LinePoint> points, Object baseLine, ChartLayout layout, double strokeWidth) {
  // `strokeWidth ? parseInt(`${strokeWidth}`, 10) : 1`
  final sw = strokeWidth == 0 || strokeWidth.isNaN ? 1.0 : strokeWidth.truncateToDouble();
  double or0(double? v) => v == null || v.isNaN ? 0 : v;
  final vertical = layout == ChartLayout.vertical;
  final start = vertical ? points.firstOrNull?.y : points.firstOrNull?.x;
  final end = vertical ? points.lastOrNull?.y : points.lastOrNull?.x;
  if (!isWellBehavedNumber(start) || !isWellBehavedNumber(end)) return null;
  final size = alpha * (start! - end!).abs();
  var max = points.map((p) => or0(vertical ? p.x : p.y)).reduce(math.max);
  if (isNumber(baseLine)) {
    max = math.max((baseLine as num).toDouble(), max);
  } else if (baseLine is List<LinePoint> && baseLine.isNotEmpty) {
    max = math.max(baseLine.map((p) => or0(vertical ? p.x : p.y)).reduce(math.max), max);
  }
  if (!isNumber(max)) return null;
  final from = start < end ? start : start - size;
  return vertical
      ? Rect.fromLTWH(0, from, max + sw, size.floorToDouble())
      : Rect.fromLTWH(from, 0, size, (max + sw).floorToDouble());
}

/// `getTickLineCoord`: tick line end points and the tick label anchor.
({Offset p1, Offset p2, Offset tick}) getTickLineCoord(AxisLayout a, TickItem data) {
  final s = a.settings;
  final r = a.rect;
  final sign = s.mirror ? -1 : 1;
  final tickSize = s.tickSize;
  final tickCoord = data.tickCoord ?? data.coordinate;
  final mirror = s.mirror ? 1 : 0, notMirror = s.mirror ? 0 : 1;
  switch (s.orientation) {
    case AxisOrientation.top:
      final y2 = r.top + notMirror * r.height;
      final y1 = y2 - sign * tickSize;
      return (p1: Offset(data.coordinate, y1), p2: Offset(data.coordinate, y2), tick: Offset(tickCoord, y1 - sign * s.tickMargin));
    case AxisOrientation.left:
      final x2 = r.left + notMirror * r.width;
      final x1 = x2 - sign * tickSize;
      return (p1: Offset(x1, data.coordinate), p2: Offset(x2, data.coordinate), tick: Offset(x1 - sign * s.tickMargin, tickCoord));
    case AxisOrientation.right:
      final x2 = r.left + mirror * r.width;
      final x1 = x2 + sign * tickSize;
      return (p1: Offset(x1, data.coordinate), p2: Offset(x2, data.coordinate), tick: Offset(x1 + sign * s.tickMargin, tickCoord));
    case AxisOrientation.bottom:
      final y2 = r.top + mirror * r.height;
      final y1 = y2 + sign * tickSize;
      return (p1: Offset(data.coordinate, y1), p2: Offset(data.coordinate, y2), tick: Offset(tickCoord, y1 + sign * s.tickMargin));
  }
}
