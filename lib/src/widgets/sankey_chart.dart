// Sankey: src/chart/Sankey.tsx. Links are painted first, nodes above them; each
// is a Layer whose mouseenter / mouseleave / click set the tooltip item state
// (tooltipSlice: itemInteraction hover and click) under the 'item' event type,
// with the tooltip anchored at the node centre or the link midpoint. Default
// shapes: a Rectangle (fill #0088fe, fill-opacity 0.8) and a stroked cubic path
// (stroke #333, stroke-opacity 0.2). Pointer handling follows polar_chart.dart.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kTouchSlop, PointerDeviceKind;
import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;
import 'package:flutter/widgets.dart';

import '../components.dart';
import '../util.dart' show jsString;
import '../render/sector.dart' show strokeContains;
import '../render/shapes.dart';
import '../sankey.dart';
import 'responsive_container.dart';
import 'tooltip.dart';

/// `SankeyNodeOptions` as a callback: paints in the chart's coordinate space
/// ([size] is the chart). The returned path, if any, is what hover and click
/// hit test (Recharts' events sit on the wrapping `<g>`, so anything painted
/// reacts); null falls back to the default Rectangle.
typedef SankeyNodePainter = Path? Function(Canvas canvas, Size size, SankeyNodeProps props);

/// `SankeyLinkOptions` as a callback; null falls back to the default link path.
typedef SankeyLinkPainter = Path? Function(Canvas canvas, Size size, SankeyLinkProps props);

/// `onClick` / `onMouseEnter` / `onMouseLeave`: [item] is a [SankeyNodeProps] or a [SankeyLinkProps].
typedef SankeyEventHandler = void Function(Object item, SankeyElementType type, PointerEvent event);

/// `Sankey` with `sankeyDefaultProps`.
///
/// [node] is an [SvgStyle] merged over the default Rectangle or a
/// [SankeyNodePainter]; [link] an [SvgStyle] or a [SankeyLinkPainter]. A custom
/// painter's shape is its returned hit path, else the default shape.
class Sankey extends StatefulWidget {
  const Sankey({
    super.key,
    this.width,
    this.height,
    required this.data,
    this.nodePadding = 10,
    this.nodeWidth = 10,
    this.linkCurvature = 0.5,
    this.iterations = 32,
    this.node,
    this.link,
    this.margin = const Margin.all(5),
    this.sort = true,
    this.verticalAlign = SankeyVerticalAlign.justify,
    this.align = SankeyAlign.justify,
    this.dataKey = 'value',
    this.nameKey = 'name',
    this.name,
    this.fill,
    this.stroke,
    this.strokeWidth,
    this.accessibilityLayer = true,
    this.title,
    this.desc,
    this.onClick,
    this.onMouseEnter,
    this.onMouseLeave,
    this.children = const [],
  });

  final double? width;
  final double? height;
  final SankeyData data;
  final double nodePadding;
  final double nodeWidth;
  final double linkCurvature;
  final int iterations;
  final Object? node;
  final Object? link;
  final Margin margin;
  final bool sort;
  final SankeyVerticalAlign verticalAlign;
  final SankeyAlign align;

  /// Only read by the tooltip (the link value is always `value`).
  final Object dataKey;
  final Object nameKey;
  final String? name;

  /// The tooltip entry colour.
  final Color? fill;

  /// Set on the svg: inherited by default nodes (not links) and put in the tooltip entry.
  final Color? stroke;
  final double? strokeWidth;
  final bool accessibilityLayer;
  final String? title;
  final String? desc;
  final SankeyEventHandler? onClick;
  final SankeyEventHandler? onMouseEnter;
  final SankeyEventHandler? onMouseLeave;

  /// Only a [Tooltip] is used.
  final List<RechartsElement> children;

  @override
  State<Sankey> createState() => _SankeyState();
}

/// What the sankey currently has under the pointer.
typedef _Hit = ({SankeyElementType type, int index});

class _Interaction {
  const _Interaction({this.active = false, this.hit, this.coordinate});
  final bool active;
  final _Hit? hit;
  final Offset? coordinate;
  _Interaction inactive() => _Interaction(hit: hit, coordinate: coordinate);
}

class _View {
  const _View({this.active = false, this.coordinate, this.payload = const [], this.activeIndex});
  final bool active;

  /// 'node-N' / 'link-N' (Recharts' tooltip index), '0' for the keyboard.
  final Object? activeIndex;
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

class _Model {
  _Model(this.size, this.nodes, this.links, this.viewBox)
      : nodeHit = List.filled(nodes.length, null),
        linkHit = List.filled(links.length, null);
  final Size size;

  /// Hit paths returned by custom painters, filled while painting.
  final List<Path?> nodeHit, linkHit;
  final List<SankeyNodeProps> nodes;
  final List<SankeyLinkProps> links;
  final Rect viewBox;
}

class _SankeyState extends State<Sankey> with TickerProviderStateMixin {
  final _ViewNotifier _view = _ViewNotifier();
  _Interaction _hover = const _Interaction();
  _Interaction _click = const _Interaction();
  _Interaction _keyboard = const _Interaction();
  bool _keyboardIndexSet = false;
  final FocusNode _focusNode = FocusNode(debugLabel: 'recharts sankey');
  _Hit? _hovered;
  _Hit? _downHit;
  Offset? _downPosition;
  _Model? _model;
  Sankey? _modelWidget;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _view.dispose();
    super.dispose();
  }

  Tooltip? get _tooltip => widget.children.whereType<Tooltip>().firstOrNull;

  // The layout in `useMemo`: reruns only when its inputs change.
  _Model _modelFor(Size size) {
    final w = widget, old = _modelWidget, m = _model;
    if (m != null &&
        old != null &&
        m.size == size &&
        identical(old.data, w.data) &&
        old.margin == w.margin &&
        old.iterations == w.iterations &&
        old.nodeWidth == w.nodeWidth &&
        old.nodePadding == w.nodePadding &&
        old.sort == w.sort &&
        old.linkCurvature == w.linkCurvature &&
        old.align == w.align &&
        old.verticalAlign == w.verticalAlign &&
        identical(old.node, w.node) &&
        identical(old.link, w.link)) {
      return m;
    }
    _modelWidget = w;
    final margin = w.margin;
    final viewBox = sankeyViewBox(size, margin);
    final computed = computeSankeyData(
      data: w.data,
      width: size.width - margin.left - margin.right,
      height: size.height - margin.top - margin.bottom,
      iterations: w.iterations,
      nodeWidth: w.nodeWidth,
      nodePadding: w.nodePadding,
      sort: w.sort,
      verticalAlign: w.verticalAlign,
      align: w.align,
    );
    final linkStyle = w.link is SvgStyle ? w.link as SvgStyle : null;
    final nodeStyle = w.node is SvgStyle ? w.node as SvgStyle : null;
    final links = <SankeyLinkProps>[];
    for (var i = 0; i < computed.links.length; i++) {
      final p = buildLinkProps(
          link: computed.links[i],
          nodes: computed.nodes,
          top: margin.top,
          left: margin.left,
          i: i,
          linkCurvature: w.linkCurvature,
          style: linkStyle);
      if (p != null) links.add(p);
    }
    final nodes = [
      for (var i = 0; i < computed.nodes.length; i++)
        buildNodeProps(node: computed.nodes[i], top: margin.top, left: margin.left, i: i, style: nodeStyle),
    ];
    return _model = _Model(size, nodes, links, viewBox);
  }

  // -------------------------------------------------------------- tooltip state

  _View _computeView() {
    final m = _model, tooltip = _tooltip;
    if (m == null) return const _View();
    final mouse = tooltip?.trigger == TooltipTrigger.click ? _click : _hover;
    // combineTooltipInteractionState: active mouse, active keyboard, then the sticky `active` prop.
    String? defaultKey;
    final state = mouse.active
        ? mouse
        : _keyboard.active
            ? _keyboard
            : (mouse.hit != null && tooltip?.active == true)
            ? _Interaction(active: true, hit: mouse.hit, coordinate: mouse.coordinate)
            : (mouse.hit == null && tooltip?.defaultIndex != null)
            // defaultIndex activates with no coordinate: the box sits at (0,0).
            ? _Interaction(active: true, hit: _parseHit(defaultKey = jsString(tooltip!.defaultIndex), m))
            : _Interaction(coordinate: mouse.coordinate);
    // The keyboard's index '0' is non-null, so it activates without an item.
    final isActive = tooltip?.active ?? (state.active && (state.hit != null || defaultKey != null || identical(state, _keyboard)));
    var payload = const <TooltipPayloadEntry>[];
    final hit = state.hit;
    if (isActive && (hit != null || identical(state, _keyboard))) {
      // The keyboard's index '0' is no 'node-0': the searcher finds nothing.
      final entry = sankeyTooltipEntry(
        type: hit?.type ?? SankeyElementType.node,
        index: hit?.index ?? -1,
        nodes: m.nodes,
        links: m.links,
        dataKey: widget.dataKey,
        nameKey: widget.nameKey,
        name: widget.name,
        fill: widget.fill,
        stroke: widget.stroke,
      );
      if (!(tooltip?.filterNull ?? true) || entry.value != null) {
        payload = [entry];
      }
    }
    final hitIndex = hit == null ? null : '${hit.type.name}-${hit.index}';
    return _View(
        active: isActive,
        coordinate: state.coordinate,
        payload: payload,
        activeIndex: hitIndex ?? defaultKey ?? (identical(state, _keyboard) ? '0' : null));
  }

  /// `sankeyPayloadSearcher`: 'node-N' / 'link-N' finds `nodes[N]` / `links[N]`; anything else finds nothing.
  static _Hit? _parseHit(String key, _Model m) {
    final parts = key.split('-');
    final index = parts.length > 1 ? int.tryParse(parts[1]) : null;
    if (index == null || index < 0) return null;
    return switch (parts[0]) {
      'node' when index < m.nodes.length => (type: SankeyElementType.node, index: index),
      'link' when index < m.links.length => (type: SankeyElementType.link, index: index),
      _ => null,
    };
  }

  void _refreshView() => _view.set(_computeView());

  // -------------------------------------------------------------- keyboard

  /// `focusAction`: the first focus activates the keyboard tooltip at index '0'.
  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      if (!widget.accessibilityLayer || _keyboard.active || _keyboardIndexSet) return;
      _keyboardIndexSet = true;
      _keyboard = const _Interaction(active: true);
    } else {
      // `blurAction`: inactive, index kept.
      if (!_keyboard.active) return;
      _keyboard = _keyboard.inactive();
    }
    _refreshView();
  }

  /// `keyDownAction`: Enter toggles; arrows return early (no tooltip data).
  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent || !widget.accessibilityLayer) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.enter && _keyboardIndexSet) {
      _keyboard = _keyboard.active ? _keyboard.inactive() : const _Interaction(active: true);
      _refreshView();
    }
    return KeyEventResult.ignored;
  }

  // -------------------------------------------------------------- input

  Object _item(_Hit h) => h.type == SankeyElementType.node ? _model!.nodes[h.index] : _model!.links[h.index];

  Offset _coordinate(_Hit h) => h.type == SankeyElementType.node
      ? sankeyNodeTooltipCoordinate(_model!.nodes[h.index])
      : sankeyLinkTooltipCoordinate(_model!.links[h.index]);

  static Path _linkPath(SankeyLinkProps p) => Path()
    ..moveTo(p.sourceX, p.sourceY)
    ..cubicTo(p.sourceControlX, p.sourceY, p.targetControlX, p.targetY, p.targetX, p.targetY);

  static Path? _nodePath(SankeyNodeProps p) {
    if (!(p.width != 0 && p.height != 0) || p.x.isNaN || p.y.isNaN || p.width.isNaN || p.height.isNaN) return null;
    return rectanglePath(p.x, p.y, p.width, p.height, p.style?.radius ?? 0);
  }

  /// Topmost painted element under [p]: nodes over links, later over earlier.
  _Hit? _hitAt(Offset p) {
    final m = _model;
    if (m == null) return null;
    for (var i = m.nodes.length - 1; i >= 0; i--) {
      final n = m.nodes[i];
      final custom = m.nodeHit[i];
      final path = custom ?? _nodePath(n);
      if (path == null) continue;
      final stroke = n.style?.stroke ?? widget.stroke;
      if (path.contains(p) ||
          (custom == null && stroke != null && strokeContains(path, p, n.style?.strokeWidth ?? widget.strokeWidth ?? 1))) {
        return (type: SankeyElementType.node, index: i);
      }
    }
    for (var i = m.links.length - 1; i >= 0; i--) {
      final l = m.links[i];
      final custom = m.linkHit[i];
      if (custom != null) {
        if (custom.contains(p)) return (type: SankeyElementType.link, index: i);
        continue;
      }
      if (l.sourceX.isNaN || l.targetX.isNaN || l.sourceY.isNaN || l.targetY.isNaN) continue;
      final path = _linkPath(l);
      final width = l.style?.strokeWidth ?? l.linkWidth;
      // Butt caps: the stroke ends at the end points' x. The end tangents are
      // horizontal since each control point shares its end point's y.
      // ponytail: exact only for 0 < linkCurvature <= 1; outside it the curve overshoots the end points.
      final inX = p.dx >= math.min(l.sourceX, l.targetX) && p.dx <= math.max(l.sourceX, l.targetX);
      if ((l.style?.fill != null && path.contains(p)) || (inX && width > 0 && strokeContains(path, p, width))) {
        return (type: SankeyElementType.link, index: i);
      }
    }
    return null;
  }

  void _setHovered(_Hit? hit, PointerEvent e) {
    if (hit == _hovered || !mounted) return;
    final old = _hovered;
    _hovered = hit;
    if (old != null) {
      _hover = _hover.inactive();
      _refreshView();
      widget.onMouseLeave?.call(_item(old), old.type, e);
    }
    if (hit != null) {
      _keyboard = _keyboard.inactive();
      _hover = _Interaction(active: true, hit: hit, coordinate: _coordinate(hit));
      _refreshView();
      widget.onMouseEnter?.call(_item(hit), hit.type, e);
    }
  }

  void _click_(_Hit hit, PointerEvent e) {
    _keyboard = _keyboard.inactive();
    _click = _Interaction(active: true, hit: hit, coordinate: _coordinate(hit));
    _refreshView();
    widget.onClick?.call(_item(hit), hit.type, e);
  }

  void _onPointerDown(PointerDownEvent e) {
    _downPosition = e.localPosition;
    _downHit = _hitAt(e.localPosition);
    if (e.kind == PointerDeviceKind.mouse) {
      if (widget.accessibilityLayer) _focusNode.requestFocus();
      _setHovered(_downHit, e);
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    final down = _downPosition;
    _downPosition = null;
    if (down == null) return;
    final touch = e.kind != PointerDeviceKind.mouse;
    if (touch && (e.localPosition - down).distance > kTouchSlop) return;
    final hit = _hitAt(e.localPosition);
    // The tap's emulated mouse events reach the element under the finger.
    if (touch) {
      _setHovered(hit, e);
      if (widget.accessibilityLayer) _focusNode.requestFocus();
    }
    if (hit != null && (touch || hit == _downHit)) _click_(hit, e);
  }

  // -------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final responsive = ResponsiveContainerScope.maybeOf(context);
    return LayoutBuilder(builder: (context, constraints) {
      final width = responsive?.width ?? widget.width ?? (constraints.hasBoundedWidth ? constraints.maxWidth : 0.0);
      final height =
          responsive?.height ?? widget.height ?? (constraints.hasBoundedHeight ? constraints.maxHeight : 0.0);
      if (width <= 0 || height <= 0) return SizedBox(width: width, height: height);
      return _buildChart(context, Size(width, height));
    });
  }

  Widget _buildChart(BuildContext context, Size size) {
    final m = _modelFor(size);
    // A hovered index may point past a smaller data set.
    final stale = (_hovered?.index ?? 0) >= (_hovered?.type == SankeyElementType.node ? m.nodes.length : m.links.length);
    if (stale) _hovered = null;
    _view.set(_computeView(), notify: false);
    final reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final tooltip = _tooltip;

    final stack = Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(painter: _SankeyPainter(m, widget.node, widget.link, widget.stroke, widget.strokeWidth)),
          ),
        ),
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
                      viewBox: m.viewBox,
                      active: v.active,
                      payload: v.payload,
                      coordinate: v.coordinate,
                      activeIndex: v.activeIndex);
                },
              ),
            ),
          ),
      ],
    );

    Widget content = MouseRegion(
      onEnter: (e) => _setHovered(_hitAt(e.localPosition), e),
      onHover: (e) => _setHovered(_hitAt(e.localPosition), e),
      onExit: (e) => _setHovered(null, e),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onPointerDown,
        onPointerMove: (e) {
          if (e.kind == PointerDeviceKind.mouse) _setHovered(_hitAt(e.localPosition), e);
        },
        onPointerUp: _onPointerUp,
        onPointerCancel: (_) => _downPosition = null,
        child: stack,
      ),
    );
    content = TapRegion(
      onTapOutside: (_) {
        if (_focusNode.hasFocus) _focusNode.unfocus();
      },
      child: content,
    );
    if (widget.title != null || widget.desc != null) {
      content = Semantics(label: widget.title, hint: widget.desc, child: content);
    }
    return SizedBox.fromSize(
      size: size,
      child: Focus(focusNode: _focusNode, canRequestFocus: widget.accessibilityLayer, onKeyEvent: _onKey, child: content),
    );
  }
}

class _SankeyPainter extends CustomPainter {
  _SankeyPainter(this.model, this.node, this.link, this.stroke, this.strokeWidth);
  final _Model model;
  final Object? node;
  final Object? link;
  final Color? stroke;
  final double? strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < model.links.length; i++) {
      final l = model.links[i];
      final option = link;
      if (option is SankeyLinkPainter) {
        model.linkHit[i] = option(canvas, size, l);
        continue;
      }
      if (l.sourceX.isNaN || l.targetX.isNaN || l.sourceY.isNaN || l.targetY.isNaN) continue;
      final s = l.style;
      final path = _SankeyState._linkPath(l);
      final fill = s?.fill;
      if (fill != null) canvas.drawPath(path, fillPaint(fill, opacity: s?.fillOpacity ?? 1));
      final width = s?.strokeWidth ?? l.linkWidth;
      if (width > 0) {
        drawStroke(canvas, path,
            strokePaint(s?.stroke ?? const Color(0xFF333333), width, opacity: s?.strokeOpacity ?? 0.2), s?.strokeDasharray);
      }
    }
    for (var i = 0; i < model.nodes.length; i++) {
      final n = model.nodes[i];
      final option = node;
      if (option is SankeyNodePainter) {
        model.nodeHit[i] = option(canvas, size, n);
        continue;
      }
      final path = _SankeyState._nodePath(n);
      if (path == null) continue;
      final s = n.style;
      canvas.drawPath(path, fillPaint(s?.fill ?? const Color(0xFF0088FE), opacity: s?.fillOpacity ?? 0.8));
      final stroke = s?.stroke ?? this.stroke;
      if (stroke != null) {
        drawStroke(canvas, path, strokePaint(stroke, s?.strokeWidth ?? strokeWidth ?? 1, opacity: s?.strokeOpacity ?? 1), s?.strokeDasharray);
      }
    }
  }

  @override
  bool shouldRepaint(_SankeyPainter old) => old.model != model || old.node != node || old.link != link || old.stroke != stroke || old.strokeWidth != strokeWidth;
}
