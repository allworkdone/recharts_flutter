// Sankey: src/chart/Sankey.tsx. Links are painted first, nodes above them; each
// is a Layer whose mouseenter / mouseleave / click set the tooltip item state
// (tooltipSlice: itemInteraction hover and click) under the 'item' event type,
// with the tooltip anchored at the node centre or the link midpoint. Default
// shapes: a Rectangle (fill #0088fe, fill-opacity 0.8) and a stroked cubic path
// (stroke #333, stroke-opacity 0.2). Pointer handling follows polar_chart.dart.

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kTouchSlop, PointerDeviceKind;
import 'package:flutter/widgets.dart';

import '../components.dart';
import '../render/sector.dart' show strokeContains;
import '../render/shapes.dart';
import '../sankey.dart';
import 'responsive_container.dart';
import 'tooltip.dart';

/// `SankeyNodeOptions` as a callback: paints in the chart's coordinate space.
typedef SankeyNodePainter = void Function(Canvas canvas, SankeyNodeProps props);

/// `SankeyLinkOptions` as a callback.
typedef SankeyLinkPainter = void Function(Canvas canvas, SankeyLinkProps props);

/// `onClick` / `onMouseEnter` / `onMouseLeave`: [item] is a [SankeyNodeProps] or a [SankeyLinkProps].
typedef SankeyEventHandler = void Function(Object item, SankeyElementType type, PointerEvent event);

/// `Sankey` with `sankeyDefaultProps`.
///
/// [node] is an [SvgStyle] merged over the default Rectangle or a
/// [SankeyNodePainter]; [link] an [SvgStyle] or a [SankeyLinkPainter]. A custom
/// painter's shape is unknown to hit testing: the default shape stands in.
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
    this.accessibilityLayer = true,
    this.title,
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
  final bool accessibilityLayer;
  final String? title;
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

class _Model {
  _Model(this.size, this.nodes, this.links, this.viewBox);
  final Size size;
  final List<SankeyNodeProps> nodes;
  final List<SankeyLinkProps> links;
  final Rect viewBox;
}

class _SankeyState extends State<Sankey> with TickerProviderStateMixin {
  final _ViewNotifier _view = _ViewNotifier();
  _Interaction _hover = const _Interaction();
  _Interaction _click = const _Interaction();
  _Hit? _hovered;
  _Hit? _downHit;
  Offset? _downPosition;
  _Model? _model;
  Sankey? _modelWidget;

  @override
  void dispose() {
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
    final viewBox = Rect.fromLTWH(margin.left, margin.top, (size.width - margin.left - margin.right).clamp(0, double.infinity),
        (size.height - margin.top - margin.bottom).clamp(0, double.infinity));
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
    final state = mouse.active
        ? mouse
        : (mouse.hit != null && tooltip?.active == true)
            ? _Interaction(active: true, hit: mouse.hit, coordinate: mouse.coordinate)
            : _Interaction(coordinate: mouse.coordinate);
    final isActive = tooltip?.active ?? (state.active && state.hit != null);
    var payload = const <TooltipPayloadEntry>[];
    final hit = state.hit;
    if (isActive && hit != null) {
      final entry = sankeyTooltipEntry(
        type: hit.type,
        index: hit.index,
        nodes: m.nodes,
        links: m.links,
        dataKey: widget.dataKey,
        nameKey: widget.nameKey,
        name: widget.name,
        fill: widget.fill,
      );
      if (entry != null && (!(tooltip?.filterNull ?? true) || entry.value != null)) {
        payload = [entry];
      }
    }
    return _View(active: isActive, coordinate: state.coordinate, payload: payload);
  }

  void _refreshView() => _view.set(_computeView());

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
      final path = _nodePath(n);
      if (path == null) continue;
      final s = n.style;
      if (path.contains(p) || (s?.stroke != null && strokeContains(path, p, s?.strokeWidth ?? 1))) {
        return (type: SankeyElementType.node, index: i);
      }
    }
    for (var i = m.links.length - 1; i >= 0; i--) {
      final l = m.links[i];
      if (l.sourceX.isNaN || l.targetX.isNaN || l.sourceY.isNaN || l.targetY.isNaN) continue;
      final path = _linkPath(l);
      final width = l.style?.strokeWidth ?? l.linkWidth;
      if ((l.style?.fill != null && path.contains(p)) || (width > 0 && strokeContains(path, p, width))) {
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
      _hover = _Interaction(active: true, hit: hit, coordinate: _coordinate(hit));
      _refreshView();
      widget.onMouseEnter?.call(_item(hit), hit.type, e);
    }
  }

  void _click_(_Hit hit, PointerEvent e) {
    _click = _Interaction(active: true, hit: hit, coordinate: _coordinate(hit));
    _refreshView();
    widget.onClick?.call(_item(hit), hit.type, e);
  }

  void _onPointerDown(PointerDownEvent e) {
    _downPosition = e.localPosition;
    _downHit = _hitAt(e.localPosition);
    if (e.kind == PointerDeviceKind.mouse) _setHovered(_downHit, e);
  }

  void _onPointerUp(PointerUpEvent e) {
    final down = _downPosition;
    _downPosition = null;
    if (down == null) return;
    final touch = e.kind != PointerDeviceKind.mouse;
    if (touch && (e.localPosition - down).distance > kTouchSlop) return;
    final hit = _hitAt(e.localPosition);
    // The tap's emulated mouse events reach the element under the finger.
    if (touch) _setHovered(hit, e);
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
            child: CustomPaint(painter: _SankeyPainter(m, widget.node, widget.link)),
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
                      coordinate: v.coordinate);
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
    if (widget.title != null) content = Semantics(label: widget.title, child: content);
    return SizedBox.fromSize(size: size, child: content);
  }
}

class _SankeyPainter extends CustomPainter {
  _SankeyPainter(this.model, this.node, this.link);
  final _Model model;
  final Object? node;
  final Object? link;

  @override
  void paint(Canvas canvas, Size size) {
    for (final l in model.links) {
      final option = link;
      if (option is SankeyLinkPainter) {
        option(canvas, l);
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
    for (final n in model.nodes) {
      final option = node;
      if (option is SankeyNodePainter) {
        option(canvas, n);
        continue;
      }
      final path = _SankeyState._nodePath(n);
      if (path == null) continue;
      final s = n.style;
      canvas.drawPath(path, fillPaint(s?.fill ?? const Color(0xFF0088FE), opacity: s?.fillOpacity ?? 0.8));
      final stroke = s?.stroke;
      if (stroke != null) {
        drawStroke(canvas, path, strokePaint(stroke, s?.strokeWidth ?? 1, opacity: s?.strokeOpacity ?? 1), s?.strokeDasharray);
      }
    }
  }

  @override
  bool shouldRepaint(_SankeyPainter old) => old.model != model || old.node != node || old.link != link;
}
