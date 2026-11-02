// Treemap: src/chart/Treemap.tsx (TreemapWithState, TreemapItem, ContentItem,
// renderNestIndex). The chart has no axes; its only tooltip event type is
// 'item'. Each node is a Layer whose `transform` runs a CSSTransitionAnimate
// from translate(-x - width, 0), so the entrance is a per-node slide driven
// like ErrorBar's CSS scale (animation.dart: ErrorBarAnimation): one frame
// late, after `animationBegin`, eased by the browser.

import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../components.dart';
import '../core/easing.dart';
import '../render/svg_text.dart';
import '../treemap.dart';
import '../util.dart';
import 'responsive_container.dart';
import 'tooltip.dart';

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

  /// Accepted for parity; Rectangle's update animation is never active here.
  final bool? isUpdateAnimationActive;
  final int animationBegin;
  final int animationDuration;
  final Object animationEasing;

  @override
  State<Treemap> createState() => _TreemapState();
}

/// One rendered node (`renderNode`).
class _Item {
  _Item(this.node, this.root) : key = '${node['x']}-${node['y']}-${node['name']}';
  final TreemapNode node;
  final TreemapNode root;
  final String key;
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
    easingFn = createEasingFunction(easing is String && easing == 'spring' ? 'ease' : easing) ?? createEasingFunction('ease')!;
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

class _Interaction {
  const _Interaction({this.active = false, this.index, this.coordinate});
  final bool active;
  final String? index;
  final Offset? coordinate;
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
  _Item? _downItem;
  Offset? _pointer;
  bool _pointerInside = false;
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

  TreemapNode _withRoot(TreemapNode node, TreemapNode root) => {...node, 'root': root};

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

  /// A browser re-hit-tests under a still pointer after the layout changed.
  void _rehover() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pointerInside && _pointer != null) _setHover(_itemAt(_pointer!));
    });
  }

  // -------------------------------------------------------------- items

  /// `renderNode`: nodes in paint order.
  void _collect(TreemapNode root, TreemapNode node, List<_Item> out) {
    final current = _currentRoot;
    final isCurrentRootChild = ((current?['children'] as List?) ?? const []).any((c) {
      final item = c as TreemapNode;
      return item['depth'] == node['depth'] && item['name'] == node['name'];
    });
    if (!isCurrentRootChild && root['depth'] != 0 && widget.type == TreemapType.nest) return;
    out.add(_Item(node, root));
    for (final child in (node['children'] as List?) ?? const []) {
      _collect(node, child as TreemapNode, out);
    }
  }

  /// `CSSTransitionAnimate` per node: nodes whose key is new start a slide-in.
  void _syncMounts(List<_Item> items, bool reducedMotion) {
    final keys = {for (final i in items) i.key};
    _mountOf.removeWhere((k, _) => !keys.contains(k));
    final fresh = {for (final i in items) if (!_mountOf.containsKey(i.key)) i.key};
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
          for (var i = 0; i < fresh.length; i++) {
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
    final m = _mountOf[item.key];
    if (m == null) return 0;
    return (-item.x - item.width) * (1 - m.progress);
  }

  // -------------------------------------------------------------- hit testing

  /// The topmost node whose rect (with its 1px stroke) is under [p].
  _Item? _itemAt(Offset p) {
    if (p.dy < 0 || p.dy >= _renderHeight(_height, widget.type) || p.dx < 0 || p.dx >= _width) return null;
    for (final item in _items.reversed) {
      if (item.width == 0 || item.height == 0) continue;
      final dx = _dx(item);
      if (Rect.fromLTWH(item.x + dx, item.y, item.width, item.height).inflate(0.5).contains(p)) return item;
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

  /// Layer mouseenter / mouseleave and `setActiveMouseOverItemIndex`.
  void _setHover(_Item? item, [PointerEvent? event]) {
    if (!mounted || item?.key == _hoveredKey) return;
    final previous = _items.where((i) => i.key == _hoveredKey).firstOrNull;
    _hoveredKey = item?.key;
    bool fires(_Item i) => i.isLeaf || widget.type == TreemapType.nest;
    if (previous != null && fires(previous) && event != null) widget.onMouseLeave?.call(_withRoot(previous.node, previous.root), event);
    if (item != null) {
      if (fires(item) && event != null) widget.onMouseEnter?.call(_withRoot(item.node, item.root), event);
      setState(() => _hover = _Interaction(active: true, index: item.node['tooltipIndex'] as String, coordinate: _center(item)));
    }
  }

  void _mouseLeave(PointerEvent e) {
    _pointerInside = false;
    final previous = _items.where((i) => i.key == _hoveredKey).firstOrNull;
    _hoveredKey = null;
    if (previous != null && (previous.isLeaf || widget.type == TreemapType.nest)) {
      widget.onMouseLeave?.call(_withRoot(previous.node, previous.root), e);
    }
    setState(() => _hover = _Interaction(index: _hover.index, coordinate: _hover.coordinate));
  }

  void _onPointerDown(PointerDownEvent e) {
    _pointer = e.localPosition;
    _pointerInside = true;
    _downItem = _itemAt(e.localPosition);
    if (e.kind != PointerDeviceKind.mouse) _setHover(_downItem, e);
  }

  void _onPointerUp(PointerUpEvent e) {
    final boxIndex = _boxAt(e.localPosition);
    if (boxIndex != null && boxIndex == _boxAt(_pointer ?? e.localPosition)) {
      _handleNestIndex(_nestIndex[boxIndex], boxIndex);
      return;
    }
    final item = _itemAt(e.localPosition);
    if (item == null || (e.kind == PointerDeviceKind.mouse && item.key != _downItem?.key)) return;
    // ContentItemWithEvents: the rect's click, then the Layer's.
    setState(() => _click = _Interaction(active: true, index: item.node['tooltipIndex'] as String, coordinate: _center(item)));
    final node = _withRoot(item.node, item.root);
    if (widget.type == TreemapType.nest && item.depth > 0) _handleClick(node);
    if (item.isLeaf || widget.type == TreemapType.nest) widget.onClick?.call(node);
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
    if (_formatRoot != null) _collect(_formatRoot!, _formatRoot!, items);
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
                final state = tooltip.trigger == TooltipTrigger.click ? _click : _hover;
                final hasIndex = state.index != null;
                final active = tooltip.active ?? (state.active && hasIndex);
                return tooltipLayer(tooltip,
                    vsync: this,
                    reducedMotion: reducedMotion,
                    viewBox: Offset.zero & size,
                    active: active,
                    payload: active ? _payload(tooltip, state) : const [],
                    coordinate: state.coordinate);
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
          _pointerInside = true;
          _setHover(_itemAt(e.localPosition), e);
        },
        onHover: (e) {
          _pointer = e.localPosition;
          _setHover(_itemAt(e.localPosition), e);
        },
        onExit: _mouseLeave,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onPointerDown,
          onPointerMove: (e) {
            _pointer = e.localPosition;
            if (e.kind != PointerDeviceKind.mouse) {
              // handleTouchMove: a finger over a node activates it.
              final hit = _itemAt(e.localPosition);
              if (hit != null) _setHover(hit, e);
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

class _TreemapPainter extends CustomPainter {
  _TreemapPainter({
    required this.items,
    required this.dx,
    required this.widget,
    required this.size,
    required this.baseStyle,
    required this.scaler,
    required this.boxes,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final List<_Item> items;
  final double Function(_Item) dx;
  final Treemap widget;
  final Size size;
  final TextStyle baseStyle;
  final TextScaler scaler;
  final List<_Box> boxes;

  @override
  void paint(Canvas canvas, Size _) {
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, _renderHeight(size.height, widget.type)));
    for (final item in items) {
      canvas.save();
      canvas.translate(dx(item), 0);
      if (widget.content != null) {
        widget.content!(canvas, item.node);
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
    final node = item.node;
    final x = item.x, y = item.y, width = item.width, height = item.height;
    final colors = widget.colorPanel ?? _defaultColors;
    final nodeFill = node['fill'], nodeStroke = node['stroke'];
    final fill = nodeFill is Color
        ? nodeFill
        : widget.fill ?? (item.depth < 2 ? colors[(node['index'] as int) % colors.length] : const Color(0x00FFFFFF));
    final stroke = nodeStroke is Color ? nodeStroke : widget.stroke ?? const Color(0xFFFFFFFF);
    // The svg's own fill and stroke, which the arrow and the text inherit.
    final inheritedFill = widget.fill;
    final inheritedStroke = widget.stroke;

    if (x.isFinite && y.isFinite && width.isFinite && height.isFinite && width != 0 && height != 0) {
      final rect = Rect.fromLTWH(x, y, width, height);
      canvas.drawRect(rect, Paint()..color = fill);
      canvas.drawRect(rect, _strokePaint(stroke));
    }

    if (width > 10 && height > 10 && node['children'] != null && widget.type == TreemapType.nest && item.depth > 0) {
      final path = Path()
        ..moveTo(x + 2, y + height / 2)
        ..lineTo(x + 6, y + height / 2 + 3)
        ..lineTo(x + 2, y + height / 2 + 6)
        ..close();
      canvas.drawPath(path, Paint()..color = inheritedFill ?? const Color(0xFF000000));
      if (inheritedStroke != null) canvas.drawPath(path, _strokePaint(inheritedStroke));
    }

    final name = jsString(node['name']);
    final nameSize = measureText(name, baseStyle, scaler);
    if (width > 20 && height > 20 && nameSize.width < width && nameSize.height < height) {
      _paintLabel(canvas, name, x + 8, y + height / 2 + 7, inheritedFill ?? const Color(0xFF000000), inheritedStroke);
    }
  }

  /// `<text x y fontSize={14}>`: the baseline sits at [y]; stroke goes over the fill.
  void _paintLabel(Canvas canvas, String text, double x, double y, Color fill, Color? stroke) {
    TextStyle style({Color? color, Paint? foreground}) => TextStyle(
          fontFamily: baseStyle.fontFamily,
          fontFamilyFallback: baseStyle.fontFamilyFallback,
          fontWeight: baseStyle.fontWeight,
          fontStyle: baseStyle.fontStyle,
          fontSize: 14,
          color: color,
          foreground: foreground,
        );
    void draw(TextStyle s) {
      final tp = textPainterFor(text, s, scaler);
      tp.paint(canvas, Offset(x, y - tp.computeDistanceToActualBaseline(TextBaseline.alphabetic)));
    }

    draw(style(color: fill));
    if (stroke != null) draw(style(foreground: _strokePaint(stroke)));
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
