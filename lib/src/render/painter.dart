// Draws the SVG part of a cartesian chart, split into layers that follow
// Recharts' DefaultZIndexes (src/zIndex/DefaultZIndexes.tsx):
//   background: grid (-100), bar background (-50)
//   cursorBelow: BarChart cursor rectangle (200)
//   main: bars (300), lines + reference lines (400), axis lines (500), dots (600)
//   activeBar: Bar `activeBar` (1000)
//   overlay: cursor line (1100), active dots (1200)
//   labels: tick labels and reference line labels (2000)
// Geometry follows CartesianAxis.tsx (getTickLineCoord, AxisLine),
// CartesianGrid.tsx, Line.tsx/LineDrawShape.tsx, Dots.tsx, ActivePoints.tsx,
// Bar.tsx/Rectangle.tsx (BarRectangleWithActiveState), ActiveShapeUtils.tsx,
// ReferenceLine.tsx and Cursor.tsx.

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../animation.dart';
import '../components.dart';
import '../core/curve.dart';
import '../engine/axis.dart';
import '../engine/get_ticks.dart';
import '../engine/model.dart';
import '../util.dart';
import 'shapes.dart';
import 'svg_text.dart';

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
  });
  final CartesianModel model;
  final List<RechartsElement> children;
  final TextStyle textStyle;
  final TextScaler textScaler;
  final Map<String, SeriesAnimator<BarRect>> barAnimators;
  final Map<String, SeriesAnimator<LinePoint>> lineAnimators;
  final Map<String, AnimatedLineLength> lineLengths;

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

  Rect? _clipFor(GraphicalItem item) {
    final x = _axisSettings(true, item.xAxisId);
    final y = _axisSettings(false, item.yAxisId);
    final needX = x?.allowDataOverflow ?? false, needY = y?.allowDataOverflow ?? false;
    if (!needX && !needY) return null;
    final p = m.offset.plotArea;
    return Rect.fromLTRB(
      needX ? p.left : p.left - p.width / 2,
      needY ? p.top : p.top - p.height / 2,
      needX ? p.right : p.right + p.width / 2,
      needY ? p.bottom : p.bottom + p.height / 2,
    );
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

  void _paintMain(Canvas canvas) {
    final lineSteps = <String, List<LinePoint>>{};
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
    // Lines and reference lines (z 400), in document order.
    for (final c in frame.children) {
      if (c is Line) {
        final s = m.series.where((s) => identical(s.item.element, c)).firstOrNull;
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
    // Dots (z 600)
    for (final s in m.series) {
      final points = lineSteps[s.item.id];
      if (points == null) continue;
      _withClip(canvas, _clipFor(s.item), () => _paintDots(canvas, s.item, s.item.element as Line, points));
    }
  }

  /// Rectangle with `{...barProps, ...entry (incl. Cell props), ...active}`.
  void _paintBar(Canvas canvas, Bar bar, BarRect r, SvgStyle? active) {
    if (!r.x.isFinite || !r.y.isFinite || r.width == 0 || r.height == 0) return;
    final path = barPath(bar, r, active);
    final fill = active?.fill ?? r.cell?.fill ?? bar.fill ?? const Color(0xFF000000);
    canvas.drawPath(path, fillPaint(fill, opacity: active?.fillOpacity ?? r.cell?.fillOpacity ?? bar.fillOpacity ?? 1));
    final stroke = active?.stroke ?? r.cell?.stroke ?? bar.stroke;
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
    final path = linePath([for (final p in points) p.x == null || p.y == null ? null : Offset(p.x!, p.y!)], line.type,
        layout: m.layout, connectNulls: line.connectNulls);
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

  void _paintDots(Canvas canvas, GraphicalItem item, Line line, List<LinePoint> points) {
    if (!(line.dot != false || points.length == 1)) return;
    final style = line.dot is SvgStyle ? line.dot as SvgStyle : null;
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      if (p.x == null || p.y == null) continue;
      final props = DotProps(
        cx: p.x!,
        cy: p.y!,
        r: style?.r ?? 3,
        index: i,
        value: p.value,
        payload: p.payload,
        dataKey: line.dataKey,
        fill: style?.fill ?? line.fill,
        stroke: style?.stroke ?? line.stroke,
        strokeWidth: style?.strokeWidth ?? line.strokeWidth,
      );
      if (line.dot is DotPainter) {
        (line.dot as DotPainter)(canvas, props);
      } else {
        _paintDot(canvas, props, style?.strokeDasharray ?? line.strokeDasharray);
      }
    }
  }

  void _paintDot(Canvas canvas, DotProps d, List<double>? dash) {
    final center = Offset(d.cx, d.cy);
    if (d.fill != null) canvas.drawCircle(center, d.r, fillPaint(d.fill!));
    if (d.stroke != null && d.strokeWidth > 0) {
      final path = Path()..addOval(Rect.fromCircle(center: center, radius: d.r));
      drawStroke(canvas, path, strokePaint(d.stroke!, d.strokeWidth), dash);
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
          width: s is YAxis ? s.width : null,
          scaler: frame.textScaler);
    }
  }

  void _paintLabels(Canvas canvas) {
    for (final c in frame.children) {
      if (c is CartesianAxisElement) {
        for (final a in m.axes.where((a) => a.settings == c)) {
          _paintTickLabels(canvas, a);
        }
      } else if (c is ReferenceLine && c.label != null) {
        final r = m.referenceLines.where((r) => r.settings == c).firstOrNull;
        if (r == null) continue;
        final rect = Rect.fromPoints(r.p1, r.p2);
        paintSvgText(canvas, c.label!, rect.left + rect.width / 2, rect.top + rect.height / 2,
            style: frame.textStyle.copyWith(color: const Color(0xFF808080)),
            textAnchor: TextAnchor.middle,
            verticalAnchor: TextVerticalAnchor.middle,
            scaler: frame.textScaler);
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
      if (style?.stroke != null) {
        drawStroke(canvas, path, strokePaint(style!.stroke!, style.strokeWidth ?? 1), style.strokeDasharray);
      }
    } else {
      final pts = cursorPoints(m.layout, h.coordinate!, m.offset);
      final path = Path()
        ..moveTo(pts[0].dx, pts[0].dy)
        ..lineTo(pts[1].dx, pts[1].dy);
      drawStroke(canvas, path, strokePaint(style?.stroke ?? const Color(0xFFCCCCCC), style?.strokeWidth ?? 1),
          style?.strokeDasharray);
    }
  }

  void _paintActiveDots(Canvas canvas) {
    final h = hover?.value;
    if (h == null || h.activeDataPoints.isEmpty) return;
    for (final s in m.series) {
      final line = s.item.element;
      if (line is! Line || s.item.hide || line.activeDot == false || s.points == null) continue;
      final p = s.points!.where((p) => h.activeDataPoints.any((d) => identical(d, p.payload))).firstOrNull;
      if (p == null || p.x == null || p.y == null) continue;
      final style = line.activeDot is SvgStyle ? line.activeDot as SvgStyle : null;
      final props = DotProps(
        cx: p.x!,
        cy: p.y!,
        r: style?.r ?? 4,
        index: s.points!.indexOf(p),
        value: p.value,
        payload: p.payload,
        dataKey: line.dataKey,
        fill: style?.fill ?? line.stroke,
        stroke: style?.stroke ?? const Color(0xFFFFFFFF),
        strokeWidth: style?.strokeWidth ?? 2,
      );
      _withClip(canvas, _clipFor(s.item), () {
        if (line.activeDot is DotPainter) {
          (line.activeDot as DotPainter)(canvas, props);
        } else {
          _paintDot(canvas, props, style?.strokeDasharray);
        }
      });
    }
  }
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
