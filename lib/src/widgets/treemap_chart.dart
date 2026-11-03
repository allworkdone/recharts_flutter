// Treemap: src/chart/Treemap.tsx (TreemapWithState, TreemapItem, ContentItem,
// renderNestIndex). The chart has no axes; its only tooltip event type is
// 'item'. Each node is a Layer whose `transform` runs a CSSTransitionAnimate
// from translate(-x - width, 0), so the entrance is a per-node slide driven
// like ErrorBar's CSS scale (animation.dart: ErrorBarAnimation): one frame
// late, after `animationBegin`, eased by the browser.

import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind, kTouchSlop;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../components.dart';
import '../core/easing.dart';
import '../render/svg_text.dart';
import '../treemap.dart';
import '../util.dart';
import 'responsive_container.dart';
import 'tooltip.dart';
import '../css_color.dart';

export '../treemap.dart' show TreemapNode, treemapColorPanel, addToTreemapNodeIndex, treemapPayloadSearcher, computeNode, squarify;

enum TreemapType { flat, nest }

/// `content` as a function: paints the node in the node's own coordinates.
typedef TreemapContentPainter = void Function(Canvas canvas, TreemapNode node);

const _nestIndexHeight = 30.0;

/// `getTreemapRenderHeight`.
double _renderHeight(double height, TreemapType type) => type == TreemapType.nest ? height - _nestIndexHeight : height;

Color _hex(String s) => Color(0xFF000000 | int.parse(s.substring(1), radix: 16));

final _defaultColors = [for (final c in treemapColorPanel) _hex(c)];

/// `<Treemap>` with `defaultTreeMapProps`. [width] and [height] fall back to
/// the incoming constraints (or a `ResponsiveContainer`).
class Treemap extends StatefulWidget {
  const Treemap({
    super.key,
    this.width,
    this.height,
    this.data = const [],
    this.aspectRatio = 1.618033988749895,
    this.nodeInset = 0,
    this.nodeGap = 0,
    this.content,
    this.fill,
    this.stroke,
    this.nameKey = 'name',
    this.dataKey = 'value',
    this.children = const [],
    this.type = TreemapType.flat,
    this.colorPanel,
    this.nestIndexContent,
    this.onAnimationStart,
    this.onAnimationEnd,
    this.onMouseEnter,
    this.onMouseLeave,
    this.onClick,
    this.isAnimationActive,
    this.isUpdateAnimationActive,
    this.animationBegin = 0,
    this.animationDuration = 1500,
    this.animationEasing = 'linear',
  });

  final double? width;
  final double? height;

  /// Maps with an optional `children` list.
  final List<Object?> data;
  final double aspectRatio;

  /// Inset between a parent node and its children.
  final double nodeInset;

  /// Gap between sibling nodes.
  final double nodeGap;

  /// Replaces the default rect and label of each node.
  final TreemapContentPainter? content;

  /// Svg `fill` / `stroke` of the chart: every default rect, and the labels and
  /// arrows that inherit them. A [Color] under `fill` / `stroke` in a data
  /// entry overrides them for that node.
  final Color? fill;
  final Color? stroke;
  final Object nameKey;
  final Object dataKey;

  /// Only [Tooltip] has an effect.
  final List<RechartsElement> children;
  final TreemapType type;
  final List<Color>? colorPanel;

  /// The breadcrumb text of the nest index (`nestIndexContent` as a function).
  final String Function(TreemapNode item, int i)? nestIndexContent;
  final VoidCallback? onAnimationStart;
  final VoidCallback? onAnimationEnd;

  /// Called for leaves, and for every node in `nest` mode.
  final void Function(TreemapNode node, PointerEvent event)? onMouseEnter;
  final void Function(TreemapNode node, PointerEvent event)? onMouseLeave;
  final void Function(TreemapNode node)? onClick;

  /// null is `'auto'`: on unless the platform asks for reduced motion.
  final bool? isAnimationActive;

  /// Accepted for parity. Recharts hands `!isUpdateAnimationActive` to Rectangle, so an explicit `false`
  /// turns on Rectangle's stroke-dasharray draw-in; that is not ported (the default 'auto' is a no-op).
  final bool? isUpdateAnimationActive;
  final int animationBegin;
  final int animationDuration;
  final Object animationEasing;

  @override
  State<Treemap> createState() => _TreemapState();
}

/// One rendered node (`renderNode`).
class _Item {
  _Item(this.node, this.root, String parentKey) : key = '$parentKey/${node['x']}-${node['y']}-${node['name']}';
  final TreemapNode node;
  final TreemapNode root;

  /// React's `key` path: a changed ancestor key remounts the whole subtree.
  final String key;

  /// The `from` of the node's CSSTransitionAnimate: a change restarts it.
  String get mountKey => '$key|${-x - width}';
  bool get isLeaf => (node['children'] as List?)?.isNotEmpty != true;
  double get x => (node['x'] as num).toDouble();
  double get y => (node['y'] as num).toDouble();
  double get width => (node['width'] as num).toDouble();
  double get height => (node['height'] as num).toDouble();
  int get depth => node['depth'] as int;
}

/// Mount of a batch of nodes: their `CSSTransitionAnimate`s run on one clock.
class _Mount {
  _Mount(TickerProvider vsync, this.keys, {required int begin, required int duration, required Object easing})
      : controller = AnimationController(vsync: vsync) {
    // extractCssEasing: 'spring' and non-string easings fall back to 'ease'.
    easingFn = createEasingFunction(easing is String && easing != 'spring' ? easing : 'ease') ?? createEasingFunction('ease')!;
    final int total = math.max<int>(0, begin) + math.max<int>(0, duration);
    beginFraction = total == 0 ? 0 : math.max(0, begin) / total;
    controller.duration = Duration(milliseconds: total == 0 ? 1 : total);
    controller.value = 0;
    // Starts a frame late, like SeriesAnimator.
    pendingStart = SchedulerBinding.instance.scheduleFrameCallback((_) {
      pendingStart = null;
      controller.forward(from: 0);
    });
  }

  final Set<String> keys;
  final AnimationController controller;
  late final EasingFunction easingFn;
  late final double beginFraction;
  int? pendingStart;

  /// The eased transition progress.
  double get progress {
    final v = controller.value;
    final p = beginFraction >= 1 ? 1.0 : ((v - beginFraction) / (1 - beginFraction)).clamp(0.0, 1.0);
    return p >= 1 ? 1 : easingFn(p);
  }

  void dispose() {
    if (pendingStart != null) SchedulerBinding.instance.cancelFrameCallbackWithId(pendingStart!);
    controller.dispose();
  }
}

int _nextId = 0;

class _Interaction {
  const _Interaction({this.active = false, this.index, this.coordinate});
  final bool active;
  final String? index;
  final Offset? coordinate;
}

/// The Rectangle's fill and stroke: the node's own, else the chart's, else the color panel.
(Color, Color) _rectColors(Treemap widget, _Item item) {
  final node = item.node;
  final colors = widget.colorPanel ?? _defaultColors;
  final fill = cssFillOf(node['fill']) ??
      widget.fill ?? (item.depth < 2 ? colors[(node['index'] as int) % colors.length] : const Color(0x00FFFFFF));
  return (fill, cssStrokeOf(node['stroke']) ?? widget.stroke ?? const Color(0xFFFFFFFF));
}

class _TreemapState extends State<Treemap> with TickerProviderStateMixin {
  // State of TreemapWithState.
  TreemapNode? _formatRoot;
  TreemapNode? _currentRoot;
  List<TreemapNode> _nestIndex = [];
  Object? _prevData;
  TreemapType? _prevType;
  Size? _prevSize;
  Object? _prevDataKey;
  double? _prevAspectRatio, _prevNodeInset, _prevNodeGap;

  List<_Item> _items = const [];
  final Map<String, _Mount> _mountOf = {};
  final List<_Mount> _mounts = [];
  _Interaction _hover = const _Interaction();
  _Interaction _click = const _Interaction();
  String? _hoveredKey;
  _Part? _hoveredPart;
  _Hit? _downHit;
  int? _downBox;
  Offset? _downPosition;
  Offset? _pointer;
  PointerEvent? _lastEvent;
  bool _pointerInside = false;
  final String _id = 'recharts-treemap-${_nextId++}';
  double _width = 0, _height = 0;
  List<_Box> _boxes = const [];
  TextStyle _baseStyle = const TextStyle();
  TextScaler _scaler = TextScaler.noScaling;

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
    for (final m in _mounts) {
      m.dispose();
    }
    super.dispose();
  }

  // -------------------------------------------------------------- layout state

  TreemapNode _computeRoot(TreemapNode node, {String? nested}) => computeNode(
        depth: 0,
        node: {...node, 'x': 0, 'y': 0, 'width': _width, 'height': _renderHeight(_height, widget.type)},
        index: 0,
        dataKey: widget.dataKey,
        nameKey: widget.nameKey,
        nestedActiveTooltipIndex: nested,
      );

  TreemapNode _squarify(TreemapNode root) => squarify(root, widget.aspectRatio, widget.nodeInset, widget.nodeGap);

  /// `getDerivedStateFromProps`.
  void _deriveState(Size size) {
    final w = widget;
    if (!identical(w.data, _prevData) ||
        w.type != _prevType ||
        size != _prevSize ||
        w.dataKey != _prevDataKey ||
        w.aspectRatio != _prevAspectRatio ||
        w.nodeInset != _prevNodeInset ||
        w.nodeGap != _prevNodeGap) {
      _width = size.width;
      _height = size.height;
      final root = _computeRoot({'children': w.data});
      _formatRoot = _squarify(root);
      _currentRoot = root;
      _nestIndex = [root];
      _prevData = w.data;
      _prevType = w.type;
      _prevSize = size;
      _prevDataKey = w.dataKey;
      _prevAspectRatio = w.aspectRatio;
      _prevNodeInset = w.nodeInset;
      _prevNodeGap = w.nodeGap;
    }
  }

  /// `handleClick`.
  void _handleClick(TreemapNode node) {
    if (widget.type == TreemapType.nest && node['children'] != null) {
      final root = _computeRoot(node, nested: node['tooltipIndex'] as String);
      final formatRoot = _squarify(root);
      _nestIndex.add(node);
      setState(() {
        _formatRoot = formatRoot;
        _currentRoot = root;
      });
      _rehover();
    }
    widget.onClick?.call(node);
  }

  /// `handleNestIndex`.
  void _handleNestIndex(TreemapNode node, int i) {
    final root = _computeRoot(node, nested: node['tooltipIndex'] as String);
    final formatRoot = _squarify(root);
    setState(() {
      _formatRoot = formatRoot;
      _currentRoot = node;
      _nestIndex = _nestIndex.sublist(0, i + 1);
    });
    _rehover();
  }

  /// After a drill every node remounts and Chrome fires boundary events for the
  /// element now under the still pointer; the old element is gone, so nothing leaves.
  void _rehover() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = _pointer, e = _lastEvent;
      if (!mounted || !_pointerInside || p == null) return;
      _hoveredKey = null;
      _hoveredPart = null;
      _updateHover(_hitAt(p), e);
    });
  }

  // -------------------------------------------------------------- items

  /// `renderNode`: nodes in paint order.
  void _collect(TreemapNode root, TreemapNode node, String parentKey, List<_Item> out) {
    final current = _currentRoot;
    final isCurrentRootChild = ((current?['children'] as List?) ?? const []).any((c) {
      final item = c as TreemapNode;
      return item['depth'] == node['depth'] && item['name'] == node['name'];
    });
    if (!isCurrentRootChild && root['depth'] != 0 && widget.type == TreemapType.nest) return;
    final item = _Item(node, root, parentKey);
    out.add(item);
    for (final child in (node['children'] as List?) ?? const []) {
      _collect(node, child as TreemapNode, item.key, out);
    }
  }

  /// `CSSTransitionAnimate` per node: nodes whose key or `from` is new start a slide-in.
  void _syncMounts(List<_Item> items, bool reducedMotion) {
    final keys = {for (final i in items) i.mountKey};
    _mountOf.removeWhere((k, _) => !keys.contains(k));
    final fresh = {for (final i in items) if (!_mountOf.containsKey(i.mountKey)) i.mountKey};
    final active = widget.isAnimationActive ?? !reducedMotion;
    if (fresh.isNotEmpty && active) {
      final mount = _Mount(this, fresh,
          begin: widget.animationBegin, duration: widget.animationDuration, easing: widget.animationEasing);
      _mounts.add(mount);
      for (final k in fresh) {
        _mountOf[k] = mount;
      }
      if (widget.onAnimationStart != null) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          for (var i = 0; i < fresh.length; i++) {
            widget.onAnimationStart?.call();
          }
        });
      }
      mount.controller.addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) {
          // Only nodes still mounted report their end.
          for (var i = fresh.where((k) => _mountOf[k] == mount).length; i > 0; i--) {
            widget.onAnimationEnd?.call();
          }
        }
      });
    }
    final live = _mountOf.values.toSet();
    for (final m in _mounts.where((m) => !live.contains(m)).toList()) {
      _mounts.remove(m);
      m.dispose();
    }
  }

  double _dx(_Item item) {
    final m = _mountOf[item.mountKey];
    if (m == null) return 0;
    return (-item.x - item.width) * (1 - m.progress);
  }

  // -------------------------------------------------------------- hit testing

  /// The topmost painted part under [p]: per node (paint order, last on top) the
  /// label, the arrow, then the rect with its 1px stroke. Only the rect carries
  /// the tooltip's `data-recharts-item-index` and handlers.
  _Hit? _hitAt(Offset p) {
    if (p.dy < 0 || p.dy >= _renderHeight(_height, widget.type) || p.dx < 0 || p.dx >= _width) return null;
    for (final item in _items.reversed) {
      final q = p - Offset(_dx(item), 0);
      if (widget.content == null) {
        final label = _labelRect(widget, _baseStyle, _scaler, item);
        if (label != null && label.contains(q)) return _Hit(item, _Part.label);
        final arrow = _arrowPath(widget, item);
        if (arrow != null && arrow.contains(q)) return _Hit(item, _Part.arrow);
      }
      if (item.width == 0 || item.height == 0) continue;
      final rect = Rect.fromLTWH(item.x, item.y, item.width, item.height);
      if (!rect.inflate(0.5).contains(q)) continue;
      // fill="none" leaves the interior unhit; the 1px stroke ring still counts unless it is none too.
      final (fill, stroke) = _rectColors(widget, item);
      if (!isCssNone(fill) || (!isCssNone(stroke) && !rect.deflate(0.5).contains(q))) return _Hit(item, _Part.rect);
    }
    return null;
  }

  int? _boxAt(Offset p) {
    for (final (i, b) in _boxes.indexed) {
      if (b.rect.contains(p)) return i;
    }
    return null;
  }

  Offset _center(_Item item) => Offset(item.x + item.width / 2, item.y + item.height / 2);

  bool _fires(_Item i) => i.isLeaf || widget.type == TreemapType.nest;

  /// `{...svgPropertiesNoEvents(props), ...node, root}`: what handlers receive.
  TreemapNode _eventProps(_Item item) => {
        'id': _id,
        if (widget.fill != null) 'fill': widget.fill,
        if (widget.stroke != null) 'stroke': widget.stroke,
        ...item.node,
        'root': item.root,
      };

  /// What `content` receives: the same plus the animation flags of TreemapItem.
  TreemapNode _contentProps(_Item item) => {
        ..._eventProps(item),
        'isAnimationActive': widget.isAnimationActive ?? 'auto',
        'isUpdateAnimationActive': widget.isUpdateAnimationActive == false,
      };

  /// `setActiveMouseOverItemIndex`, dispatched by the rect's onMouseEnter.
  void _dispatchHover(_Item item) {
    if (!mounted) return;
    setState(() => _hover = _Interaction(active: true, index: item.node['tooltipIndex'] as String, coordinate: _center(item)));
  }

  /// mouseenter / mouseleave of the Layers (user callbacks) and of the rect (tooltip).
  void _updateHover(_Hit? hit, PointerEvent? event) {
    if (!mounted) return;
    final prevKey = _hoveredKey, prevPart = _hoveredPart;
    _hoveredKey = hit?.item.key;
    _hoveredPart = hit?.part;
    if (prevKey != _hoveredKey) {
      final prev = prevKey == null ? null : _items.where((i) => i.key == prevKey).firstOrNull;
      if (prev != null && _fires(prev) && event != null) widget.onMouseLeave?.call(_eventProps(prev), event);
      if (hit != null && _fires(hit.item) && event != null) widget.onMouseEnter?.call(_eventProps(hit.item), event);
    }
    if (hit != null && hit.part == _Part.rect && (prevKey != _hoveredKey || prevPart != _Part.rect)) _dispatchHover(hit.item);
  }

  void _mouseLeave(PointerEvent e) {
    _pointerInside = false;
    final previous = _items.where((i) => i.key == _hoveredKey).firstOrNull;
    _hoveredKey = null;
    _hoveredPart = null;
    if (previous != null && _fires(previous)) widget.onMouseLeave?.call(_eventProps(previous), e);
    setState(() => _hover = _Interaction(index: _hover.index, coordinate: _hover.coordinate));
  }

  void _onPointerDown(PointerDownEvent e) {
    _pointer = e.localPosition;
    _downPosition = e.localPosition;
    _pointerInside = true;
    _downHit = _hitAt(e.localPosition);
    _downBox = _boxAt(e.localPosition);
  }

  void _onPointerUp(PointerUpEvent e) {
    final p = e.localPosition;
    final touch = e.kind != PointerDeviceKind.mouse;
    // A touch that moved from one node to another is no tap.
    if (touch && _downPosition != null && (p - _downPosition!).distance > kTouchSlop) return;
    final box = _boxAt(p);
    if (box != null && box == _downBox) {
      _handleNestIndex(_nestIndex[box], box);
      return;
    }
    final hit = _hitAt(p);
    // A tap's emulated mouse events enter the node under the finger first.
    if (touch) _updateHover(hit, e);
    final down = _downHit;
    // A click targets the common ancestor of the mousedown and mouseup targets.
    if (hit == null || down == null || down.item.key != hit.item.key) return;
    final item = hit.item;
    // ContentItemWithEvents: the rect's click (when it is the target), then the Layer's.
    if (hit.part == _Part.rect && down.part == _Part.rect) {
      setState(() => _click = _Interaction(active: true, index: item.node['tooltipIndex'] as String, coordinate: _center(item)));
    }
    final node = _eventProps(item);
    if (widget.type == TreemapType.nest && item.depth > 0) _handleClick(node);
    if (_fires(item)) widget.onClick?.call(node);
  }

  // -------------------------------------------------------------- tooltip

  List<TooltipPayloadEntry> _payload(Tooltip tooltip, _Interaction state) {
    final node = treemapPayloadSearcher(_currentRoot, state.index);
    final fill = widget.fill;
    final name = getValueByDataKey(node, widget.nameKey);
    final entry = TooltipPayloadEntry(
      dataKey: widget.dataKey,
      name: name == null ? null : jsString(name),
      value: getValueByDataKey(node, widget.dataKey),
      payload: node,
      color: fill,
      fill: fill,
      stroke: widget.stroke,
      unit: '',
    );
    if (tooltip.filterNull && entry.value == null) return const [];
    return [entry];
  }

  // -------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final responsive = ResponsiveContainerScope.maybeOf(context);
    return LayoutBuilder(builder: (context, constraints) {
      final width = responsive?.width ?? widget.width ?? (constraints.hasBoundedWidth ? constraints.maxWidth : 0.0);
      final height = responsive?.height ?? widget.height ?? (constraints.hasBoundedHeight ? constraints.maxHeight : 0.0);
      if (width <= 0 || height <= 0 || !width.isFinite || !height.isFinite) return const SizedBox.shrink();
      return _buildChart(context, Size(width, height));
    });
  }

  Widget _buildChart(BuildContext context, Size size) {
    _baseStyle = DefaultTextStyle.of(context).style;
    _scaler = MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    final reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _deriveState(size);
    final items = <_Item>[];
    if (_formatRoot != null) _collect(_formatRoot!, _formatRoot!, '', items);
    _items = items;
    _syncMounts(items, reducedMotion);
    _boxes = widget.type == TreemapType.nest ? _layoutBreadcrumb(size) : const [];

    final tooltip = widget.children.whereType<Tooltip>().firstOrNull;
    final painter = _TreemapPainter(
      items: items,
      dx: _dx,
      widget: widget,
      size: size,
      baseStyle: _baseStyle,
      scaler: _scaler,
      boxes: _boxes,
      contentProps: _contentProps,
      repaint: Listenable.merge([for (final m in _mounts) m.controller]),
    );
    final stack = Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: painter))),
        if (tooltip != null)
          Positioned.fill(
            child: IgnorePointer(
              child: () {
                var state = tooltip.trigger == TooltipTrigger.click ? _click : _hover;
                // defaultIndex: String(defaultIndex), no coordinate (getPosition is a noop): the box sits at (0,0).
                if (!state.active && state.index == null && tooltip.defaultIndex != null) {
                  state = _Interaction(active: true, index: jsString(tooltip.defaultIndex));
                }
                final hasIndex = state.index != null;
                final active = tooltip.active ?? (state.active && hasIndex);
                return tooltipLayer(tooltip,
                    vsync: this,
                    reducedMotion: reducedMotion,
                    viewBox: Offset.zero & size,
                    active: active,
                    payload: active ? _payload(tooltip, state) : const [],
                    coordinate: state.coordinate,
                    activeIndex: state.index);
              }(),
            ),
          ),
      ],
    );
    return SizedBox.fromSize(
      size: size,
      child: MouseRegion(
        onEnter: (e) {
          _pointer = e.localPosition;
          _lastEvent = e;
          _pointerInside = true;
          _updateHover(_hitAt(e.localPosition), e);
        },
        onHover: (e) {
          _pointer = e.localPosition;
          _lastEvent = e;
          _updateHover(_hitAt(e.localPosition), e);
        },
        onExit: _mouseLeave,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onPointerDown,
          onPointerMove: (e) {
            _pointer = e.localPosition;
            if (e.kind != PointerDeviceKind.mouse) {
              // handleTouchMove: only the tooltip follows a finger over a rect; no callbacks.
              final hit = _hitAt(e.localPosition);
              if (hit != null && hit.part == _Part.rect) _dispatchHover(hit.item);
            }
          },
          onPointerUp: _onPointerUp,
          child: stack,
        ),
      ),
    );
  }

  /// `renderNestIndex`: inline-block boxes (`padding: 0 7px`, `marginRight: 3px`)
  /// centred under the svg, whose own line box leaves the font's descent below it.
  List<_Box> _layoutBreadcrumb(Size size) {
    final probe = textPainterFor('x', _baseStyle, _scaler);
    final ascent = probe.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final asc = (ascent + 0.5).floorToDouble();
    final desc = (probe.height - ascent + 0.5).floorToDouble();
    final top = _renderHeight(size.height, widget.type) + desc + 8;
    final names = <String>[];
    final widths = <double>[];
    for (final (i, item) in _nestIndex.indexed) {
      final custom = widget.nestIndexContent;
      final raw = getValueByDataKey(item, widget.nameKey, 'root');
      final name = custom != null ? custom(item, i) : (raw is String ? raw : 'root');
      names.add(name);
      widths.add(measureText(name, _baseStyle, _scaler).width + 14);
    }
    var x = (size.width - widths.fold<double>(0, (a, w) => a + w + 3)) / 2;
    final boxes = <_Box>[];
    for (final (i, name) in names.indexed) {
      // An empty inline-block has no line box, hence no height.
      boxes.add(_Box(name, Rect.fromLTWH(x, top, widths[i], name.isEmpty ? 0 : asc + desc), asc));
      x += widths[i] + 3;
    }
    return boxes;
  }
}

class _Box {
  const _Box(this.name, this.rect, this.ascent);
  final String name;
  final Rect rect;
  final double ascent;
}

final Map<Color, Paint> _strokePaints = {};
Paint _strokePaint(Color c) => _strokePaints.putIfAbsent(c, () => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = 1
  ..color = c);

enum _Part { rect, label, arrow }

class _Hit {
  const _Hit(this.item, this.part);
  final _Item item;
  final _Part part;
}

TextStyle _labelStyle(TextStyle base, {Color? color, Paint? foreground}) => TextStyle(
      fontFamily: base.fontFamily,
      fontFamilyFallback: base.fontFamilyFallback,
      fontWeight: base.fontWeight,
      fontStyle: base.fontStyle,
      fontSize: 14,
      color: color,
      foreground: foreground,
    );

/// ContentItem's name: shown only when it fits, measured at the page font size
/// but drawn at 14.
({String name, double x, double y})? _labelPlacement(Treemap w, TextStyle base, TextScaler scaler, _Item item) {
  final name = jsString(item.node['name']);
  final size = measureText(name, base, scaler);
  if (item.width > 20 && item.height > 20 && size.width < item.width && size.height < item.height) {
    return (name: name, x: item.x + 8, y: item.y + item.height / 2 + 7);
  }
  return null;
}

/// The text's glyph cell: advance wide, ascent above the baseline to descent below.
Rect? _labelRect(Treemap w, TextStyle base, TextScaler scaler, _Item item) {
  final label = _labelPlacement(w, base, scaler, item);
  if (label == null) return null;
  final tp = textPainterFor(label.name, _labelStyle(base, color: const Color(0xFF000000)), scaler);
  return Rect.fromLTWH(label.x, label.y - tp.computeDistanceToActualBaseline(TextBaseline.alphabetic), tp.width, tp.height);
}

Path? _arrowPath(Treemap w, _Item item) {
  if (!(item.width > 10 && item.height > 10 && item.node['children'] != null && w.type == TreemapType.nest && item.depth > 0)) return null;
  final x = item.x, y = item.y, height = item.height;
  return Path()
    ..moveTo(x + 2, y + height / 2)
    ..lineTo(x + 6, y + height / 2 + 3)
    ..lineTo(x + 2, y + height / 2 + 6)
    ..close();
}

class _TreemapPainter extends CustomPainter {
  _TreemapPainter({
    required this.items,
    required this.dx,
    required this.widget,
    required this.size,
    required this.baseStyle,
    required this.scaler,
    required this.boxes,
    required this.contentProps,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final List<_Item> items;
  final double Function(_Item) dx;
  final Treemap widget;
  final Size size;
  final TextStyle baseStyle;
  final TextScaler scaler;
  final List<_Box> boxes;
  final TreemapNode Function(_Item) contentProps;

  @override
  void paint(Canvas canvas, Size _) {
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, _renderHeight(size.height, widget.type)));
    for (final item in items) {
      canvas.save();
      canvas.translate(dx(item), 0);
      if (widget.content != null) {
        widget.content!(canvas, contentProps(item));
      } else {
        _paintContent(canvas, item);
      }
      canvas.restore();
    }
    canvas.restore();
    _paintBreadcrumb(canvas);
  }

  /// `ContentItem`'s default content: Rectangle, nest arrow and name.
  void _paintContent(Canvas canvas, _Item item) {
    final x = item.x, y = item.y, width = item.width, height = item.height;
    final (fill, stroke) = _rectColors(widget, item);
    // The svg's own fill and stroke, which the arrow and the text inherit.
    final inheritedFill = widget.fill;
    final inheritedStroke = widget.stroke;

    if (x.isFinite && y.isFinite && width.isFinite && height.isFinite && width != 0 && height != 0) {
      final rect = Rect.fromLTWH(x, y, width, height);
      canvas.drawRect(rect, Paint()..color = fill);
      canvas.drawRect(rect, _strokePaint(stroke));
    }

    final arrow = _arrowPath(widget, item);
    if (arrow != null) {
      canvas.drawPath(arrow, Paint()..color = inheritedFill ?? const Color(0xFF000000));
      if (inheritedStroke != null) canvas.drawPath(arrow, _strokePaint(inheritedStroke));
    }

    final label = _labelPlacement(widget, baseStyle, scaler, item);
    if (label != null) {
      // `<text x y fontSize={14}>`: fill, then the inherited stroke over it.
      paintSvgText(canvas, label.name, label.x, label.y,
          style: _labelStyle(baseStyle, color: inheritedFill ?? const Color(0xFF000000)), scaler: scaler);
      if (inheritedStroke != null) {
        paintSvgText(canvas, label.name, label.x, label.y,
            style: _labelStyle(baseStyle, foreground: _strokePaint(inheritedStroke)), scaler: scaler);
      }
    }
  }

  void _paintBreadcrumb(Canvas canvas) {
    final style = baseStyle.copyWith(color: const Color(0xFFFFFFFF));
    for (final b in boxes) {
      if (b.rect.height == 0) continue;
      canvas.drawRect(b.rect, Paint()..color = const Color(0xFF000000));
      final tp = textPainterFor(b.name, style, scaler);
      tp.paint(canvas, Offset(b.rect.left + 7, b.rect.top + b.ascent - tp.computeDistanceToActualBaseline(TextBaseline.alphabetic)));
    }
  }

  @override
  bool shouldRepaint(_TreemapPainter old) => true;
}
