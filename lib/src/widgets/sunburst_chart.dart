// SunburstChart: src/chart/SunburstChart.tsx. Sectors come from
// computeSunburst (lib/src/sunburst.dart) and are drawn like <Sector> with
// a <Text> label each; the tooltip is the 'item' event type (hover and
// click state as in tooltipSlice.ts), driven by the sector under the pointer.

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kTouchSlop, PointerDeviceKind;
import 'package:flutter/widgets.dart';

import '../components.dart';
import '../render/polar_painter.dart' show svgTextBox;
import '../render/sector.dart';
import '../render/shapes.dart';
import '../render/svg_text.dart';
import '../sunburst.dart';
import '../util.dart';
import 'responsive_container.dart';
import 'tooltip.dart';

/// `textOptions` (the `<Text>` props of defaultTextProps). Like in Recharts a
/// given object replaces the defaults as a whole; unset fields are the Text
/// defaults (fill '#808080', no stroke, normal weight, inherited size,
/// verticalAnchor 'end'). textAnchor, x and y are always set by the chart.
class SunburstTextOptions {
  const SunburstTextOptions({
    this.fontWeight,
    this.fontSize,
    this.fontStyle,
    this.letterSpacing,
    this.fill,
    this.stroke,
    this.strokeWidth = 1,
    this.fillOpacity = 1,
    this.strokeOpacity = 1,
    this.strokeBeforeFill = false,
    this.fontFamily,
    this.verticalAnchor = TextVerticalAnchor.end,
    this.angle = 0,
    this.width,
    this.maxLines,
    this.breakAll = false,
    this.scaleToFit = false,
    this.dx = 0,
    this.dy = 0,
    this.pointerEventsNone = false,
  });

  /// `{fontWeight: 'bold', paintOrder: 'stroke fill', fontSize: '.75rem', stroke: '#FFF', fill: 'black', pointerEvents: 'none'}`.
  static const defaults = SunburstTextOptions(
    fontWeight: FontWeight.bold,
    fontSize: 12,
    fill: Color(0xFF000000),
    stroke: Color(0xFFFFFFFF),
    strokeBeforeFill: true,
    pointerEventsNone: true,
  );

  final FontWeight? fontWeight;

  /// Pixels (`.75rem` is 12).
  final double? fontSize;
  final FontStyle? fontStyle;
  final double? letterSpacing;
  final Color? fill, stroke;
  final double strokeWidth, fillOpacity, strokeOpacity;

  /// `paintOrder: 'stroke fill'`.
  final bool strokeBeforeFill;
  final String? fontFamily;
  final TextVerticalAnchor verticalAnchor;
  final double angle;
  final double? width;
  final int? maxLines;
  final bool breakAll, scaleToFit;
  final double dx, dy;

  /// `pointerEvents: 'none'`; otherwise labels take the pointer from the sector under them.
  final bool pointerEventsNone;
}

typedef SunburstNodeHandler = void Function(Map<String, Object?> node, PointerEvent event);

int _nextId = 0;

/// src/chart/SunburstChart.tsx. [data] is the root node: maps with `name`,
/// [dataKey] (default 'value'), an optional `fill` [Color] and `children`.
class SunburstChart extends StatefulWidget {
  SunburstChart({
    super.key,
    required this.data,
    this.width,
    this.height,
    this.padding = 2,
    this.dataKey = 'value',
    this.nameKey = 'name',
    this.ringPadding = 2,
    this.innerRadius = 50,
    this.outerRadius,
    this.cx,
    this.cy,
    this.startAngle = 0,
    this.endAngle = 360,
    this.fill = const Color(0xFF333333),
    this.stroke = const Color(0xFFFFFFFF),
    this.textOptions = SunburstTextOptions.defaults,
    this.onMouseEnter,
    this.onMouseLeave,
    this.onClick,
    this.children = const [],
    String? id,
  }) : id = id ?? 'recharts-sunburst-${_nextId++}';

  final Map<String, Object?> data;
  final double? width, height;
  final double padding;
  final String dataKey;

  /// A String, an int index or a function from the node to its name.
  final Object? nameKey;
  final double ringPadding, innerRadius;
  final double? outerRadius, cx, cy;
  final double startAngle, endAngle;
  final Color fill;
  final Color? stroke;
  final SunburstTextOptions textOptions;
  final SunburstNodeHandler? onMouseEnter, onMouseLeave;
  final void Function(Map<String, Object?> node)? onClick;

  /// The [Tooltip] (other elements are not rendered by SunburstChart).
  final List<RechartsElement> children;
  final String id;

  @override
  State<SunburstChart> createState() => _SunburstChartState();
}

class _Interaction {
  const _Interaction({this.active = false, this.index, this.coordinate, this.dataKey});
  final bool active;
  final String? index;
  final Offset? coordinate;
  final Object? dataKey;
  _Interaction inactive() => _Interaction(index: index, coordinate: coordinate, dataKey: dataKey);
}

class _View {
  const _View({this.active = false, this.coordinate, this.payload = const []});
  final bool active;
  final Offset? coordinate;
  final List<TooltipPayloadEntry> payload;
}

class _ViewNotifier extends ChangeNotifier implements ValueListenable<_View> {
  _View _value = const _View();
  @override
  _View get value => _value;
  void set(_View v, {bool notify = true}) {
    _value = v;
    if (notify) notifyListeners();
  }
}

class _SunburstChartState extends State<SunburstChart> with TickerProviderStateMixin {
  final _ViewNotifier _view = _ViewNotifier();
  _Interaction _hover = const _Interaction();
  _Interaction _click = const _Interaction();
  int? _hovered, _downItem;
  Offset? _downPosition;
  SunburstLayout? _layout;
  List<Path?> _paths = const [];
  List<Rect?> _labelBoxes = const [];
  Tooltip? _tooltip;

  @override
  void initState() {
    super.initState();
    PaintingBinding.instance.systemFonts.addListener(_onFontsChanged);
  }

  void _onFontsChanged() {
    clearTextCache();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_onFontsChanged);
    _view.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- tooltip

  _View _computeView() {
    final layout = _layout, tooltip = _tooltip;
    if (layout == null) return const _View();
    final mouse = tooltip?.trigger == TooltipTrigger.click ? _click : _hover;
    var state = mouse;
    if (!mouse.active) {
      if (mouse.index != null) {
        if (tooltip?.active == true) state = _Interaction(active: true, index: mouse.index, coordinate: mouse.coordinate, dataKey: mouse.dataKey);
      } else if (tooltip?.defaultIndex != null) {
        final i = '[${tooltip!.defaultIndex}]';
        state = _Interaction(active: true, index: i, coordinate: layout.positions[jsString(layout.byIndex[i]?['name'])]);
      }
    }
    final node = state.index == null ? null : layout.byIndex[state.index];
    final active = tooltip?.active ?? (state.active && node != null);
    var payload = const <TooltipPayloadEntry>[];
    if (active && node != null) {
      final w = widget;
      final name = getValueByDataKey(node, w.nameKey);
      payload = [
        TooltipPayloadEntry(
          dataKey: w.dataKey,
          name: name == null ? (w.nameKey == null ? w.dataKey : null) : jsString(name),
          value: getValueByDataKey(node, w.dataKey),
          payload: node,
          color: w.fill,
          fill: w.fill,
          stroke: w.stroke,
          unit: '',
        ),
      ];
      if (tooltip?.filterNull ?? true) payload = [for (final e in payload) if (e.value != null) e];
    }
    return _View(active: active, coordinate: state.coordinate, payload: payload);
  }

  void _refresh() => _view.set(_computeView());

  // ---------------------------------------------------------------- input

  int? _sectorAt(Offset p) {
    final layout = _layout;
    if (layout == null) return null;
    final width = widget.padding;
    for (var i = layout.sectors.length - 1; i >= 0; i--) {
      // A label is painted above its own sector, so it takes the pointer first.
      if (_labelBoxes[i]?.contains(p) ?? false) return null;
      final path = _paths[i];
      if (path == null) continue;
      if (path.contains(p) || (widget.stroke != null && strokeContains(path, p, width))) return i;
    }
    return null;
  }

  Map<String, Object?> _node(int i) => _layout!.sectors[i].node;

  Offset? _position(int i) => _layout!.positions[jsString(_node(i)['name'])];

  /// onMouseEnter / onMouseLeave of the sector under the pointer.
  void _setHover(int? hit, PointerEvent e) {
    if (hit == _hovered || !mounted) return;
    final old = _hovered;
    _hovered = hit;
    if (old != null) {
      widget.onMouseLeave?.call(_node(old), e);
      _hover = _hover.inactive();
    }
    if (hit != null) {
      widget.onMouseEnter?.call(_node(hit), e);
      _hover = _Interaction(active: true, index: _node(hit)['tooltipIndex'] as String, coordinate: _position(hit), dataKey: widget.dataKey);
    }
    _refresh();
  }

  void _onPointerDown(PointerDownEvent e) {
    _downPosition = e.localPosition;
    _downItem = _sectorAt(e.localPosition);
    if (e.kind == PointerDeviceKind.mouse) _setHover(_downItem, e);
  }

  void _onPointerUp(PointerUpEvent e) {
    final down = _downPosition;
    _downPosition = null;
    if (down == null) return;
    final touch = e.kind != PointerDeviceKind.mouse;
    if (touch && (e.localPosition - down).distance > kTouchSlop) return;
    final item = _sectorAt(e.localPosition);
    if (touch) _setHover(item, e);
    // A click targets the common ancestor of the mousedown and mouseup targets.
    if (item != null && (touch || item == _downItem)) {
      final node = _node(item);
      widget.onClick?.call(node);
      _click = _Interaction(active: true, index: node['tooltipIndex'] as String, coordinate: _position(item), dataKey: widget.dataKey);
      _refresh();
    }
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final responsive = ResponsiveContainerScope.maybeOf(context);
    return LayoutBuilder(builder: (context, constraints) {
      final width = responsive?.width ?? widget.width ?? (constraints.hasBoundedWidth ? constraints.maxWidth : 0.0);
      final height = responsive?.height ?? widget.height ?? (constraints.hasBoundedHeight ? constraints.maxHeight : 0.0);
      if (width <= 0 || height <= 0) return SizedBox(width: width, height: height);
      return _buildChart(context, Size(width, height));
    });
  }

  Widget _buildChart(BuildContext context, Size size) {
    final w = widget;
    final base = DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    final reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final layout = _layout = computeSunburst(
      data: w.data,
      width: size.width,
      height: size.height,
      dataKey: w.dataKey,
      padding: w.padding,
      ringPadding: w.ringPadding,
      innerRadius: w.innerRadius,
      outerRadius: w.outerRadius,
      cx: w.cx,
      cy: w.cy,
      startAngle: w.startAngle,
      endAngle: w.endAngle,
      fill: w.fill,
    );
    _paths = [
      for (final s in layout.sectors)
        sectorPath(SectorGeometry(
            cx: w.cx ?? size.width / 2,
            cy: w.cy ?? size.height / 2,
            innerRadius: s.innerRadius,
            outerRadius: s.outerRadius,
            startAngle: s.startAngle,
            endAngle: s.endAngle)),
    ];
    final tooltip = _tooltip = w.children.whereType<Tooltip>().firstOrNull;
    _view.set(_computeView(), notify: false);

    final painter = _SunburstPainter(layout, _paths, w, base, scaler);
    final o = w.textOptions;
    _labelBoxes = [
      for (final s in layout.sectors)
        o.pointerEventsNone || o.angle != 0 || s.node[w.dataKey] == null || o.scaleToFit
            ? null
            : svgTextBox(jsString(s.node[w.dataKey]), s.textPosition.dx + o.dx, s.textPosition.dy + o.dy,
                painter.fillStyle, scaler,
                textAnchor: TextAnchor.middle, verticalAnchor: o.verticalAnchor),
    ];
    final stack = Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: painter))),
        if (tooltip != null)
          Positioned.fill(
            child: IgnorePointer(
              child: ListenableBuilder(
                listenable: _view,
                builder: (context, _) {
                  final v = _view.value;
                  return tooltipLayer(tooltip,
                      vsync: this,
                      reducedMotion: reducedMotion,
                      viewBox: Offset.zero & size,
                      active: v.active,
                      payload: v.payload,
                      coordinate: v.coordinate);
                },
              ),
            ),
          ),
      ],
    );

    return SizedBox.fromSize(
      size: size,
      child: TapRegion(
        onTapOutside: (e) {
          if (e.kind == PointerDeviceKind.touch && _hover.active) _setHover(null, e as PointerEvent);
        },
        child: MouseRegion(
          onEnter: (e) => _setHover(_sectorAt(e.localPosition), e),
          onHover: (e) => _setHover(_sectorAt(e.localPosition), e),
          onExit: (e) => _setHover(null, e),
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _onPointerDown,
            onPointerMove: (e) {
              final hit = _sectorAt(e.localPosition);
              if (e.kind == PointerDeviceKind.mouse || hit != null) _setHover(hit, e);
            },
            onPointerUp: _onPointerUp,
            onPointerCancel: (_) => _downPosition = null,
            child: stack,
          ),
        ),
      ),
    );
  }
}

class _SunburstPainter extends CustomPainter {
  _SunburstPainter(this.layout, this.paths, this.w, TextStyle base, this.scaler) {
    final o = w.textOptions;
    final style = base.copyWith(
        fontSize: o.fontSize,
        fontWeight: o.fontWeight ?? FontWeight.normal,
        fontStyle: o.fontStyle,
        letterSpacing: o.letterSpacing,
        fontFamily: o.fontFamily);
    fillStyle = style.copyWith(foreground: fillPaint(o.fill ?? const Color(0xFF808080), opacity: o.fillOpacity));
    strokeStyle = o.stroke == null
        ? null
        : style.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..color = o.stroke!.withValues(alpha: o.stroke!.a * o.strokeOpacity)
              ..strokeWidth = o.strokeWidth
              ..strokeMiterLimit = 4);
    strokeFirst = o.strokeBeforeFill;
  }

  final SunburstLayout layout;
  final List<Path?> paths;
  final SunburstChart w;
  final TextScaler scaler;
  late final TextStyle fillStyle;
  late final TextStyle? strokeStyle;
  late final bool strokeFirst;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < layout.sectors.length; i++) {
      final s = layout.sectors[i];
      final path = paths[i];
      if (path != null) {
        canvas.drawPath(path, fillPaint(s.fill));
        if (w.stroke != null && w.padding > 0) canvas.drawPath(path, strokePaint(w.stroke!, w.padding));
      }
      final v = s.node[w.dataKey];
      if (v == null) continue;
      final text = jsString(v);
      final o = w.textOptions;
      void draw(TextStyle st) => paintSvgText(canvas, text, s.textPosition.dx + o.dx, s.textPosition.dy + o.dy,
          style: st,
          measureStyle: fillStyle,
          textAnchor: TextAnchor.middle,
          verticalAnchor: o.verticalAnchor,
          angle: o.angle,
          width: o.width,
          maxLines: o.maxLines,
          breakAll: o.breakAll,
          scaleToFit: o.scaleToFit,
          scaler: scaler);
      if (strokeFirst && strokeStyle != null) draw(strokeStyle!);
      draw(fillStyle);
      if (!strokeFirst && strokeStyle != null) draw(strokeStyle!);
    }
  }

  @override
  bool shouldRepaint(_SunburstPainter old) => true;

  @override
  bool? hitTest(Offset position) => false;
}
