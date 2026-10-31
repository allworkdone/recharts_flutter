// LineChart / BarChart / ComposedChart: src/chart/CartesianChart.tsx and
// RechartsWrapper.tsx, with the tooltip state machine of
// src/state/tooltipSlice.ts + combiners/combineTooltipInteractionState.ts,
// the mouse/touch middleware (mouseEventsMiddleware.ts,
// touchEventsMiddleware.ts), externalEventsMiddleware.ts payloads, the
// 'index' method of synchronisation/useChartSynchronisation.tsx (tooltip and
// brush), the accessibility layer (keyboardEventsMiddleware.ts: focus, blur,
// arrow keys; the wrapper's onFocus also fires for focused Brush travellers), the Brush data indexes of src/state/chartDataSlice.ts and
// BrushInternal (Brush.tsx), and the Brush panorama (CategoricalChart.tsx
// `compact`, PanoramaContext).
//
// Pointer input uses a Listener (raw pointer events, no gesture arena) plus a
// MouseRegion for hover enter/exit, so a chart inside a scroll view never
// steals the scroll gesture; the browser does not block page scroll either.

import 'package:flutter/gestures.dart' show kTouchSlop, PointerDeviceKind;
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show HardwareKeyboard, KeyDownEvent, KeyRepeatEvent, LogicalKeyboardKey;
import 'package:flutter/widgets.dart';

import '../animation.dart';
import '../components.dart';
import '../core/curve.dart';
import '../engine/model.dart';
import '../render/painter.dart';
import '../render/svg_text.dart';
import 'brush.dart';
import 'legend.dart';
import 'responsive_container.dart';
import 'tooltip.dart';

/// Shared props of the cartesian charts (`CartesianChartProps`).
abstract class CategoricalChart extends StatefulWidget {
  const CategoricalChart({
    super.key,
    this.width,
    this.height,
    this.data = const [],
    this.layout = ChartLayout.horizontal,
    this.margin = const Margin.all(5),
    this.barCategoryGap = '10%',
    this.barGap = 4,
    this.barSize,
    this.maxBarSize,
    this.stackOffset = StackOffset.none,
    this.reverseStackOrder = false,
    this.syncId,
    this.accessibilityLayer = true,
    this.onClick,
    this.onMouseEnter,
    this.onMouseMove,
    this.onMouseLeave,
    this.children = const [],
  });

  /// When null the chart fills the incoming constraints.
  final double? width;
  final double? height;
  final List<Object?> data;
  final ChartLayout layout;

  /// Missing sides are 0, like Recharts' `setMargin`.
  final Margin margin;

  /// Number or percent string.
  final Object barCategoryGap;

  /// Number or percent string.
  final Object barGap;

  /// Number or percent string.
  final Object? barSize;
  final double? maxBarSize;
  final StackOffset stackOffset;
  final bool reverseStackOrder;

  /// Charts with the same id share the active tooltip index (`syncMethod: 'index'`).
  final Object? syncId;

  /// When false, focusing the chart no longer shows the tooltip at index 0 and
  /// arrow keys no longer move it (keyboardEventsMiddleware.ts).
  final bool accessibilityLayer;
  final ChartEventHandler? onClick;
  final ChartEventHandler? onMouseEnter;
  final ChartEventHandler? onMouseMove;
  final ChartEventHandler? onMouseLeave;
  final List<RechartsElement> children;

  String get chartName;

  @override
  State<CategoricalChart> createState() => _CartesianChartState();
}

class LineChart extends CategoricalChart {
  const LineChart({
    super.key,
    super.width,
    super.height,
    super.data,
    super.layout,
    super.margin,
    super.syncId,
    super.accessibilityLayer,
    super.onClick,
    super.onMouseEnter,
    super.onMouseMove,
    super.onMouseLeave,
    super.children,
  });
  @override
  String get chartName => 'LineChart';
}

class BarChart extends CategoricalChart {
  const BarChart({
    super.key,
    super.width,
    super.height,
    super.data,
    super.layout,
    super.margin,
    super.barCategoryGap,
    super.barGap,
    super.barSize,
    super.maxBarSize,
    super.stackOffset,
    super.reverseStackOrder,
    super.syncId,
    super.accessibilityLayer,
    super.onClick,
    super.onMouseEnter,
    super.onMouseMove,
    super.onMouseLeave,
    super.children,
  });
  @override
  String get chartName => 'BarChart';
}

/// The Brush panorama: the Brush's chart child cloned with the brush size,
/// `padding` as margin and the full data (`compact`). Recharts renders it in
/// the main chart's store, so axis settings, chart name and layout come from
/// the main chart, and both charts' items meet in the axis domains.
class _Panorama extends CategoricalChart {
  _Panorama(this.source,
      {required this.main,
      required this.rootOffset,
      required this.rootSize,
      required Size size,
      required Margin padding,
      required super.data})
      : super(
          width: size.width,
          height: size.height,
          layout: main.layout,
          margin: padding,
          barCategoryGap: source.barCategoryGap,
          barGap: source.barGap,
          barSize: source.barSize,
          maxBarSize: source.maxBarSize,
          stackOffset: source.stackOffset,
          reverseStackOrder: source.reverseStackOrder,
          children: source.children,
        );
  final CategoricalChart source;
  final CategoricalChart main;
  final ChartOffset rootOffset;
  final Size rootSize;
  @override
  String get chartName => main.chartName;
}

class ComposedChart extends CategoricalChart {
  const ComposedChart({
    super.key,
    super.width,
    super.height,
    super.data,
    super.layout,
    super.margin,
    super.barCategoryGap,
    super.barGap,
    super.barSize,
    super.maxBarSize,
    super.stackOffset,
    super.reverseStackOrder,
    super.syncId,
    super.accessibilityLayer,
    super.onClick,
    super.onMouseEnter,
    super.onMouseMove,
    super.onMouseLeave,
    super.children,
  });
  @override
  String get chartName => 'ComposedChart';
}

/// `TooltipInteractionState`.
class _Interaction {
  const _Interaction({this.active = false, this.index, this.coordinate});
  final bool active;
  final int? index;
  final Offset? coordinate;
  _Interaction inactive() => _Interaction(index: index, coordinate: coordinate);
}

/// Everything the tooltip and the hover layer render.
class _TooltipView extends HoverState {
  const _TooltipView({
    super.cursorVisible,
    super.coordinate,
    super.activeDataPoints,
    this.active = false,
    this.activeIndex,
    this.label,
    this.payload = const [],
    this.interactionActive = false,
  });
  final bool active;
  final int? activeIndex;
  final Object? label;
  final List<TooltipPayloadEntry> payload;
  final bool interactionActive;
}

class _ViewNotifier extends ChangeNotifier implements ValueListenable<_TooltipView> {
  _TooltipView _value = const _TooltipView();
  @override
  _TooltipView get value => _value;
  void set(_TooltipView v, {bool notify = true}) {
    _value = v;
    if (notify) notifyListeners();
  }
}

/// Registry for `syncId` with `syncMethod="index"`.
final Map<Object, Set<_CartesianChartState>> _syncGroups = {};

class _CartesianChartState extends State<CategoricalChart> with TickerProviderStateMixin {
  final Map<String, SeriesAnimator<BarRect>> _barAnimators = {};
  final Map<String, SeriesAnimator<LinePoint>> _lineAnimators = {};
  final Map<String, AnimatedLineLength> _lineLengths = {};
  final _ViewNotifier _view = _ViewNotifier();

  _Interaction _hover = const _Interaction();
  _Interaction _click = const _Interaction();
  _Interaction _sync = const _Interaction();
  _Interaction _keyboard = const _Interaction();
  final FocusNode _focusNode = FocusNode(debugLabel: 'recharts chart');

  /// What has DOM focus inside the chart, in Recharts terms: the svg
  /// (`tabIndex=0`, null traveller) or a Brush traveller. The Flutter
  /// [_focusNode] only routes keys; a model keeps Flutter web's first-focus
  /// handling (the view focuses its first focusable node) from moving it.
  ({BrushTravellerId? traveller})? _focusTarget;
  final GlobalKey<BrushLayerState> _brushKey = GlobalKey();
  CartesianModel? _model;
  Size? _customLegendSize;
  Offset? _downPosition;
  Object? _registeredSyncId;

  // chartDataSlice: the slice of `data` the chart renders, set by the Brush.
  int _dataStartIndex = 0;
  int _dataEndIndex = 0;
  List<Object?>? _chartData;
  (int?, int?)? _brushIndexProps;
  BrushStartEndIndex? _brushEmitted;

  @override
  void initState() {
    super.initState();
    PaintingBinding.instance.systemFonts.addListener(_onFontsChanged);
    _focusNode.addListener(_onFocusChange);
  }

  /// Text was measured with fallback fonts until now; measure again.
  void _onFontsChanged() {
    clearTextCache();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_onFontsChanged);
    _unregisterSync();
    _focusNode.dispose();
    for (final a in _barAnimators.values) {
      a.dispose();
    }
    for (final a in _lineAnimators.values) {
      a.dispose();
    }
    _view.dispose();
    super.dispose();
  }

  void _registerSync() {
    if (_registeredSyncId == widget.syncId) return;
    _unregisterSync();
    if (widget.syncId != null) {
      _syncGroups.putIfAbsent(widget.syncId!, () => {}).add(this);
      _registeredSyncId = widget.syncId;
    }
  }

  void _unregisterSync() {
    final id = _registeredSyncId;
    if (id == null) return;
    _syncGroups[id]?.remove(this);
    if (_syncGroups[id]?.isEmpty ?? false) _syncGroups.remove(id);
    _registeredSyncId = null;
  }

  // -------------------------------------------------------------- brush

  Brush? get _brush => widget is _Panorama ? null : widget.children.whereType<Brush>().firstOrNull;

  /// `setChartData` (keeps dataStartIndex, resets dataEndIndex), then the
  /// Brush effect re-applying controlled `startIndex`/`endIndex`.
  void _syncDataIndexes() {
    final data = widget.data;
    // ponytail: a rebuilt but equal list is not "new data" (Recharts compares identity).
    final dataChanged = _chartData == null || !(identical(data, _chartData) || listEquals(data, _chartData));
    if (dataChanged) {
      _chartData = data;
      if (data.isNotEmpty && _dataEndIndex != data.length - 1) _dataEndIndex = data.length - 1;
    }
    final brush = _brush;
    final props = brush == null ? null : (brush.startIndex, brush.endIndex);
    if (props != null && (dataChanged || props != _brushIndexProps)) {
      if (brush!.startIndex != null) _dataStartIndex = brush.startIndex!;
      if (brush.endIndex != null) _dataEndIndex = brush.endIndex!;
    }
    _brushIndexProps = props;

    // useBrushChartSynchronisation
    final range = (startIndex: _dataStartIndex, endIndex: _dataEndIndex);
    final id = widget.syncId;
    if (brush != null && id != null && range != _brushEmitted) {
      _brushEmitted = range;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        for (final other in [...?_syncGroups[id]]) {
          if (!identical(other, this) && other.mounted) other._receiveBrushSync(range);
        }
      });
    }
  }

  void _receiveBrushSync(BrushStartEndIndex range) {
    if (range.startIndex == _dataStartIndex && range.endIndex == _dataEndIndex) return;
    setState(() {
      _dataStartIndex = range.startIndex;
      _dataEndIndex = range.endIndex;
    });
  }

  /// `BrushInternal.onChange`.
  void _onBrushChange(BrushStartEndIndex next) {
    if (next.startIndex == _dataStartIndex && next.endIndex == _dataEndIndex) return;
    _brush?.onChange?.call(next);
    setState(() {
      _dataStartIndex = next.startIndex;
      _dataEndIndex = next.endIndex;
    });
  }

  void _onBrushDragEnd() => _brush?.onDragEnd?.call((startIndex: _dataStartIndex, endIndex: _dataEndIndex));

  /// The panorama renders its own items over the main chart's axis settings.
  List<RechartsElement> get _modelChildren {
    final w = widget;
    if (w is! _Panorama) return w.children;
    return [
      ...w.main.children.whereType<CartesianAxisElement>(),
      ...w.children.where((c) => c is! CartesianAxisElement && c is! Tooltip && c is! Legend && c is! Brush),
    ];
  }

  // -------------------------------------------------------------- tooltip state

  _Interaction _interactionState(CartesianModel m) {
    final tooltip = m.tooltipSettings;
    final mouse = tooltip?.trigger == TooltipTrigger.click ? _click : _hover;
    if (mouse.active) return mouse;
    if (_keyboard.active) return _keyboard;
    if (_sync.active && _sync.index != null) return _sync;
    if (mouse.index != null) {
      if (tooltip?.active == true) return _Interaction(active: true, index: mouse.index, coordinate: mouse.coordinate);
    } else if (tooltip?.defaultIndex != null) {
      return _Interaction(active: true, index: tooltip!.defaultIndex);
    }
    return _Interaction(coordinate: mouse.coordinate);
  }

  _TooltipView _computeView(CartesianModel m) {
    final tooltip = m.tooltipSettings;
    final state = _interactionState(m);
    final activeIndex = combineActiveTooltipIndex(m, state.index);
    final isActive = state.active && activeIndex != null;
    final finalIsActive = tooltip?.active ?? isActive;
    var coordinate = state.coordinate;
    if (coordinate == null && tooltip?.defaultIndex != null) coordinate = _coordinateForIndex(m, tooltip!.defaultIndex!);
    final payload = tooltipPayloadOf(m, activeIndex);
    var finalPayload = finalIsActive ? payload : const <TooltipPayloadEntry>[];
    if (tooltip?.filterNull ?? true) {
      finalPayload = [
        for (final e in finalPayload)
          if (e.value != null && (!e.hide || (tooltip?.includeHidden ?? false))) e,
      ];
    }
    return _TooltipView(
      cursorVisible: tooltip != null && finalIsActive,
      coordinate: coordinate,
      activeDataPoints: {for (final p in payload) ?p.payload}.toList(),
      active: finalIsActive,
      activeIndex: activeIndex,
      label: activeLabelOf(m, activeIndex),
      payload: finalPayload,
      interactionActive: state.active,
    );
  }

  void _refreshView() {
    final m = _model;
    if (m == null) return;
    _view.set(_computeView(m));
  }

  /// `combineCoordinateForDefaultIndex` (Line and Bar have no `getPosition`).
  Offset? _coordinateForIndex(CartesianModel m, int i) {
    if (i < 0 || i >= m.tooltipTicks.length) return null;
    final c = m.tooltipTicks[i].coordinate;
    return m.layout == ChartLayout.horizontal
        ? Offset(c, (m.offset.top + m.size.height) / 2)
        : Offset((m.offset.left + m.size.width) / 2, c);
  }

  // -------------------------------------------------------------- keyboard

  /// The wrapper's React `onFocus`/`onBlur` are focusin/focusout: they fire for
  /// every descendant, so moving between svg and travellers is a blur then a focus.
  void _setFocusTarget(({BrushTravellerId? traveller})? target) {
    if (target == _focusTarget || !mounted) return;
    final hadFocus = _focusTarget != null;
    setState(() => _focusTarget = target);
    if (hadFocus) _blurAction();
    if (target != null) _focusAction();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      _setFocusTarget(null);
    } else if (_focusTarget == null) {
      _setFocusTarget((traveller: null));
    }
  }

  /// `focusAction`: the first focus shows the tooltip at index 0.
  void _focusAction() {
    final m = _model;
    if (!widget.accessibilityLayer || m == null || _keyboard.active || _keyboard.index != null) return;
    _keyboard = _Interaction(active: true, index: 0, coordinate: _coordinateForIndex(m, 0));
    _refreshView();
    _broadcastSync();
  }

  /// `blurAction`.
  void _blurAction() {
    if (!_keyboard.active) return;
    _keyboard = _keyboard.inactive();
    _refreshView();
    _broadcastSync();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = e.logicalKey;
    final traveller = _focusTarget?.traveller;
    // Tab order: svg, start traveller, end traveller.
    if (key == LogicalKeyboardKey.tab && _brushKey.currentState != null) {
      final order = <BrushTravellerId?>[null, BrushTravellerId.startX, BrushTravellerId.endX];
      final next = order.indexOf(traveller) + (HardwareKeyboard.instance.isShiftPressed ? -1 : 1);
      if (next < 0 || next >= order.length) return KeyEventResult.ignored;
      _setFocusTarget((traveller: order[next]));
      return KeyEventResult.handled;
    }
    // TravellerLayer onKeyDown: arrows move the traveller and stop propagation.
    if (traveller != null && (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight)) {
      _brushKey.currentState?.handleTravellerMoveKeyboard(key == LogicalKeyboardKey.arrowRight ? 1 : -1, traveller);
      return KeyEventResult.handled;
    }
    return _keyDownAction(key);
  }

  /// `keyDownAction`: ArrowLeft/ArrowRight move the tooltip, Enter toggles it.
  KeyEventResult _keyDownAction(LogicalKeyboardKey key) {
    final m = _model;
    if (!widget.accessibilityLayer || m == null) return KeyEventResult.ignored;
    final right = key == LogicalKeyboardKey.arrowRight;
    if (!right && key != LogicalKeyboardKey.arrowLeft && key != LogicalKeyboardKey.enter) return KeyEventResult.ignored;
    final currentIndex = combineActiveTooltipIndex(m, _keyboard.index) ?? -1;
    final isOutsideDomain = currentIndex < 0;
    if (key == LogicalKeyboardKey.enter) {
      if (isOutsideDomain) return KeyEventResult.ignored;
      _keyboard = _Interaction(
          active: !_keyboard.active, index: _keyboard.index, coordinate: _coordinateForIndex(m, _keyboard.index!));
    } else {
      // selectChartDirection
      final reversed = m.layout == ChartLayout.horizontal
          ? widget.children.whereType<XAxis>().any((a) => a.reversed)
          : widget.children.whereType<YAxis>().any((a) => a.reversed);
      final movement = (right ? 1 : -1) * (reversed ? -1 : 1);
      final displayed = tooltipDisplayedData(m);
      var nextIndex = -1;
      if (isOutsideDomain) {
        final candidates = movement > 0
            ? List.generate(displayed.length, (i) => i)
            : List.generate(displayed.length, (i) => displayed.length - 1 - i);
        nextIndex = candidates.where((i) => combineActiveTooltipIndex(m, i) != null).firstOrNull ?? -1;
        if (nextIndex < 0) return KeyEventResult.ignored;
      } else {
        nextIndex = currentIndex + movement;
        final dataLength = m.tooltipTicks.isNotEmpty ? m.tooltipTicks.length : displayed.length;
        if (dataLength == 0 || nextIndex >= dataLength || nextIndex < 0) return KeyEventResult.ignored;
      }
      _keyboard = _Interaction(active: true, index: nextIndex, coordinate: _coordinateForIndex(m, nextIndex));
    }
    _refreshView();
    _broadcastSync();
    // React does not preventDefault here: the key still reaches the page.
    return KeyEventResult.ignored;
  }

  /// A mouse down (or a tap) focuses the Brush traveller under it, else the
  /// chart's svg (`tabIndex=0`), the nearest focusable ancestor in the browser.
  void _focusFromPointer(Offset local) {
    if (widget is _Panorama) return;
    _setFocusTarget((traveller: _brushKey.currentState?.travellerAt(local)));
    _focusNode.requestFocus();
  }

  ChartEventState _eventState() {
    final v = _view.value;
    return ChartEventState(
      activeCoordinate: v.coordinate,
      activeIndex: v.activeIndex,
      activeTooltipIndex: v.activeIndex,
      activeLabel: v.label,
      isTooltipActive: v.interactionActive,
    );
  }

  // -------------------------------------------------------------- input

  void _setHoverFromPointer(Offset local, {required bool leaveWhenOutside}) {
    final m = _model;
    if (m == null || !mounted) return;
    final props = activePropsFromPointer(m, local);
    if (props != null) {
      _hover = _Interaction(active: true, index: props.activeIndex, coordinate: props.activeCoordinate);
      _sync = const _Interaction();
    } else if (leaveWhenOutside) {
      _hover = _hover.inactive();
    } else {
      return;
    }
    _refreshView();
    _broadcastSync();
  }

  void _mouseLeave() {
    if (!mounted) return;
    _hover = _hover.inactive();
    _refreshView();
    _broadcastSync();
  }

  /// `mouseClickAction` -> `setMouseClickAxisIndex`.
  void _chartClick(Offset local) {
    final m = _model;
    if (m == null) return;
    final props = activePropsFromPointer(m, local);
    if (props != null) {
      _click = _Interaction(active: true, index: props.activeIndex, coordinate: props.activeCoordinate);
      _refreshView();
    }
  }

  void _broadcastSync() {
    final id = _registeredSyncId;
    final m = _model;
    if (id == null || m == null || m.tooltipSettings == null) return;
    final v = _view.value;
    for (final other in _syncGroups[id] ?? const <_CartesianChartState>{}) {
      if (!identical(other, this)) other._receiveSync(v.active, v.activeIndex, v.coordinate, m.viewBox);
    }
  }

  void _receiveSync(bool active, int? index, Offset? coordinate, Rect sourceViewBox) {
    final m = _model;
    if (m == null) return;
    if (!active) {
      _sync = const _Interaction();
    } else {
      final vb = m.viewBox;
      final scaled = coordinate == null
          ? null
          : Offset(
              vb.left + (sourceViewBox.width != 0 ? (coordinate.dx - sourceViewBox.left) / sourceViewBox.width : 0) * vb.width,
              vb.top + (sourceViewBox.height != 0 ? (coordinate.dy - sourceViewBox.top) / sourceViewBox.height : 0) * vb.height,
            );
      _sync = _Interaction(active: true, index: index, coordinate: scaled);
    }
    _refreshView();
  }

  void _onPointerDown(PointerDownEvent e) {
    _downPosition = e.localPosition;
    final touch = e.kind == PointerDeviceKind.touch || e.kind == PointerDeviceKind.stylus;
    if (!touch) _focusFromPointer(e.localPosition);
    // Touch: the first touchmove (or the tap's emulated mousemove) shows the tooltip.
    _setHoverFromPointer(e.localPosition, leaveWhenOutside: !touch);
  }

  void _onPointerMove(PointerMoveEvent e) {
    final touch = e.kind == PointerDeviceKind.touch || e.kind == PointerDeviceKind.stylus;
    _setHoverFromPointer(e.localPosition, leaveWhenOutside: !touch);
    if (!touch) widget.onMouseMove?.call(_eventState(), e);
  }

  void _onPointerUp(PointerUpEvent e) {
    final down = _downPosition;
    _downPosition = null;
    if (down == null) return;
    final touch = e.kind == PointerDeviceKind.touch || e.kind == PointerDeviceKind.stylus;
    if (touch && (e.localPosition - down).distance > kTouchSlop) return;
    if (touch) _focusFromPointer(e.localPosition);
    _chartClick(e.localPosition);
    widget.onClick?.call(_eventState(), e);
  }

  // -------------------------------------------------------------- animation

  void _syncAnimators(CartesianModel m, bool reducedMotion) {
    final live = <String>{};
    for (final s in m.series) {
      final el = s.item.element;
      final id = s.item.id;
      live.add(id);
      final active = el.isAnimationActive ?? !reducedMotion;
      if (s.item.isBar) {
        final a = _barAnimators.putIfAbsent(id, () => SeriesAnimator<BarRect>(this, matchBy: MatchBy.append));
        a.update(s.item.hide ? null : s.rects,
            active: active,
            begin: el.animationBegin,
            duration: el.animationDuration,
            easing: el.animationEasing,
            onAnimationStart: el.onAnimationStart,
            onAnimationEnd: el.onAnimationEnd);
      } else {
        final a = _lineAnimators.putIfAbsent(id, () => SeriesAnimator<LinePoint>(this, matchBy: MatchBy.byIndex));
        final restarted = a.update(s.item.hide ? null : s.points,
            active: active,
            begin: el.animationBegin,
            duration: el.animationDuration,
            easing: el.animationEasing,
            onAnimationStart: el.onAnimationStart,
            onAnimationEnd: el.onAnimationEnd);
        if (restarted && a.target == null) _lineLengths.remove(id);
        _lineLengths.putIfAbsent(id, AnimatedLineLength.new);
      }
    }
    for (final id in _barAnimators.keys.where((k) => !live.contains(k)).toList()) {
      _barAnimators.remove(id)!.dispose();
    }
    for (final id in _lineAnimators.keys.where((k) => !live.contains(k)).toList()) {
      _lineAnimators.remove(id)!.dispose();
      _lineLengths.remove(id);
    }
  }

  // -------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    _registerSync();
    _syncDataIndexes();
    final responsive = widget is _Panorama ? null : ResponsiveContainerScope.maybeOf(context);
    return LayoutBuilder(builder: (context, constraints) {
      final width = responsive?.width ?? widget.width ?? (constraints.hasBoundedWidth ? constraints.maxWidth : 0.0);
      final height =
          responsive?.height ?? widget.height ?? (constraints.hasBoundedHeight ? constraints.maxHeight : 0.0);
      if (width <= 0 || height <= 0) return SizedBox(width: width, height: height);
      return _buildChart(context, Size(width, height));
    });
  }

  Widget _buildChart(BuildContext context, Size size) {
    final textStyle = DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    final reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final w = widget;
    final isPanorama = w is _Panorama;
    final children = _modelChildren;
    final legend = children.whereType<Legend>().firstOrNull;
    final items = collectItems(children);

    LegendLayout? legendLayout;
    var legendSize = Size.zero;
    if (legend != null) {
      final payload = legendPayloadOf(items, legend);
      if (legend.content == null) {
        legendLayout = computeLegendLayout(
            legend: legend,
            payload: payload,
            chartSize: size,
            margin: widget.margin,
            baseStyle: textStyle,
            scaler: scaler);
        legendSize = legendLayout.size;
      } else {
        legendSize = _customLegendSize ?? Size.zero;
      }
    }

    TextStyle tickStyle(CartesianAxisElement? axis) {
      var style = textStyle;
      if (axis == null) return style;
      if (axis.fontSize != null) style = style.copyWith(fontSize: axis.fontSize);
      if (axis.tick is TextStyle) style = style.merge(axis.tick as TextStyle);
      return style;
    }

    final m = computeCartesianModel(
      chartName: widget.chartName,
      size: size,
      data: widget.data,
      children: children,
      layout: widget.layout,
      margin: widget.margin,
      barCategoryGap: widget.barCategoryGap,
      barGap: widget.barGap,
      barSize: widget.barSize,
      maxBarSize: widget.maxBarSize,
      stackOffset: widget.stackOffset,
      reverseStackOrder: widget.reverseStackOrder,
      legendSize: legendSize,
      measureFor: (axis) {
        final style = tickStyle(axis);
        return (text) => measureText(text, style, scaler);
      },
      dataStartIndex: _dataStartIndex,
      dataEndIndex: _dataEndIndex,
      panorama: isPanorama,
      sharedChildren: w is _Panorama ? w.main.children : (_brush?.child?.children ?? const []),
      rootOffset: w is _Panorama ? w.rootOffset : null,
      rootSize: w is _Panorama ? w.rootSize : null,
    );
    _model = m;
    _syncAnimators(m, reducedMotion);
    // Everything that reads the view is rebuilt below, so no notification.
    _view.set(_computeView(m), notify: false);

    final frame = ChartFrame(
      model: m,
      children: children,
      textStyle: textStyle,
      textScaler: scaler,
      barAnimators: _barAnimators,
      lineAnimators: _lineAnimators,
      lineLengths: _lineLengths,
    );
    final animations = Listenable.merge([
      for (final a in _barAnimators.values) a.controller,
      for (final a in _lineAnimators.values) a.controller,
    ]);

    Widget layer(ChartLayer l, {Listenable? repaint}) => Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(painter: CartesianPainter(l, frame, hover: _view, repaint: repaint)),
          ),
        );

    final tooltip = m.tooltipSettings;
    final brush = m.brushRect == null ? null : _brush;
    final stack = Stack(
      clipBehavior: Clip.none,
      children: [
        layer(ChartLayer.background),
        // Brush has no zIndex: it paints in the default layer, under every positive one.
        if (brush != null && _chartData!.isNotEmpty)
          Positioned.fill(
            key: const ValueKey('brush'),
            child: BrushLayer(
              key: _brushKey,
              settings: brush,
              rect: m.brushRect!.translate(0, brush.dy ?? 0),
              data: _chartData!,
              startIndex: _dataStartIndex,
              endIndex: _dataEndIndex,
              onChange: _onBrushChange,
              onDragEnd: _onBrushDragEnd,
              textStyle: textStyle,
              textScaler: scaler,
              focusedTraveller: _focusTarget?.traveller,
              panorama: brush.child == null
                  ? null
                  : _Panorama(brush.child!,
                      main: widget,
                      rootOffset: m.offset,
                      rootSize: m.size,
                      size: m.brushRect!.size,
                      padding: brush.padding,
                      data: _chartData!),
            ),
          ),
        layer(ChartLayer.cursorBelow, repaint: _view),
        layer(ChartLayer.main, repaint: animations),
        layer(ChartLayer.overlay, repaint: _view),
        layer(ChartLayer.labels),
        if (legend != null) _buildLegend(legend, legendLayout, size, scaler),
        if (tooltip != null) Positioned.fill(child: IgnorePointer(child: _buildTooltip(tooltip, m, reducedMotion))),
      ],
    );

    final content = TapRegion(
        onTapOutside: (e) {
          // Clicking elsewhere blurs the chart.
          if (_focusNode.hasFocus) _focusNode.unfocus();
          _setFocusTarget(null);
          // Touch browsers fire mouseleave when another element is tapped.
          if (e.kind == PointerDeviceKind.touch && _hover.active) _mouseLeave();
        },
        child: MouseRegion(
          onEnter: (e) {
            _setHoverFromPointer(e.localPosition, leaveWhenOutside: true);
            widget.onMouseEnter?.call(_eventState(), e);
          },
          onHover: (e) {
            _setHoverFromPointer(e.localPosition, leaveWhenOutside: true);
            widget.onMouseMove?.call(_eventState(), e);
          },
          onExit: (e) {
            _mouseLeave();
            widget.onMouseLeave?.call(_eventState(), e);
          },
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerCancel: (_) => _downPosition = null,
            child: stack,
          ),
        ),
      );
    return SizedBox.fromSize(
      size: size,
      // The panorama is a nested svg without tabIndex.
      child: isPanorama ? content : Focus(focusNode: _focusNode, onKeyEvent: _onKey, child: content),
    );
  }

  Widget _buildLegend(Legend legend, LegendLayout? layout, Size size, TextScaler scaler) {
    if (layout != null) {
      final pos = legendPosition(legend, size, widget.margin, layout.size);
      return Positioned(
        left: pos.dx,
        top: pos.dy,
        child: IgnorePointer(child: DefaultLegendContent(legend: legend, layout: layout, scaler: scaler)),
      );
    }
    final payload = legendPayloadOf(collectItems(widget.children), legend);
    final box = _customLegendSize ?? Size.zero;
    final pos = legendPosition(legend, size, widget.margin, box);
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: SizeReporter(
        onSize: (s) {
          if (mounted && s != _customLegendSize) setState(() => _customLegendSize = s);
        },
        child: legend.content!(payload),
      ),
    );
  }

  Widget _buildTooltip(Tooltip tooltip, CartesianModel m, bool reducedMotion) {
    final animate = tooltip.isAnimationActive ?? !reducedMotion;
    return ListenableBuilder(
      listenable: _view,
      builder: (context, _) {
        final v = _view.value;
        final content = tooltip.content != null
            ? tooltip.content!(TooltipContentProps(
                active: v.active,
                payload: v.payload,
                label: v.label,
                coordinate: v.coordinate,
                activeIndex: v.activeIndex,
              ))
            : DefaultTooltipContent(
                payload: v.payload,
                label: v.label,
                separator: tooltip.separator,
                contentStyle: tooltip.contentStyle,
                itemStyle: tooltip.itemStyle,
                labelStyle: tooltip.labelStyle,
                itemSorter: tooltip.itemSorter,
                formatter: tooltip.formatter,
                labelFormatter: tooltip.labelFormatter,
              );
        return TooltipBoundingBox(
          vsync: this,
          active: v.active,
          hasPayload: v.payload.isNotEmpty,
          coordinate: v.coordinate,
          viewBox: m.viewBox,
          offset: tooltip.offset,
          allowEscapeViewBox: tooltip.allowEscapeViewBox,
          reverseDirection: tooltip.reverseDirection,
          position: tooltip.position,
          animate: animate,
          animationDuration: tooltip.animationDuration,
          animationEasing: tooltip.animationEasing,
          child: content,
        );
      },
    );
  }
}
