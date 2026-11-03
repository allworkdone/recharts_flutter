// LineChart / BarChart / AreaChart / ComposedChart / ScatterChart: src/chart/CartesianChart.tsx and
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
// Tooltip event type 'item' (selectTooltipEventType.ts; BarChart allows it,
// ScatterChart has nothing else): bars, their backgrounds and scatter symbols
// dispatch item hover/click like the onMouseEnter/onMouseLeave/onClick
// handlers of tooltipContext.tsx, picked by hit testing what is painted under
// the pointer, and combineTooltipPayloadConfigurations.ts narrows the payload
// to that item.
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
import '../util.dart' show defaultIndexIsFractional, defaultPayloadIndex;
import '../core/curve.dart';
import '../core/js_math.dart' show jsRound;
import '../engine/axis.dart' show GraphicalItem;
import '../engine/funnel.dart';
import '../engine/model.dart';
import '../engine/polar_scene.dart' show PolarCoordinate;
import '../render/label.dart';
import '../render/painter.dart';
import '../render/svg_text.dart';
import 'brush.dart';
import 'legend.dart';
import 'responsive_container.dart';
import 'sync_registry.dart';
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
    this.baseValue,
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

  /// Default [Area.baseValue]: `num`, `'dataMin'` or `'dataMax'`.
  final Object? baseValue;

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

class AreaChart extends CategoricalChart {
  const AreaChart({
    super.key,
    super.width,
    super.height,
    super.data,
    super.layout,
    super.margin,
    super.stackOffset,
    super.reverseStackOrder,
    super.baseValue,
    super.syncId,
    super.accessibilityLayer,
    super.onClick,
    super.onMouseEnter,
    super.onMouseMove,
    super.onMouseLeave,
    super.children,
  });
  @override
  String get chartName => 'AreaChart';
}

class FunnelChart extends CategoricalChart {
  const FunnelChart({
    super.key,
    super.width,
    super.height,
    super.data,
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
  String get chartName => 'FunnelChart';
}

/// src/chart/ScatterChart.tsx: tooltips are always per item ('item' event
/// type) with a cross cursor; the axes usually need `type: number`.
class ScatterChart extends CategoricalChart {
  const ScatterChart({
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
  String get chartName => 'ScatterChart';
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
          baseValue: source.baseValue,
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
    super.baseValue,
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
  const _Interaction({this.active = false, this.index, this.coordinate, this.dataKey, this.itemId, this.desired});
  final bool active;

  /// `Number(defaultIndex)` when the state comes from `Tooltip.defaultIndex`.
  final double? desired;
  final int? index;
  final Offset? coordinate;
  final Object? dataKey;

  /// `graphicalItemId`.
  final String? itemId;
  _Interaction inactive() => _Interaction(index: index, coordinate: coordinate, dataKey: dataKey, itemId: itemId);
  _Interaction activate() =>
      _Interaction(active: true, index: index, coordinate: coordinate, dataKey: dataKey, itemId: itemId);
}

/// The graphical item element under the pointer: a bar or its background.
typedef _ItemHit = ({String id, Object? dataKey, int index, Offset tooltipPosition, bool background});

/// Everything the tooltip and the hover layer render.
class _TooltipView extends HoverState {
  const _TooltipView({
    super.cursorVisible,
    super.coordinate,
    super.activeDataPoints,
    super.activeIndex,
    super.activeDataKey,
    super.activeBarLayer,
    this.active = false,
    this.label,
    this.payload = const [],
    this.interactionActive = false,
    this.itemEventType = false,
  });
  final bool active;
  final Object? label;
  final List<TooltipPayloadEntry> payload;
  final bool interactionActive;

  /// The Tooltip renders no label for the 'item' event type.
  final bool itemEventType;
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

class _CartesianChartState extends State<CategoricalChart> with TickerProviderStateMixin implements TooltipSyncPeer {
  final Map<String, SeriesAnimator<BarRect>> _barAnimators = {};
  final Map<String, SeriesAnimator<LinePoint>> _lineAnimators = {};
  final Map<String, AnimatedLineLength> _lineLengths = {};
  final Map<String, AreaBaseLineAnimation> _areaBaseLines = {};
  final Map<String, SeriesAnimator<FunnelTrapezoid>> _funnelAnimators = {};
  final Map<String, SeriesAnimator<ScatterPoint>> _scatterAnimators = {};
  final Map<String, ErrorBarAnimation> _errorBarAnimations = {};
  final _ViewNotifier _view = _ViewNotifier();

  _Interaction _hover = const _Interaction();
  _Interaction _click = const _Interaction();
  _Interaction _itemHover = const _Interaction();
  _Interaction _itemClick = const _Interaction();
  _ItemHit? _hoveredItem;
  _ItemHit? _downItem;
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
  ChartFrame? _frame;
  final Map<Object, AutoYAxisWidth> _yAxisWidths = {};
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
    for (final a in _funnelAnimators.values) {
      a.dispose();
    }
    for (final a in _scatterAnimators.values) {
      a.dispose();
    }
    for (final a in _errorBarAnimations.values) {
      a.dispose();
    }
    _view.dispose();
    super.dispose();
  }

  void _registerSync() {
    if (_registeredSyncId == widget.syncId) return;
    _unregisterSync();
    if (widget.syncId != null) {
      joinSyncGroup(widget.syncId!, this);
      _registeredSyncId = widget.syncId;
    }
  }

  void _unregisterSync() {
    final id = _registeredSyncId;
    if (id == null) return;
    leaveSyncGroup(id, this);
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
        for (final other in syncPeers(id, this)) {
          if (other.mounted) other.receiveBrushSync(range);
        }
      });
    }
  }

  @override
  void receiveBrushSync(BrushStartEndIndex range) {
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

  /// `combineTooltipEventType`: `shared={false}` selects 'item' where the
  /// chart validates it, BarChart; FunnelChart and ScatterChart only know 'item'.
  bool _isItemEventType(CartesianModel m) =>
      m.chartName == 'FunnelChart' ||
      m.chartName == 'ScatterChart' ||
      (m.tooltipSettings?.shared == false && m.chartName == 'BarChart');

  _Interaction _interactionState(CartesianModel m) {
    final tooltip = m.tooltipSettings;
    final click = tooltip?.trigger == TooltipTrigger.click;
    final mouse = _isItemEventType(m) ? (click ? _itemClick : _itemHover) : (click ? _click : _hover);
    if (mouse.active) return mouse;
    if (_keyboard.active) return _keyboard;
    if (_sync.active && _sync.index != null) return _sync;
    if (mouse.index != null) {
      if (tooltip?.active == true) return mouse.activate();
    } else if (tooltip?.defaultIndex != null) {
      final desired = tooltip!.defaultIndexNumber;
      return _Interaction(active: true, index: defaultPayloadIndex(desired), desired: desired);
    }
    return _Interaction(coordinate: mouse.coordinate);
  }

  /// `combineTooltipPayloadConfigurations` for the 'item' event type.
  Iterable<GraphicalItem> _itemPayloadConfigurations(CartesianModel m) {
    if (m.items.isEmpty) return const [];
    final tooltip = m.tooltipSettings;
    final id = (tooltip?.trigger == TooltipTrigger.click ? _itemClick : _itemHover).itemId;
    // A synchronised chart shows all of its items at the synced index.
    if (_sync.active && id == null) return m.items;
    // defaultIndex and keyboard have nothing to filter by: the first item.
    if (id == null && (tooltip?.defaultIndex != null || _keyboard.active)) return [m.items.first];
    return m.items.where((i) => i.id == id);
  }

  /// `combineTooltipPayloadConfigurations` for a FunnelChart: the hovered funnel, else the first.
  List<TooltipPayloadEntry> _funnelPayload(CartesianModel m, int? activeIndex) {
    if (activeIndex == null || m.funnels.isEmpty) return const [];
    final id = (m.tooltipSettings?.trigger == TooltipTrigger.click ? _itemClick : _itemHover).itemId;
    final funnels = id == null ? [m.funnels.first] : m.funnels.where((f) => f.id == id);
    return [
      for (final f in funnels)
        if (!f.settings.hide) ?funnelTooltipEntry(f, m.chartData, activeIndex),
    ];
  }

  _TooltipView _computeView(CartesianModel m) {
    final tooltip = m.tooltipSettings;
    final item = _isItemEventType(m);
    final state = _interactionState(m);
    final activeIndex = combineActiveTooltipIndex(m, state.index);
    final isActive = state.active && activeIndex != null;
    final finalIsActive = tooltip?.active ?? isActive;
    var coordinate = state.coordinate;
    final desired = state.desired ?? tooltip?.defaultIndexNumber;
    final fractional = state.desired != null && defaultIndexIsFractional(state.desired, tooltipDisplayedData(m).length);
    // The coordinate is `tooltipTicks[Number(defaultIndex)]`: a whole, in-range number only.
    if (coordinate == null && desired != null && desired.isFinite && desired == desired.truncateToDouble()) {
      coordinate = _coordinateForIndex(m, desired.toInt());
    }
    final payload = m.chartName == 'FunnelChart'
        ? _funnelPayload(m, activeIndex)
        : tooltipPayloadOf(m, activeIndex, items: item ? _itemPayloadConfigurations(m) : null, itemEventType: item);
    var finalPayload = finalIsActive ? payload : const <TooltipPayloadEntry>[];
    if (tooltip?.filterNull ?? true) {
      finalPayload = [
        for (final e in finalPayload)
          if (e.value != null && (!e.hide || (tooltip?.includeHidden ?? false))) e,
      ];
    }
    return _TooltipView(
      // Cursor.tsx renders nothing for the 'item' event type outside ScatterChart.
      cursorVisible: tooltip != null && finalIsActive && !fractional && (!item || m.chartName == 'ScatterChart'),
      coordinate: coordinate,
      activeDataPoints: {for (final p in payload) ?p.payload}.toList(),
      activeIndex: fractional ? null : activeIndex,
      activeDataKey: state.dataKey,
      activeBarLayer: nextActiveBarLayer(m, _view.value.activeBarLayer, fractional ? null : activeIndex, state.dataKey),
      active: finalIsActive,
      label: fractional ? null : activeLabelOf(m, activeIndex),
      payload: finalPayload,
      interactionActive: state.active,
      itemEventType: item,
    );
  }

  void _refreshView() {
    final m = _model;
    if (m == null) return;
    _view.set(_computeView(m));
  }

  /// `combineCoordinateForDefaultIndex`: the first item's `getPosition` (Scatter
  /// and Funnel have one: the item's tooltip position), else the tooltip tick.
  Offset? _coordinateForIndex(CartesianModel m, int i) {
    if (m.funnels.isNotEmpty) {
      final p = m.funnels.first.trapezoids.elementAtOrNull(i)?.tooltipPosition;
      if (p != null) return p;
    }
    final first = m.items.firstOrNull;
    if (first != null && first.isScatter) {
      final p = scatterPointsOf(m, first)?.elementAtOrNull(i);
      if (p != null) return p.tooltipPosition;
    }
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
      activeDataKey: v.activeDataKey,
      activeIndex: v.activeIndex,
      activeTooltipIndex: v.activeIndex,
      activeLabel: v.label,
      isTooltipActive: v.interactionActive,
    );
  }

  // -------------------------------------------------------------- input

  /// mouseMoveAction. With the 'item' event type only the items react, through
  /// their enter/leave handlers.
  void _setHoverFromPointer(Offset local, {required bool leaveWhenOutside}) {
    final m = _model;
    if (m == null || !mounted) return;
    if (_isItemEventType(m)) return _setItemHover(_itemAt(local));
    final props = activePropsFromPointer(m, local);
    if (props != null) {
      // setMouseOverAxisIndex
      _hover = _Interaction(active: true, index: props.activeIndex, coordinate: props.activeCoordinate);
      _sync = const _Interaction();
      _keyboard = _keyboard.inactive();
    } else if (leaveWhenOutside) {
      _hover = _hover.inactive();
    } else {
      return;
    }
    _refreshView();
    _broadcastSync();
  }

  /// `mouseLeaveChart`; the pointer has also left any item.
  void _mouseLeave() {
    if (!mounted) return;
    _hover = _hover.inactive();
    _itemHover = _itemHover.inactive();
    _hoveredItem = null;
    _refreshView();
    _broadcastSync();
  }

  /// A Bar's onMouseEnter / onMouseLeave (tooltipContext.tsx), fired when the
  /// element under the pointer changes.
  void _setItemHover(_ItemHit? hit) {
    if (hit == _hoveredItem || !mounted) return;
    _hoveredItem = hit;
    if (hit == null) {
      // mouseLeaveItem
      _itemHover = _itemHover.inactive();
    } else {
      // setActiveMouseOverItemIndex
      _itemHover = _itemInteraction(hit);
      _sync = const _Interaction();
      _keyboard = _keyboard.inactive();
    }
    _refreshView();
    _broadcastSync();
  }

  _Interaction _itemInteraction(_ItemHit hit) => _Interaction(
      active: true, index: hit.index, coordinate: hit.tooltipPosition, dataKey: hit.dataKey, itemId: hit.id);

  /// The topmost bar element under [p] as the browser hit tests the SVG: the
  /// activeBar layer (z 1000), the bars (300), then backgrounds (-50), each
  /// in reverse paint order. Only bars dispatch item events; Line does not.
  _ItemHit? _itemAt(Offset p) {
    final m = _model, frame = _frame;
    if (m == null || frame == null) return null;
    final h = _view.value;
    for (final f in m.funnels.reversed) {
      if (f.settings.hide) continue;
      for (final t in (currentTrapezoids(frame, f) ?? const <FunnelTrapezoid>[]).reversed) {
        if (!trapezoidVisible(t)) continue;
        if (trapezoidPath(t.x, t.y, t.upperWidth, t.lowerWidth, t.height).contains(p)) {
          final target = f.trapezoids.where((x) => x.index == t.index).firstOrNull ?? t;
          return (id: f.id, dataKey: f.settings.dataKey, index: t.index, tooltipPosition: target.tooltipPosition, background: false);
        }
      }
    }
    final bars = [
      for (final s in m.series)
        if (s.item.element case final Bar bar when !s.item.hide) (s, bar),
    ].reversed;
    // The entry's tooltipPosition belongs to the target rectangle, not the animated one.
    _ItemHit hit(SeriesModel s, BarRect r, {bool background = false}) => (
          id: s.item.id,
          dataKey: s.item.dataKey,
          index: r.originalDataIndex,
          tooltipPosition:
              (s.rects?.where((t) => t.originalDataIndex == r.originalDataIndex).firstOrNull ?? r).tooltipPosition,
          background: background,
        );
    for (final layer in [true, false]) {
      // Scatter symbols: active ones (z 1200) over the activeBar layer, the rest (600) over bars.
      if (_scatterAt(m, frame, h, p, active: layer) case final hit?) return hit;
      for (final (s, bar) in bars) {
        for (final r in (currentBarRects(frame, s) ?? const <BarRect>[]).reversed) {
          if (inActiveBarLayer(h, s.item, bar, r) != layer) continue;
          if (r.width == 0 || r.height == 0) continue;
          if (barPath(bar, r, activeBarStyle(h, bar, r)).contains(p)) return hit(s, r);
        }
      }
    }
    for (final (s, bar) in bars) {
      if (bar.background == false) continue;
      for (final r in (s.rects ?? const <BarRect>[]).reversed) {
        final b = r.background;
        if (b != null && b.width != 0 && b.height != 0 && b.contains(p)) return hit(s, r, background: true);
      }
    }
    return null;
  }

  /// The topmost scatter symbol under [p], among the active points or the others.
  _ItemHit? _scatterAt(CartesianModel m, ChartFrame frame, HoverState h, Offset p, {required bool active}) {
    for (final s in m.series.reversed) {
      final scatter = s.item.element;
      if (scatter is! Scatter || s.item.hide) continue;
      final points = currentScatterPoints(frame, s) ?? const <ScatterPoint>[];
      for (var i = points.length - 1; i >= 0; i--) {
        if (isActiveScatterPoint(h, scatter, i) != active) continue;
        final position = points[i].tooltipPosition;
        if (position == null || !(scatterSymbolPath(scatter, points[i], active: active)?.contains(p) ?? false)) {
          continue;
        }
        return (id: s.item.id, dataKey: scatter.dataKey, index: i, tooltipPosition: position, background: false);
      }
    }
    return null;
  }

  /// The wrapper's onClick: `mouseClickAction` -> `setMouseClickAxisIndex`,
  /// after the clicked bar's own onClick (`setActiveClickItemIndex`).
  void _chartClick(Offset local, _ItemHit? item) {
    final m = _model;
    if (m == null) return;
    if (item != null && _isItemEventType(m)) {
      _itemClick = _itemInteraction(item);
      _sync = const _Interaction();
      _keyboard = _keyboard.inactive();
    }
    final props = activePropsFromPointer(m, local);
    if (props != null) {
      _click = _Interaction(active: true, index: props.activeIndex, coordinate: props.activeCoordinate);
      _sync = const _Interaction();
      _keyboard = _keyboard.inactive();
    }
    if (item != null || props != null) {
      _refreshView();
      _broadcastSync();
    }
  }

  void _broadcastSync() {
    final id = _registeredSyncId;
    final m = _model;
    if (id == null || m == null || m.tooltipSettings == null) return;
    final v = _view.value;
    for (final other in syncPeers(id, this)) {
      other.receiveTooltipSync(v.active, v.activeIndex, v.coordinate, v.activeDataKey, m.viewBox, null);
    }
  }

  @override
  void receiveTooltipSync(
      bool active, int? index, Offset? coordinate, Object? dataKey, Rect sourceViewBox, PolarCoordinate? polar) {
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
      _sync = _Interaction(active: true, index: index, coordinate: scaled, dataKey: dataKey);
    }
    _refreshView();
  }

  /// Touch with the 'item' event type: touchEventsMiddleware finds no item
  /// under a moving finger (bars carry no data-item attributes), so only a
  /// tap's emulated mouse events reach the bars.
  bool _touchIgnoredByItems(PointerEvent e) =>
      (e.kind == PointerDeviceKind.touch || e.kind == PointerDeviceKind.stylus) &&
      _model != null &&
      _isItemEventType(_model!);

  void _onPointerDown(PointerDownEvent e) {
    _downPosition = e.localPosition;
    _downItem = _itemAt(e.localPosition);
    final touch = e.kind == PointerDeviceKind.touch || e.kind == PointerDeviceKind.stylus;
    if (!touch) _focusFromPointer(e.localPosition);
    // Touch: the first touchmove (or the tap's emulated mousemove) shows the tooltip.
    if (!_touchIgnoredByItems(e)) _setHoverFromPointer(e.localPosition, leaveWhenOutside: !touch);
  }

  void _onPointerMove(PointerMoveEvent e) {
    final touch = e.kind == PointerDeviceKind.touch || e.kind == PointerDeviceKind.stylus;
    if (!_touchIgnoredByItems(e)) _setHoverFromPointer(e.localPosition, leaveWhenOutside: !touch);
    if (!touch) widget.onMouseMove?.call(_eventState(), e);
  }

  void _onPointerUp(PointerUpEvent e) {
    final down = _downPosition;
    _downPosition = null;
    if (down == null) return;
    final touch = e.kind == PointerDeviceKind.touch || e.kind == PointerDeviceKind.stylus;
    if (touch && (e.localPosition - down).distance > kTouchSlop) return;
    final item = _itemAt(e.localPosition);
    if (touch) {
      // The tap's emulated mouseover reaches the item under the finger.
      if (_touchIgnoredByItems(e)) _setItemHover(item);
      _focusFromPointer(e.localPosition);
    }
    // A click targets the common ancestor of the mousedown and mouseup targets.
    _chartClick(e.localPosition, touch || item == _downItem ? item : null);
    widget.onClick?.call(_eventState(), e);
  }

  // -------------------------------------------------------------- animation

  void _syncAnimators(CartesianModel m, bool reducedMotion) {
    final live = <String>{};
    final liveErrorBars = <String>{};
    for (final s in m.series) {
      final el = s.item.element;
      final id = s.item.id;
      live.add(id);
      final active = el.isAnimationActive ?? !reducedMotion;
      for (var b = 0; b < s.errorBars.length; b++) {
        final (bar, lines) = s.errorBars[b];
        final key = errorBarAnimationKey(s.item, b);
        liveErrorBars.add(key);
        _errorBarAnimations.putIfAbsent(key, () => ErrorBarAnimation(this)).update({for (final l in lines) l.key},
            active: bar.isAnimationActive,
            begin: bar.animationBegin,
            duration: bar.animationDuration,
            easing: bar.animationEasing);
      }
      if (s.item.isScatter) {
        _scatterAnimators.putIfAbsent(id, () => SeriesAnimator<ScatterPoint>(this, matchBy: MatchBy.append)).update(
            s.item.hide ? null : s.scatterPoints,
            active: active,
            begin: el.animationBegin,
            duration: el.animationDuration,
            easing: el.animationEasing,
            onAnimationStart: el.onAnimationStart,
            onAnimationEnd: el.onAnimationEnd);
      } else if (s.item.isBar) {
        final a = _barAnimators.putIfAbsent(id, () => SeriesAnimator<BarRect>(this, matchBy: MatchBy.append));
        a.update(s.item.hide ? null : s.rects,
            active: active,
            begin: el.animationBegin,
            duration: el.animationDuration,
            easing: el.animationEasing,
            onAnimationStart: el.onAnimationStart,
            onAnimationEnd: el.onAnimationEnd);
      } else if (s.item.isArea) {
        final a = _lineAnimators.putIfAbsent(id, () => SeriesAnimator<LinePoint>(this, matchBy: MatchBy.byIndex));
        final hidden = s.item.hide || s.points == null;
        final restarted = a.update(hidden ? null : s.points,
            active: active,
            begin: el.animationBegin,
            duration: el.animationDuration,
            easing: el.animationEasing,
            onAnimationStart: el.onAnimationStart,
            onAnimationEnd: el.onAnimationEnd,
            key: s.baseLine);
        // A hidden Area unmounts, dropping its baseline ref with it.
        if (hidden) _areaBaseLines.remove(id);
        // A fresh one starts like the refs of a newly mounted Area.
        if (restarted && !hidden) {
          if (_areaBaseLines[id] case final b?) {
            b.restart();
          } else {
            _areaBaseLines[id] = AreaBaseLineAnimation();
          }
        }
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
    final liveFunnels = <String>{};
    for (final f in m.funnels) {
      final el = f.settings;
      liveFunnels.add(f.id);
      _funnelAnimators
          .putIfAbsent(f.id, () => SeriesAnimator<FunnelTrapezoid>(this, matchBy: MatchBy.append))
          .update(el.hide || f.trapezoids.isEmpty ? null : f.trapezoids,
              active: el.isAnimationActive ?? !reducedMotion,
              begin: el.animationBegin,
              duration: el.animationDuration,
              easing: el.animationEasing,
              onAnimationStart: el.onAnimationStart,
              onAnimationEnd: el.onAnimationEnd);
    }
    for (final id in _funnelAnimators.keys.where((k) => !liveFunnels.contains(k)).toList()) {
      _funnelAnimators.remove(id)!.dispose();
    }
    for (final id in _barAnimators.keys.where((k) => !live.contains(k)).toList()) {
      _barAnimators.remove(id)!.dispose();
    }
    for (final id in _lineAnimators.keys.where((k) => !live.contains(k)).toList()) {
      _lineAnimators.remove(id)!.dispose();
      _lineLengths.remove(id);
      _areaBaseLines.remove(id);
    }
    for (final id in _scatterAnimators.keys.where((k) => !live.contains(k)).toList()) {
      _scatterAnimators.remove(id)!.dispose();
    }
    for (final key in _errorBarAnimations.keys.where((k) => !liveErrorBars.contains(k)).toList()) {
      _errorBarAnimations.remove(key)!.dispose();
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

    // replaceYAxis: changed settings start over from 'auto'.
    _yAxisWidths.removeWhere((_, w) => !children.any((c) => identical(c, w.settings)));
    CartesianModel compute() => computeCartesianModel(
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
      yAxisWidths: {for (final e in _yAxisWidths.entries) if (e.value.width != null) e.key: e.value.width!},
      baseValue: widget.baseValue,
    );
    var m = compute();
    // YAxisImpl's layout effect measures and dispatches updateYAxisWidth until
    // the width settles, all before the browser paints.
    // ponytail: capped at 10 passes; React gives up after 50 nested updates.
    for (var pass = 0; pass < 10 && _updateAutoYAxisWidths(m, tickStyle, textStyle, scaler); pass++) {
      m = compute();
    }
    _model = m;
    _syncAnimators(m, reducedMotion);
    // Everything that reads the view is rebuilt below, so no notification.
    _view.set(_computeView(m), notify: false);

    final frame = _frame = ChartFrame(
      model: m,
      children: children,
      textStyle: textStyle,
      textScaler: scaler,
      barAnimators: _barAnimators,
      lineAnimators: _lineAnimators,
      lineLengths: _lineLengths,
      areaBaseLines: _areaBaseLines,
      funnelAnimators: _funnelAnimators,
      scatterAnimators: _scatterAnimators,
      errorBarAnimations: _errorBarAnimations,
    );
    final animations = Listenable.merge([
      for (final a in _barAnimators.values) a.controller,
      for (final a in _lineAnimators.values) a.controller,
      for (final a in _funnelAnimators.values) a.controller,
      for (final a in _scatterAnimators.values) a.controller,
      for (final a in _errorBarAnimations.values) a.controller,
    ]);
    // Bars move between the main and activeBar layers as the tooltip moves.
    final hasActiveBar = m.series.any((s) => s.item.element is Bar && (s.item.element as Bar).activeBar != false);
    // So do funnel trapezoids and scatter points with an activeShape, between main and overlay.
    final hasActiveShape = m.funnels.any((f) => f.settings.activeShape != null) ||
        m.series.any((s) {
          final el = s.item.element;
          return el is Scatter && el.activeShape != null && el.activeShape != false;
        });
    final animationsAndView = Listenable.merge([animations, _view]);

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
        layer(ChartLayer.main, repaint: hasActiveBar || hasActiveShape ? animationsAndView : animations),
        if (hasActiveBar) layer(ChartLayer.activeBar, repaint: animationsAndView),
        // Active scatter points animate there.
        layer(ChartLayer.overlay, repaint: _scatterAnimators.isEmpty ? _view : animationsAndView),
        // Repaints when a series finishes animating and its LabelLists appear.
        layer(ChartLayer.labels, repaint: animations),
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
          if (e.kind == PointerDeviceKind.touch && (_hover.active || _itemHover.active)) _mouseLeave();
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

  /// Returns whether any `YAxis(width: 'auto')` changed width.
  bool _updateAutoYAxisWidths(
      CartesianModel m, TextStyle Function(CartesianAxisElement) tickStyle, TextStyle textStyle, TextScaler scaler) {
    var changed = false;
    for (final a in m.axes) {
      final s = a.settings;
      // No measuring for a label drawn by a function.
      if (s is! YAxis || s.width != 'auto' || s.label is Function) continue;
      final calculated =
          getCalculatedYAxisWidth(a, tickStyle: tickStyle(s), baseStyle: textStyle, scaler: scaler);
      if (jsRound(a.rect.width) != jsRound(calculated)) {
        changed = _yAxisWidths.putIfAbsent(s.id, () => AutoYAxisWidth(s)).update(calculated) || changed;
      }
    }
    return changed;
  }

  Widget _buildLegend(Legend legend, LegendLayout? layout, Size size, TextScaler scaler) => legendLayer(legend,
      layout: layout,
      payload: layout != null ? const [] : legendPayloadOf(collectItems(widget.children), legend),
      chartSize: size,
      margin: widget.margin,
      scaler: scaler,
      customSize: _customLegendSize,
      onCustomSize: (s) {
        if (mounted && s != _customLegendSize) setState(() => _customLegendSize = s);
      });

  Widget _buildTooltip(Tooltip tooltip, CartesianModel m, bool reducedMotion) => ListenableBuilder(
        listenable: _view,
        builder: (context, _) {
          final v = _view.value;
          return tooltipLayer(tooltip,
              vsync: this,
              reducedMotion: reducedMotion,
              viewBox: m.viewBox,
              active: v.active,
              payload: v.payload,
              label: v.itemEventType ? null : v.label,
              coordinate: v.coordinate,
              activeIndex: v.activeIndex);
        },
      );
}
