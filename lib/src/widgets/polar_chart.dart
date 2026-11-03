// PieChart: src/chart/PieChart.tsx and PolarChart.tsx (defaultPolarChartProps),
// rendered like CartesianChart's wrapper. The tooltip is the 'item' event
// type, the only one PieChart validates: sectors dispatch item hover and
// click (tooltipContext.tsx), picked by hit testing what is painted under the
// pointer, and the state follows tooltipSlice.ts,
// combineTooltipInteractionState.ts, combineTooltipPayloadConfigurations.ts
// and combineActiveTooltipIndex.ts. Focus and arrow keys follow
// keyboardEventsMiddleware.ts; Tab visits the svg, then each Pie whose
// `rootTabIndex` is not negative. `syncId` shares the tooltip index with the
// other polar charts of the group (syncMethod 'index').

import 'package:flutter/gestures.dart' show kTouchSlop, PointerDeviceKind;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show HardwareKeyboard, KeyDownEvent, KeyRepeatEvent, LogicalKeyboardKey;
import 'package:flutter/widgets.dart';

import '../animation.dart';
import '../components.dart';
import '../util.dart' show defaultIndexIsFractional, defaultPayloadIndex;
import '../engine/pie.dart';
import '../engine/polar_axis.dart';
import '../engine/polar_items.dart';
import '../engine/polar_scene.dart';
import '../polar_axes.dart';
import '../polar_components.dart';
import '../render/polar_painter.dart';
import '../render/polar_scene_painter.dart';
import '../render/sector.dart';
import '../render/svg_text.dart';
import 'legend.dart';
import 'responsive_container.dart';
import 'sync_registry.dart';
import 'tooltip.dart';

/// Shared props of the polar charts (`PolarChartProps` with
/// `defaultPolarChartProps`). [cx], [cy], [innerRadius] and [outerRadius] are
/// numbers or percent strings and place the polar axes; Pies carry their own.
abstract class PolarChart extends StatefulWidget {
  const PolarChart({
    super.key,
    this.width,
    this.height,
    this.data = const [],
    this.margin = const Margin.all(5),
    this.cx = '50%',
    this.cy = '50%',
    this.innerRadius = 0,
    this.outerRadius = '80%',
    required this.startAngle,
    required this.endAngle,
    this.layout = PolarLayout.radial,
    this.stackOffset = StackOffset.none,
    this.reverseStackOrder = false,
    this.barCategoryGap = '10%',
    this.barGap = 4,
    this.barSize,
    this.maxBarSize,
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
  final Margin margin;
  final Object cx, cy, innerRadius, outerRadius;
  final double startAngle, endAngle;

  /// `layout`: 'centric' puts the category on the angle axis, 'radial' on the radius axis.
  final PolarLayout layout;
  final StackOffset stackOffset;
  final bool reverseStackOrder;

  /// RadialBar sizing, like the BarChart props (percent `barSize` is not supported).
  final Object barCategoryGap, barGap;
  final Object? barSize;
  final double? maxBarSize;

  /// Polar charts with the same id share the active tooltip index.
  final Object? syncId;

  /// When false, focusing the chart no longer shows the tooltip at index 0 and
  /// arrow keys no longer move it.
  final bool accessibilityLayer;
  final ChartEventHandler? onClick;
  final ChartEventHandler? onMouseEnter;
  final ChartEventHandler? onMouseMove;
  final ChartEventHandler? onMouseLeave;
  final List<RechartsElement> children;

  String get chartName;

  /// `defaultTooltipEventType`.
  String get defaultTooltipEventType => 'item';

  /// `validateTooltipEventTypes`.
  List<String> get allowedTooltipTypes => const ['item'];

  /// Whether the chart builds the polar axes and items of [PolarScene].
  bool get usesPolarScene => false;

  @override
  State<PolarChart> createState() => _PolarChartState();
}

/// src/chart/PieChart.tsx.
class PieChart extends PolarChart {
  const PieChart({
    super.key,
    super.width,
    super.height,
    super.data,
    super.margin,
    super.cx,
    super.cy,
    super.innerRadius,
    super.outerRadius,
    super.startAngle = 0,
    super.endAngle = 360,
    super.syncId,
    super.accessibilityLayer,
    super.onClick,
    super.onMouseEnter,
    super.onMouseMove,
    super.onMouseLeave,
    super.children,
  });
  @override
  String get chartName => 'PieChart';
}

/// `TooltipInteractionState`.
class _Interaction {
  const _Interaction({this.active = false, this.index, this.coordinate, this.dataKey, this.itemId, this.polar, this.desired});
  final bool active;

  /// `Number(defaultIndex)` when the state comes from `Tooltip.defaultIndex`.
  final double? desired;
  final int? index;
  final Offset? coordinate;
  final Object? dataKey;

  /// `graphicalItemId`.
  final String? itemId;

  /// The axis tooltip's coordinate with its polar parts.
  final PolarCoordinate? polar;
  _Interaction inactive() =>
      _Interaction(index: index, coordinate: coordinate, dataKey: dataKey, itemId: itemId, polar: polar);
  _Interaction activate() =>
      _Interaction(active: true, index: index, coordinate: coordinate, dataKey: dataKey, itemId: itemId, polar: polar);
}

/// The sector under the pointer.
typedef _SectorHit = ({String id, Object dataKey, int index, Offset? tooltipPosition});

/// Everything the tooltip and the sectors render from the tooltip state.
class _PolarView extends PolarHoverState {
  const _PolarView({
    super.activeIndex,
    super.activeDataKey,
    super.activeItemId,
    super.polarCoordinate,
    super.cursorVisible,
    super.activeDataPoints,
    this.active = false,
    this.coordinate,
    this.payload = const [],
    this.interactionActive = false,
    this.label,
  });
  final bool active;
  final Offset? coordinate;
  final List<TooltipPayloadEntry> payload;
  final bool interactionActive;

  /// The axis tooltip's label (`selectActiveLabel`).
  final Object? label;
}

class _ViewNotifier extends ChangeNotifier implements ValueListenable<_PolarView> {
  _PolarView _value = const _PolarView();
  @override
  _PolarView get value => _value;
  void set(_PolarView v, {bool notify = true}) {
    _value = v;
    if (notify) notifyListeners();
  }
}

class _PolarChartState extends State<PolarChart> with TickerProviderStateMixin implements TooltipSyncPeer {
  final Map<String, SeriesAnimator<PieSector>> _pieAnimators = {};
  final Map<String, SeriesAnimator<RadarPoint>> _radarAnimators = {}, _radarBaseLineAnimators = {};
  final Map<String, SeriesAnimator<RadialBarSector>> _radialBarAnimators = {};
  final _ViewNotifier _view = _ViewNotifier();

  _Interaction _itemHover = const _Interaction();
  _Interaction _itemClick = const _Interaction();
  _Interaction _axisHover = const _Interaction();
  _Interaction _axisClick = const _Interaction();
  _Interaction _sync = const _Interaction();
  _Interaction _keyboard = const _Interaction();
  _SectorHit? _hoveredItem;
  _SectorHit? _downItem;

  /// The sector and Radar under the pointer for the user's enter / leave handlers.
  _SectorHit? _eventItem;
  String? _eventRadar;
  final FocusNode _focusNode = FocusNode(debugLabel: 'recharts polar chart');

  /// What has DOM focus inside the chart: the svg (-1) or the group of the
  /// Pie at that index; null when the chart is not focused.
  int? _focusTarget;
  PolarModel? _model;
  PolarFrame? _frame;
  Size? _customLegendSize;
  Offset? _downPosition;
  Object? _registeredSyncId;
  int _dataStart = 0;
  int? _dataEnd;

  @override
  void initState() {
    super.initState();
    PaintingBinding.instance.systemFonts.addListener(_onFontsChanged);
    _focusNode.addListener(_onFocusChange);
  }

  void _onFontsChanged() {
    clearTextCache();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_onFontsChanged);
    _unregisterSync();
    _focusNode.dispose();
    for (final a in [
      ..._pieAnimators.values,
      ..._radarAnimators.values,
      ..._radarBaseLineAnimators.values,
      ..._radialBarAnimators.values,
    ]) {
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

  // -------------------------------------------------------------- tooltip state

  /// `combineTooltipEventType`.
  bool _isAxisEvent(PolarModel m) {
    final shared = m.tooltipSettings?.shared;
    final defaultType = widget.defaultTooltipEventType;
    final type = shared == null ? defaultType : (shared ? 'axis' : 'item');
    return (widget.allowedTooltipTypes.contains(type) ? type : defaultType) == 'axis' && m.scene != null;
  }

  _Interaction _interactionState(PolarModel m) {
    final tooltip = m.tooltipSettings;
    final click = tooltip?.trigger == TooltipTrigger.click;
    final mouse = _isAxisEvent(m) ? (click ? _axisClick : _axisHover) : (click ? _itemClick : _itemHover);
    if (mouse.active) return mouse;
    if (_keyboard.active) return _keyboard;
    if (_sync.active && _sync.index != null) return _sync;
    if (mouse.index != null) {
      if (tooltip?.active == true) return mouse.activate();
    } else if (tooltip?.defaultIndex != null) {
      final desired = tooltip!.defaultIndexNumber;
      return _Interaction(active: true, index: defaultPayloadIndex(desired), desired: desired);
    }
    return _Interaction(coordinate: mouse.coordinate, polar: mouse.polar);
  }

  /// `combineActiveTooltipIndex`: clamped into the tooltip data.
  int? _activeIndex(PolarModel m, int? index) {
    if (index == null) return null;
    final scene = m.scene;
    if (scene != null) return combinePolarActiveIndex(scene, m.chartData, index);
    final length = m.tooltipDisplayedData.length;
    return length > 0 ? index.clamp(0, length - 1) : (index < 0 ? 0 : index);
  }

  /// The tooltip entries in registration order: one per Pie, Radar and RadialBar.
  List<({String id, List<TooltipPayloadEntry> Function(int index) entries})> _payloadSources(PolarModel m) {
    final scene = m.scene;
    // Children pair with models by position: equal `const` elements are one object.
    var pies = 0, radars = 0, bars = 0;
    return [
      for (final c in widget.children)
        if (c is Pie)
          ...() {
            final p = m.pies[pies++];
            return p.settings.hide || p.sectors == null
                ? const <({String id, List<TooltipPayloadEntry> Function(int index) entries})>[]
                : [(id: p.id, entries: (int i) => pieTooltipPayload(m, [p], i))];
          }()
        else if (c is Radar && scene != null)
          ...() {
            final r = scene.radars[radars++];
            return [(id: r.id, entries: (int i) => polarTooltipPayload(scene, m.chartData, i, ids: {r.id}, axis: false))];
          }()
        else if (c is RadialBar && scene != null)
          ...() {
            final b = scene.radialBars[bars++];
            return [(id: b.id, entries: (int i) => polarTooltipPayload(scene, m.chartData, i, ids: {b.id}, axis: false))];
          }(),
    ];
  }

  /// `combineTooltipPayloadConfigurations` for the 'item' event type.
  List<TooltipPayloadEntry> _itemPayload(PolarModel m, int? index) {
    if (index == null) return const [];
    final sources = _payloadSources(m);
    if (sources.isEmpty) return const [];
    final id = (m.tooltipSettings?.trigger == TooltipTrigger.click ? _itemClick : _itemHover).itemId;
    final Iterable<({String id, List<TooltipPayloadEntry> Function(int index) entries})> chosen;
    if (_sync.active && id == null) {
      chosen = sources;
    } else if (id == null && (m.tooltipSettings?.defaultIndex != null || _keyboard.active)) {
      chosen = [sources.first];
    } else {
      chosen = sources.where((s) => s.id == id);
    }
    return [for (final s in chosen) ...s.entries(index)];
  }

  /// `combineCoordinateForDefaultIndex`.
  Offset? _coordinateForIndex(PolarModel m, int i) {
    final scene = m.scene;
    final firstId = _payloadSources(m).firstOrNull?.id;
    final firstIsPie = m.pies.any((p) => p.id == firstId);
    if (scene != null && (_isAxisEvent(m) || !firstIsPie)) {
      // The first item's `getPosition` is a noop for Radar and RadialBar; the tick decides.
      final ticks = scene.tooltipTicks;
      if (i < 0 || i >= ticks.length) return null;
      return Offset((m.offset.left + m.size.width) / 2, ticks[i].coordinate);
    }
    final first = _payloadSources(m).firstOrNull;
    final pie = m.pies.where((p) => p.id == first?.id).firstOrNull ?? m.pies.where((p) => p.sectors != null).firstOrNull;
    final sectors = pie?.sectors;
    return sectors != null && i >= 0 && i < sectors.length ? sectors[i].tooltipPosition : null;
  }

  _PolarView _computeView(PolarModel m) {
    final tooltip = m.tooltipSettings;
    final state = _interactionState(m);
    final activeIndex = _activeIndex(m, state.index);
    final finalIsActive = tooltip?.active ?? (state.active && activeIndex != null);
    final axis = _isAxisEvent(m);
    var coordinate = state.coordinate;
    final desired = state.desired ?? tooltip?.defaultIndexNumber;
    final fractional = state.desired != null &&
        defaultIndexIsFractional(state.desired, m.scene != null ? m.chartData.length : m.tooltipDisplayedData.length);
    if (coordinate == null && desired != null && desired.isFinite && desired == desired.truncateToDouble()) {
      coordinate = _coordinateForIndex(m, desired.toInt());
    }
    final all = axis
        ? polarTooltipPayload(m.scene!, m.chartData, activeIndex)
        : _itemPayload(m, activeIndex);
    var payload = finalIsActive ? all : const <TooltipPayloadEntry>[];
    if (tooltip?.filterNull ?? true) {
      payload = [
        for (final e in payload)
          if (e.value != null && (!e.hide || (tooltip?.includeHidden ?? false))) e,
      ];
    }
    return _PolarView(
      activeIndex: fractional ? null : activeIndex,
      activeDataKey: state.dataKey,
      activeItemId: state.itemId,
      polarCoordinate: axis ? state.polar : null,
      // Cursor.tsx renders nothing for the 'item' event type.
      cursorVisible: tooltip != null && finalIsActive && axis && !fractional,
      activeDataPoints: [for (final p in all) ?p.payload],
      active: finalIsActive,
      coordinate: coordinate,
      payload: payload,
      interactionActive: state.active,
      label: axis && !fractional ? polarActiveLabel(m.scene!, activeIndex) : null,
    );
  }

  void _refreshView() {
    final m = _model;
    if (m == null) return;
    _view.set(_computeView(m));
  }

  ChartEventState _eventState() {
    final v = _view.value;
    return ChartEventState(
      activeCoordinate: v.coordinate,
      activeDataKey: v.activeDataKey,
      activeIndex: v.activeIndex,
      activeTooltipIndex: v.activeIndex,
      isTooltipActive: v.interactionActive,
    );
  }

  // -------------------------------------------------------------- keyboard

  void _setFocusTarget(int? target) {
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
      _setFocusTarget(-1);
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
    final m = _model;
    if (key == LogicalKeyboardKey.tab && m != null) {
      // Tab order: the svg, then the Pies' groups (`rootTabIndex`).
      final order = [-1, for (final (i, p) in m.pies.indexed) if (p.settings.rootTabIndex >= 0) i];
      final next = order.indexOf(_focusTarget ?? -1) + (HardwareKeyboard.instance.isShiftPressed ? -1 : 1);
      if (next < 0 || next >= order.length) return KeyEventResult.ignored;
      _setFocusTarget(order[next]);
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
    final currentIndex = _activeIndex(m, _keyboard.index) ?? -1;
    final displayed = m.tooltipDisplayedData;
    if (key == LogicalKeyboardKey.enter) {
      if (currentIndex < 0) return KeyEventResult.ignored;
      _keyboard = _Interaction(
          active: !_keyboard.active, index: _keyboard.index, coordinate: _coordinateForIndex(m, _keyboard.index!));
    } else {
      // Polar charts are 'left-to-right'.
      final movement = right ? 1 : -1;
      int nextIndex;
      if (currentIndex < 0) {
        if (displayed.isEmpty) return KeyEventResult.ignored;
        nextIndex = movement > 0 ? 0 : displayed.length - 1;
      } else {
        nextIndex = currentIndex + movement;
        if (displayed.isEmpty || nextIndex >= displayed.length || nextIndex < 0) return KeyEventResult.ignored;
      }
      _keyboard = _Interaction(active: true, index: nextIndex, coordinate: _coordinateForIndex(m, nextIndex));
    }
    _refreshView();
    _broadcastSync();
    return KeyEventResult.ignored;
  }

  void _focusFromPointer() {
    _setFocusTarget(_focusTarget ?? -1);
    _focusNode.requestFocus();
  }

  // -------------------------------------------------------------- input

  /// The topmost sector under [p], in paint order reversed.
  _SectorHit? _sectorAt(Offset p) {
    final m = _model, frame = _frame;
    if (m == null || frame == null) return null;
    // Labels are painted above the sectors.
    if (frame.labelBoxes.any((r) => r.contains(p))) return null;
    final h = _view.value;
    final scene = m.scene;
    // RadialBars (bar, 300) paint above Pies (area, 100).
    for (final bar in (scene?.radialBars ?? const <RadialBarModel>[]).reversed) {
      if (bar.settings.hide) continue;
      final sectors = currentRadialBarSectors(frame, bar);
      for (var i = sectors.length - 1; i >= 0; i--) {
        final s = sectors[i], b = bar.settings;
        final option = isActiveRadialBarSector(b, h, i) ? b.activeShape : b.shape;
        // A custom painter's shape is unknown: the default sector stands in.
        final path = radialBarPath(b, s, option);
        if (path == null) continue;
        final style = option is SectorStyle ? option : null;
        final stroke = style?.stroke ?? s.stroke;
        if (path.contains(p) || (stroke != null && strokeContains(path, p, style?.strokeWidth ?? s.strokeWidth ?? 1))) {
          return (id: bar.id, dataKey: b.dataKey, index: i, tooltipPosition: null);
        }
      }
    }
    for (final pie in m.pies.reversed) {
      if (pie.settings.hide || pie.sectors == null) continue;
      final sectors = currentPieSectors(frame, pie) ?? const <PieSector>[];
      for (var i = sectors.length - 1; i >= 0; i--) {
        if (!rendersSector(sectors, i)) continue;
        final s = sectors[i], option = sectorOption(h, pie, i);
        final style = option is SectorStyle ? option : null;
        // A custom painter's shape is unknown: the default sector stands in.
        final path = piePath(s, option);
        if (path == null) continue;
        final stroke = style?.stroke ?? s.stroke;
        if (path.contains(p) || (stroke != null && strokeContains(path, p, style?.strokeWidth ?? s.strokeWidth ?? 1))) {
          return (id: pie.id, dataKey: pie.settings.dataKey, index: i, tooltipPosition: sectors[i].tooltipPosition);
        }
      }
    }
    return null;
  }

  /// A sector's onMouseEnter / onMouseLeave, fired when the sector under the pointer changes.
  void _setItemHover(_SectorHit? hit) {
    if (hit == _hoveredItem || !mounted) return;
    _hoveredItem = hit;
    if (hit == null) {
      _itemHover = _itemHover.inactive();
    } else {
      _itemHover = _itemInteraction(hit);
      _sync = const _Interaction();
      _keyboard = _keyboard.inactive();
    }
    _refreshView();
    _broadcastSync();
  }

  _Interaction _itemInteraction(_SectorHit hit) => _Interaction(
      active: true, index: hit.index, coordinate: hit.tooltipPosition, dataKey: hit.dataKey, itemId: hit.id);

  /// `mouseMoveMiddleware` for the axis event type: the pointer maps to a
  /// tick index inside the polar view box, else the tooltip hides.
  void _setAxisHover(Offset p, {bool leaveWhenOutside = true}) {
    final m = _model;
    final scene = m?.scene;
    if (m == null || scene == null || !mounted) return;
    final props = polarActivePropsFromPointer(scene, p);
    if (props == null) {
      // touchEventsMiddleware never dispatches a leave; only the mouse path does.
      if (leaveWhenOutside) _mouseLeaveChart();
      return;
    }
    _axisHover = _Interaction(active: true, index: props.activeIndex, coordinate: props.coordinate.offset, polar: props.coordinate);
    _sync = const _Interaction();
    _keyboard = _keyboard.inactive();
    _refreshView();
    _broadcastSync();
  }

  /// The pointer entered or moved: the sector under it, or the axis index.
  void _pointerAt(Offset p) {
    final m = _model;
    if (m != null && _isAxisEvent(m)) {
      _setAxisHover(p);
    } else {
      _setItemHover(_sectorAt(p));
    }
  }

  RadialBar? _radialBarOf(String id) =>
      _model?.scene?.radialBars.where((b) => b.id == id).firstOrNull?.settings;

  String? _radarAt(Offset p) {
    final m = _model, frame = _frame;
    if (m?.scene == null || frame == null) return null;
    for (final r in m!.scene!.radars.reversed) {
      if (r.settings.hide || r.points == null) continue;
      final path = radarPolygonPath(frame, r);
      final stroke = r.settings.stroke;
      if (path != null &&
          ((r.settings.fill?.a != 0 && path.contains(p)) ||
              (stroke != null && strokeContains(path, p, r.settings.strokeWidth ?? 1)))) {
        return r.id;
      }
    }
    return null;
  }

  RadarEventProps _radarEventProps(String id) {
    final r = _model!.scene!.radars.firstWhere((r) => r.id == id);
    return RadarEventProps(
        radar: r.settings,
        points: r.points ?? const [],
        baseLinePoints: r.composed?.baseLinePoints ?? const [],
        isRange: r.composed?.isRange ?? false);
  }

  /// The user's onMouseEnter / onMouseLeave of RadialBar sectors and the Radar polygon,
  /// fired when what is under the pointer changes.
  void _dispatchEnterLeave(Offset? p, PointerEvent e) {
    final item = p == null ? null : _sectorAt(p);
    if (item != _eventItem) {
      final prev = _eventItem;
      _eventItem = item;
      if (prev != null) {
        final bar = _radialBarOf(prev.id);
        final sector = _model?.scene?.radialBars.where((b) => b.id == prev.id).firstOrNull?.sectors;
        if (bar != null && sector != null && prev.index < sector.length) {
          bar.onMouseLeave?.call(sector[prev.index], prev.index, e);
        }
      }
      if (item != null) {
        final bar = _radialBarOf(item.id);
        final sectors = _model?.scene?.radialBars.where((b) => b.id == item.id).firstOrNull?.sectors;
        if (bar != null && sectors != null && item.index < sectors.length) {
          bar.onMouseEnter?.call(sectors[item.index], item.index, e);
        }
      }
    }
    final radar = p == null ? null : _radarAt(p);
    if (radar != _eventRadar) {
      final prev = _eventRadar;
      _eventRadar = radar;
      if (prev != null) {
        _model?.scene?.radars.where((r) => r.id == prev).firstOrNull?.settings.onMouseLeave?.call(_radarEventProps(prev), e);
      }
      if (radar != null) {
        _model?.scene?.radars.where((r) => r.id == radar).firstOrNull?.settings.onMouseEnter?.call(_radarEventProps(radar), e);
      }
    }
  }

  /// A click's sector and Radar handlers.
  void _dispatchClick(Offset p, PointerEvent e, _SectorHit? item) {
    if (item != null) {
      final bars = _model?.scene?.radialBars.where((b) => b.id == item.id);
      final bar = bars?.firstOrNull;
      if (bar != null && item.index < bar.sectors.length) bar.settings.onClick?.call(bar.sectors[item.index], item.index, e);
    }
    final radar = _radarAt(p);
    if (radar != null) _model?.scene?.radars.where((r) => r.id == radar).firstOrNull?.settings.onClick?.call(e);
  }

  /// `mouseLeaveChart`: only the active flags clear.
  void _mouseLeaveChart() {
    _itemHover = _itemHover.inactive();
    _axisHover = _axisHover.inactive();
    _hoveredItem = null;
    _refreshView();
    _broadcastSync();
  }

  void _mouseLeave() {
    if (!mounted) return;
    _mouseLeaveChart();
  }

  void _broadcastSync() {
    final id = _registeredSyncId;
    final m = _model;
    if (id == null || m == null || m.tooltipSettings == null) return;
    final v = _view.value;
    for (final other in syncPeers(id, this)) {
      other.receiveTooltipSync(v.active, v.activeIndex, v.coordinate, v.activeDataKey, m.viewBox, v.polarCoordinate);
    }
  }

  /// useChartSynchronisation: a Brush elsewhere in the group moves this chart's data slice. Only RadialBar
  /// sectors and the tooltip data follow it; Radar points, the axes and the legend ignore it.
  @override
  void receiveBrushSync(({int startIndex, int endIndex}) range) {
    if (range.startIndex == _dataStart && range.endIndex == _dataEnd) return;
    setState(() {
      _dataStart = range.startIndex;
      _dataEnd = range.endIndex;
    });
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
      _sync = _Interaction(active: true, index: index, coordinate: scaled, dataKey: dataKey, polar: polar);
    }
    _refreshView();
  }

  void _onPointerDown(PointerDownEvent e) {
    _downPosition = e.localPosition;
    _downItem = _sectorAt(e.localPosition);
    if (e.kind == PointerDeviceKind.mouse) {
      _focusFromPointer();
      final m = _model;
      if (m == null || !_isAxisEvent(m)) _setItemHover(_downItem);
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    final down = _downPosition;
    _downPosition = null;
    if (down == null) return;
    final touch = e.kind != PointerDeviceKind.mouse;
    if (touch && (e.localPosition - down).distance > kTouchSlop) return;
    final item = _sectorAt(e.localPosition);
    final m = _model;
    if (touch) _dispatchEnterLeave(e.localPosition, e);
    if (item != null ? (touch || item == _downItem) : true) _dispatchClick(e.localPosition, e, item);
    if (m != null && _isAxisEvent(m)) {
      // mouseClickMiddleware: the pointer's axis index, when inside the view box.
      if (touch) {
        _setAxisHover(e.localPosition);
        _focusFromPointer();
      }
      final props = m.scene == null ? null : polarActivePropsFromPointer(m.scene!, e.localPosition);
      if (props != null) {
        _axisClick = _Interaction(active: true, index: props.activeIndex, coordinate: props.coordinate.offset, polar: props.coordinate);
        _sync = const _Interaction();
        _keyboard = _keyboard.inactive();
        _refreshView();
        _broadcastSync();
      }
      widget.onClick?.call(_eventState(), e);
      return;
    }
    if (touch) {
      // The tap's emulated mouse events reach the sector under the finger.
      _setItemHover(item);
      _focusFromPointer();
    }
    // A click targets the common ancestor of the mousedown and mouseup targets.
    if (item != null && (touch || item == _downItem)) {
      _itemClick = _itemInteraction(item);
      _sync = const _Interaction();
      _keyboard = _keyboard.inactive();
      _refreshView();
      _broadcastSync();
    }
    widget.onClick?.call(_eventState(), e);
  }

  // -------------------------------------------------------------- legend

  /// The legend payloads of every item (`SetPolarLegendPayload`), sorted by the Legend's `itemSorter`.
  List<LegendPayload> _legendPayload(PolarModel m, Legend legend) {
    final scene = m.scene;
    if (scene == null) return pieLegendPayload(m, legend);
    // Each item appends its payload in child render order.
    var radars = 0, bars = 0, pies = 0;
    return sortLegendPayload([
      for (final c in widget.children)
        if (c is Radar)
          radarLegendEntry(scene.radars[radars++].settings)
        else if (c is RadialBar)
          ...radialBarLegendPayload(scene.radialBars[bars++].settings, m.chartData)
        else if (c is Pie)
          ...pieLegendEntries(m.pies[pies++]),
    ], legend);
  }

  // -------------------------------------------------------------- animation

  void _syncAnimators(PolarModel m, bool reducedMotion) {
    final live = <String>{};
    for (final p in m.pies) {
      final pie = p.settings;
      live.add(p.id);
      final a = _pieAnimators.putIfAbsent(p.id, () => SeriesAnimator<PieSector>(this, matchBy: MatchBy.append));
      a.update(pie.hide ? null : p.sectors,
          active: pie.isAnimationActive ?? !reducedMotion,
          begin: pie.animationBegin,
          duration: pie.animationDuration,
          easing: pie.animationEasing,
          onAnimationStart: pie.onAnimationStart,
          onAnimationEnd: pie.onAnimationEnd);
    }
    for (final id in _pieAnimators.keys.where((k) => !live.contains(k)).toList()) {
      _pieAnimators.remove(id)!.dispose();
    }
    final scene = m.scene;
    final liveRadars = <String>{}, liveBars = <String>{};
    for (final r in scene?.radars ?? const <RadarModel>[]) {
      final radar = r.settings;
      liveRadars.add(r.id);
      final hidden = radar.hide || r.points == null;
      final active = radar.isAnimationActive ?? !reducedMotion;
      _radarAnimators.putIfAbsent(r.id, () => SeriesAnimator<RadarPoint>(this, matchBy: MatchBy.byIndex)).update(
          hidden ? null : r.points,
          active: active,
          begin: radar.animationBegin,
          duration: radar.animationDuration,
          easing: radar.animationEasing,
          onAnimationStart: radar.onAnimationStart,
          onAnimationEnd: radar.onAnimationEnd);
      // Radar's baseLine runs through its own snapshot on the same timeline.
      final range = r.composed?.isRange ?? false;
      _radarBaseLineAnimators
          .putIfAbsent(r.id, () => SeriesAnimator<RadarPoint>(this, matchBy: MatchBy.byIndex))
          .update(hidden || !range ? null : r.composed!.baseLinePoints,
              active: active, begin: radar.animationBegin, duration: radar.animationDuration, easing: radar.animationEasing);
    }
    for (final b in scene?.radialBars ?? const <RadialBarModel>[]) {
      final bar = b.settings;
      liveBars.add(b.id);
      _radialBarAnimators
          .putIfAbsent(b.id, () => SeriesAnimator<RadialBarSector>(this, matchBy: MatchBy.append))
          .update(bar.hide ? null : b.sectors,
              active: bar.isAnimationActive ?? !reducedMotion,
              begin: bar.animationBegin,
              duration: bar.animationDuration,
              easing: bar.animationEasing,
              onAnimationStart: bar.onAnimationStart,
              onAnimationEnd: bar.onAnimationEnd);
    }
    for (final id in _radarAnimators.keys.where((k) => !liveRadars.contains(k)).toList()) {
      _radarAnimators.remove(id)!.dispose();
      _radarBaseLineAnimators.remove(id)?.dispose();
    }
    for (final id in _radialBarAnimators.keys.where((k) => !liveBars.contains(k)).toList()) {
      _radialBarAnimators.remove(id)!.dispose();
    }
  }

  // -------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    _registerSync();
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
    final textStyle = DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    final reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final children = widget.children;
    final legend = children.whereType<Legend>().firstOrNull;

    PolarModel compute(Size legendSize) => computePolarModel(
        chartName: widget.chartName,
        size: size,
        data: widget.data,
        children: children,
        margin: widget.margin,
        legendSize: legendSize,
        layout: widget.layout,
        options: widget.usesPolarScene
            ? PolarOptions(
                cx: widget.cx,
                cy: widget.cy,
                innerRadius: widget.innerRadius,
                outerRadius: widget.outerRadius,
                startAngle: widget.startAngle,
                endAngle: widget.endAngle)
            : null,
        stackOffset: widget.stackOffset,
        reverseStackOrder: widget.reverseStackOrder,
        barGap: widget.barGap,
        barCategoryGap: widget.barCategoryGap,
        barSize: widget.barSize,
        maxBarSize: widget.maxBarSize,
        dataStartIndex: _dataStart,
        dataEndIndex: _dataEnd);

    // The legend payload does not depend on the offset.
    var m = compute(Size.zero);
    LegendLayout? legendLayout;
    List<LegendPayload> legendPayload = const [];
    if (legend != null) {
      legendPayload = _legendPayload(m, legend);
      if (legend.content == null) {
        legendLayout = computeLegendLayout(
            legend: legend,
            payload: legendPayload,
            chartSize: size,
            margin: widget.margin,
            baseStyle: textStyle,
            scaler: scaler);
      }
      m = compute(legendLayout?.size ?? _customLegendSize ?? Size.zero);
    }
    _model = m;
    _syncAnimators(m, reducedMotion);
    _view.set(_computeView(m), notify: false);

    final frame = _frame = PolarFrame(
        model: m,
        textStyle: textStyle,
        textScaler: scaler,
        pieAnimators: _pieAnimators,
        radarAnimators: _radarAnimators,
        radarBaseLineAnimators: _radarBaseLineAnimators,
        radialBarAnimators: _radialBarAnimators);
    final animations = Listenable.merge([
      for (final a in [
        ..._pieAnimators.values,
        ..._radarAnimators.values,
        ..._radarBaseLineAnimators.values,
        ..._radialBarAnimators.values,
      ])
        a.controller,
    ]);

    Widget layer(PolarLayer l, Listenable repaint) => Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(painter: PolarPainter(l, frame, hover: _view, repaint: repaint)),
          ),
        );

    final tooltip = m.tooltipSettings;
    final stack = Stack(
      clipBehavior: Clip.none,
      children: [
        layer(PolarLayer.main, Listenable.merge([animations, _view])),
        // Repaints when a Pie finishes animating and its labels appear.
        layer(PolarLayer.labels, animations),
        if (legend != null)
          legendLayer(legend,
              layout: legendLayout,
              payload: legendPayload,
              chartSize: size,
              margin: widget.margin,
              scaler: scaler,
              customSize: _customLegendSize,
              onCustomSize: (s) {
                if (mounted && s != _customLegendSize) setState(() => _customLegendSize = s);
              }),
        if (tooltip != null)
          Positioned.fill(
            child: IgnorePointer(
              child: ListenableBuilder(
                listenable: _view,
                builder: (context, _) {
                  final v = _view.value;
                  // The 'item' event type renders no label.
                  return tooltipLayer(tooltip,
                      vsync: this,
                      reducedMotion: reducedMotion,
                      viewBox: m.viewBox,
                      active: v.active,
                      payload: v.payload,
                      label: v.label,
                      coordinate: v.coordinate,
                      activeIndex: v.activeIndex);
                },
              ),
            ),
          ),
      ],
    );

    final content = TapRegion(
      onTapOutside: (e) {
        if (_focusNode.hasFocus) _focusNode.unfocus();
        _setFocusTarget(null);
        if (e.kind == PointerDeviceKind.touch && _itemHover.active) _mouseLeave();
      },
      child: MouseRegion(
        onEnter: (e) {
          _pointerAt(e.localPosition);
          _dispatchEnterLeave(e.localPosition, e);
          widget.onMouseEnter?.call(_eventState(), e);
        },
        onHover: (e) {
          _pointerAt(e.localPosition);
          _dispatchEnterLeave(e.localPosition, e);
          widget.onMouseMove?.call(_eventState(), e);
        },
        onExit: (e) {
          _dispatchEnterLeave(null, e);
          _mouseLeave();
          widget.onMouseLeave?.call(_eventState(), e);
        },
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onPointerDown,
          onPointerMove: (e) {
            final m = _model;
            if (e.kind == PointerDeviceKind.mouse) {
              _pointerAt(e.localPosition);
              _dispatchEnterLeave(e.localPosition, e);
              widget.onMouseMove?.call(_eventState(), e);
            } else if (m != null && _isAxisEvent(m)) {
              _setAxisHover(e.localPosition, leaveWhenOutside: false);
            } else {
              // touchEventsMiddleware: a finger over a sector activates it; elsewhere nothing changes.
              final hit = _sectorAt(e.localPosition);
              if (hit != null) _setItemHover(hit);
            }
          },
          onPointerUp: _onPointerUp,
          onPointerCancel: (_) => _downPosition = null,
          child: stack,
        ),
      ),
    );
    return SizedBox.fromSize(
      size: size,
      child: Focus(focusNode: _focusNode, onKeyEvent: _onKey, child: content),
    );
  }
}
