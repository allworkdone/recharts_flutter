// Draws the SVG part of a polar chart in the z layers of
// src/zIndex/DefaultZIndexes.tsx: Pie sectors (area, 100), then pie labels,
// label lines and LabelLists (label, 2000). Follows PieSectors, PieLabels
// (renderLabelLineItem, renderLabelItem, getTextAnchor), the Shape option
// rules of src/util/ActiveShapeUtils.tsx, and the polar half of
// src/component/Label.tsx (getAttrsOfPolarLabel) for LabelList entries.

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../animation.dart';
import '../components.dart';
import '../core/polar_utils.dart';
import '../engine/pie.dart';
import '../engine/polar_items.dart';
import '../engine/polar_scene.dart';
import '../polar_components.dart';
import '../util.dart';
import 'label.dart';
import 'polar_scene_painter.dart';
import 'radial_label.dart';
import 'sector.dart';
import 'shapes.dart';
import 'svg_text.dart';

enum PolarLayer { main, labels }

/// The active tooltip item, as sectors see it.
class PolarHoverState {
  const PolarHoverState({
    this.activeIndex,
    this.activeDataKey,
    this.activeItemId,
    this.polarCoordinate,
    this.cursorVisible = false,
    this.activeDataPoints = const [],
  });
  final int? activeIndex;
  final Object? activeDataKey;

  /// `selectActiveTooltipGraphicalItemId`.
  final String? activeItemId;

  /// The axis tooltip's coordinate with its polar parts; null for the 'item' event type and synced charts.
  final PolarCoordinate? polarCoordinate;

  /// Whether the Tooltip's cursor shows (axis event type, tooltip active).
  final bool cursorVisible;

  /// `useActiveTooltipDataPoints`: the payload of every tooltip row.
  final List<Object?> activeDataPoints;
}

/// Everything painters need for one build of a polar chart.
class PolarFrame {
  PolarFrame({
    required this.model,
    required this.textStyle,
    required this.textScaler,
    required this.pieAnimators,
    this.radarAnimators = const {},
    this.radarBaseLineAnimators = const {},
    this.radialBarAnimators = const {},
  });
  final PolarModel model;
  final TextStyle textStyle;
  final TextScaler textScaler;
  final Map<String, SeriesAnimator<PieSector>> pieAnimators;
  final Map<String, SeriesAnimator<RadarPoint>> radarAnimators, radarBaseLineAnimators;
  final Map<String, SeriesAnimator<RadialBarSector>> radialBarAnimators;

  /// Where the labels layer last drew text: SVG text sits above the sectors
  /// and takes the pointer from them.
  final List<Rect> labelBoxes = [];
}

/// `isActive` of a sector in PieSectors.
bool isActiveSector(PolarHoverState? h, PieModel pie, int index) =>
    h != null &&
    h.activeIndex == index &&
    (h.activeDataKey == null || pie.settings.dataKey == h.activeDataKey) &&
    (h.activeItemId == null || h.activeItemId == pie.id);

/// The `<Shape option>` a sector renders with: the active or inactive shape,
/// else the Pie's `shape`.
Object? sectorOption(PolarHoverState? h, PieModel pie, int index) {
  final s = pie.settings;
  final active = s.activeShape != null && s.activeShape != false && isActiveSector(h, pie, index);
  return (active ? s.activeShape : (h?.activeIndex != null ? s.inactiveShape : null)) ?? s.shape;
}

/// Sector props with an object option merged over them (`mergeShapeProps`).
SectorGeometry sectorGeometry(PieSector s, [SectorStyle? o]) => SectorGeometry(
      cx: o?.cx ?? s.cx,
      cy: o?.cy ?? s.cy,
      innerRadius: o?.innerRadius ?? s.innerRadius,
      outerRadius: o?.outerRadius ?? s.outerRadius,
      startAngle: o?.startAngle ?? s.startAngle,
      endAngle: o?.endAngle ?? s.endAngle,
      cornerRadius: o?.cornerRadius ?? s.cornerRadius ?? 0,
      forceCornerRadius: o?.forceCornerRadius ?? false,
      cornerIsExternal: o?.cornerIsExternal ?? false,
    );

/// The path a sector paints and hit tests; null when it renders nothing.
Path? piePath(PieSector s, Object? option) => sectorPath(sectorGeometry(s, option is SectorStyle ? option : null));

/// The sectors a Pie shows this frame (mid-animation they are interpolated).
List<PieSector>? currentPieSectors(PolarFrame frame, PieModel p) =>
    frame.pieAnimators[p.id]?.peek(interpolatePieSectors) ?? p.sectors;

/// Whether PieSectors renders the sector at [i] at all.
bool rendersSector(List<PieSector> sectors, int i) =>
    !(sectors[i].startAngle == 0 && sectors[i].endAngle == 0 && sectors.length != 1);

class PolarPainter extends CustomPainter {
  PolarPainter(this.layer, this.frame, {this.hover, super.repaint});

  final PolarLayer layer;
  final PolarFrame frame;
  final ValueListenable<PolarHoverState>? hover;

  PolarModel get m => frame.model;

  @override
  void paint(Canvas canvas, Size size) {
    final h = hover?.value;
    switch (layer) {
      case PolarLayer.main:
        // AllZIndexPortals: ascending zIndex, document order within one layer.
        final layers = [
          for (final p in m.pies) (p.settings.zIndex, () => _paintPie(canvas, p)),
          ...polarSceneLayers(canvas, frame, h),
        ];
        final order = [for (var i = 0; i < layers.length; i++) i]
          ..sort((a, b) => layers[a].$1 != layers[b].$1 ? layers[a].$1.compareTo(layers[b].$1) : a.compareTo(b));
        for (final i in order) {
          layers[i].$2();
        }
      case PolarLayer.labels:
        frame.labelBoxes.clear();
        for (final p in m.pies) {
          _paintPieLabels(canvas, p);
        }
        paintPolarSceneLabels(canvas, frame);
    }
  }

  @override
  bool shouldRepaint(PolarPainter old) => old.frame != frame || old.layer != layer;

  @override
  bool? hitTest(Offset position) => false;

  void _paintPie(Canvas canvas, PieModel p) {
    if (p.settings.hide || p.sectors == null) return;
    final sectors = frame.pieAnimators[p.id]?.step(interpolatePieSectors) ?? p.sectors!;
    final h = hover?.value;
    for (var i = 0; i < sectors.length; i++) {
      if (!rendersSector(sectors, i)) continue;
      final s = sectors[i];
      final option = sectorOption(h, p, i);
      if (option is PieShapePainter) {
        option(canvas, PieSectorShapeProps(sector: s, index: i, isActive: isActiveSector(h, p, i)));
        continue;
      }
      final style = option is SectorStyle ? option : null;
      final path = piePath(s, style);
      if (path == null) continue;
      final fill = style?.fill ?? s.fill;
      if (fill != null) canvas.drawPath(path, fillPaint(fill, opacity: style?.fillOpacity ?? s.fillOpacity ?? 1));
      final stroke = style?.stroke ?? s.stroke;
      final strokeWidth = style?.strokeWidth ?? s.strokeWidth ?? 1;
      if (stroke != null && strokeWidth > 0) {
        drawStroke(canvas, path, strokePaint(stroke, strokeWidth, opacity: style?.strokeOpacity ?? s.strokeOpacity ?? 1),
            style?.strokeDasharray);
      }
    }
  }

  // ---------------------------------------------------------------- labels

  void _paintPieLabels(Canvas canvas, PieModel p) {
    final sectors = p.sectors;
    if (p.settings.hide || sectors == null) return;
    // Labels show once the Pie stops animating (`showLabels={!isAnimating}`).
    if (frame.pieAnimators[p.id]?.isAnimating ?? false) return;
    final label = p.settings.label;
    if (label is LabelList) {
      _paintLabelList(canvas, label, sectors);
    } else if (label == true || label is PieLabel) {
      _paintOutsideLabels(canvas, p, sectors, label is PieLabel ? label : const PieLabel());
    }
    for (final list in p.settings.children.whereType<LabelList>()) {
      _paintLabelList(canvas, list, sectors);
    }
  }

  /// PieLabels: a label line and a text per sector.
  void _paintOutsideLabels(Canvas canvas, PieModel p, List<PieSector> sectors, PieLabel label) {
    final pie = p.settings;
    final offsetRadius = label.offsetRadius == 0 ? 20.0 : label.offsetRadius;
    for (var i = 0; i < sectors.length; i++) {
      final s = sectors[i];
      final midAngle = (s.startAngle + s.endAngle) / 2;
      final end = polarToCartesian(s.cx, s.cy, s.outerRadius + offsetRadius, midAngle);
      final line = pie.labelLine;
      if (line != false) {
        final points = [polarToCartesian(s.cx, s.cy, s.outerRadius, midAngle), end];
        if (line is PieLabelLinePainter) {
          line(canvas, PieLabelLineProps(sector: s, index: i, points: points, stroke: s.fill));
        } else {
          // Of a data entry's styles, only its color reaches the label line.
          final style = line is SvgStyle ? line : null;
          final stroke = style?.stroke ?? s.fill;
          final width = style?.strokeWidth ?? pie.strokeWidth ?? 1;
          if (stroke != null && width > 0) {
            final path = Path()
              ..moveTo(points[0].dx, points[0].dy)
              ..lineTo(points[1].dx, points[1].dy);
            drawStroke(canvas, path, strokePaint(stroke, width, opacity: style?.strokeOpacity ?? pie.strokeOpacity ?? 1),
                style?.strokeDasharray);
          }
        }
      }
      var style = frame.textStyle.copyWith(color: label.fill ?? s.fill ?? const Color(0xFF000000));
      if (label.fontSize != null) style = style.copyWith(fontSize: label.fontSize);
      final textAnchor = end.dx > s.cx ? TextAnchor.start : (end.dx < s.cx ? TextAnchor.end : TextAnchor.middle);
      final props = PieLabelProps(sector: s, index: i, x: end.dx, y: end.dy, textAnchor: textAnchor, style: style);
      if (label.content != null) {
        label.content!(canvas, props);
        continue;
      }
      final value = label.formatter != null ? label.formatter!(props) : getValueByDataKey(s.payload, pie.dataKey, s.value);
      if (value == null) continue;
      final text = jsString(value);
      paintSvgText(canvas, text, end.dx, end.dy, style: style, textAnchor: textAnchor, scaler: frame.textScaler);
      frame.labelBoxes.add(svgTextBox(text, end.dx, end.dy, style, frame.textScaler, textAnchor: textAnchor));
    }
  }

  /// LabelList over PieLabelListProvider's polar entries.
  void _paintLabelList(Canvas canvas, LabelList list, List<PieSector> sectors) {
    for (var i = 0; i < sectors.length; i++) {
      final s = sectors[i];
      final viewBox = PolarViewBox(
          cx: s.cx,
          cy: s.cy,
          innerRadius: s.innerRadius,
          outerRadius: s.outerRadius,
          startAngle: s.startAngle,
          endAngle: s.endAngle);
      final entry = LabelListEntry(value: s.value, payload: s.payload, viewBox: Rect.zero, fill: s.fill);
      final label = labelOfEntry(list, entry, i);
      paintPolarLabel(canvas, label, viewBox,
          index: i, baseStyle: frame.textStyle, scaler: frame.textScaler, boxes: frame.labelBoxes);
    }
  }
}

/// `getAttrsOfPolarLabel`; null for the radial positions (insideStart,
/// insideEnd, end), which Recharts draws along a textPath.
({double x, double y, TextAnchor textAnchor, TextVerticalAnchor verticalAnchor})? getAttrsOfPolarLabel(
    PolarViewBox v, double offset, LabelPosition position) {
  final midAngle = (v.startAngle + v.endAngle) / 2;
  switch (position) {
    case LabelPosition.insideStart || LabelPosition.insideEnd || LabelPosition.end:
      return null;
    case LabelPosition.outside:
      final p = polarToCartesian(v.cx, v.cy, v.outerRadius + offset, midAngle);
      return (
        x: p.dx,
        y: p.dy,
        textAnchor: p.dx >= v.cx ? TextAnchor.start : TextAnchor.end,
        verticalAnchor: TextVerticalAnchor.middle
      );
    case LabelPosition.center:
      return (x: v.cx, y: v.cy, textAnchor: TextAnchor.middle, verticalAnchor: TextVerticalAnchor.middle);
    case LabelPosition.centerTop:
      return (x: v.cx, y: v.cy, textAnchor: TextAnchor.middle, verticalAnchor: TextVerticalAnchor.start);
    case LabelPosition.centerBottom:
      return (x: v.cx, y: v.cy, textAnchor: TextAnchor.middle, verticalAnchor: TextVerticalAnchor.end);
    default:
      final p = polarToCartesian(v.cx, v.cy, (v.innerRadius + v.outerRadius) / 2, midAngle);
      return (x: p.dx, y: p.dy, textAnchor: TextAnchor.middle, verticalAnchor: TextVerticalAnchor.middle);
  }
}

/// `<Label viewBox={polar}>`.
void paintPolarLabel(Canvas canvas, Label label, PolarViewBox viewBox,
    {int? index, required TextStyle baseStyle, required TextScaler scaler, List<Rect>? boxes}) {
  final pos = getAttrsOfPolarLabel(viewBox, label.offset, label.position);
  if (pos == null) {
    _paintRadialLabel(canvas, label, viewBox, baseStyle, scaler, index, boxes);
    return;
  }
  final style = labelTextStyle(label, baseStyle);
  if (label.content != null) {
    final r = viewBox.outerRadius;
    label.content!(
      canvas,
      LabelProps(
        x: pos.x,
        y: pos.y,
        viewBox: Rect.fromLTWH(viewBox.cx - r, viewBox.cy - r, r * 2, r * 2),
        value: label.value,
        position: label.position,
        offset: label.offset,
        angle: label.angle,
        style: style,
        index: index,
      ),
    );
    return;
  }
  if (label.value == null) return;
  final value = label.formatter == null ? label.value : label.formatter!(label.value);
  if (value == null) return;
  final text = jsString(value), textAnchor = label.textAnchor ?? pos.textAnchor;
  paintSvgText(canvas, text, pos.x, pos.y,
      style: style,
      textAnchor: textAnchor,
      verticalAnchor: pos.verticalAnchor,
      angle: label.angle,
      breakAll: label.textBreakAll,
      measureStyle: baseStyle,
      scaler: scaler);
  if (label.angle == 0) {
    boxes?.add(svgTextBox(text, pos.x, pos.y, style, scaler, textAnchor: textAnchor, verticalAnchor: pos.verticalAnchor));
  }
}

/// `renderRadialLabel`: a `<Text textPath>` along the label's arc, with Text's `#808080` default fill.
void _paintRadialLabel(Canvas canvas, Label label, PolarViewBox viewBox, TextStyle baseStyle, TextScaler scaler, int? index,
    List<Rect>? boxes) {
  final path = radialLabelPath(viewBox, label.offset, label.position);
  final style = labelTextStyle(label, baseStyle);
  if (label.content != null) {
    final r = viewBox.outerRadius;
    label.content!(
      canvas,
      LabelProps(
        x: double.nan,
        y: double.nan,
        viewBox: Rect.fromLTWH(viewBox.cx - r, viewBox.cy - r, r * 2, r * 2),
        polarViewBox: viewBox,
        value: label.value,
        position: label.position,
        offset: label.offset,
        angle: label.angle,
        style: style,
        index: index,
      ),
    );
    return;
  }
  if (label.value == null) return;
  final value = label.formatter == null ? label.value : label.formatter!(label.value);
  if (value == null) return;
  paintSvgText(canvas, jsString(value), 0, 0,
      style: style,
      scaler: scaler,
      textPath: radialLabelArc(viewBox.cx, viewBox.cy, path.radius, path.labelAngle, path.direction),
      startOffset: label.startOffset,
      textAnchor: label.textAnchor ?? TextAnchor.start,
      centralBaseline: true,
      angle: label.angle,
      boxes: boxes);
}

/// The glyph cells of a one-line `<Text>` (the box SVG hit tests), placed
/// like [paintSvgText] places it.
Rect svgTextBox(String text, double x, double y, TextStyle style, TextScaler scaler,
    {TextAnchor textAnchor = TextAnchor.start, TextVerticalAnchor verticalAnchor = TextVerticalAnchor.end}) {
  final tp = textPainterFor(text, style, scaler);
  final em = scaler.scale(style.fontSize ?? 14);
  final baseline = y +
      switch (verticalAnchor) {
        TextVerticalAnchor.start => 0.71 * em,
        TextVerticalAnchor.middle => 0.355 * em,
        TextVerticalAnchor.end => 0.0,
      };
  final left = switch (textAnchor) {
    TextAnchor.start => x,
    TextAnchor.middle => x - tp.width / 2,
    TextAnchor.end => x - tp.width,
  };
  return Rect.fromLTWH(left, baseline - tp.computeDistanceToActualBaseline(TextBaseline.alphabetic), tp.width, tp.height);
}
