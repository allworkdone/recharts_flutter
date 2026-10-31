// Port of BrushWithState from src/cartesian/Brush.tsx: createScale (d3
// scalePoint over the data indexes), getIndexInRange/getIndex snapping with
// `gap`, traveller and slide dragging (mouse and touch, document-level
// move/up while dragging), the leave timer, keyboard moves, text visibility,
// Background, Slide, DefaultTraveller and BrushText geometry.
// Layout (selectBrushDimensions) is computed in engine/model.dart.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind, kTouchSlop;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../components.dart';
import '../core/scale.dart';
import '../render/shapes.dart';
import '../render/svg_text.dart';
import '../util.dart';

enum BrushTravellerId { startX, endX }

/// `getIndexInRange`: the last index whose coordinate is <= [x].
int getIndexInRange(List<double> valueRange, double x) {
  final len = valueRange.length;
  var start = 0;
  var end = len - 1;
  while (end - start > 1) {
    final middle = ((start + end) / 2).floor();
    if (valueRange[middle] > x) {
      end = middle;
    } else {
      start = middle;
    }
  }
  return end >= 0 && x >= valueRange[end] ? end : start;
}

/// `getIndex`.
BrushStartEndIndex getBrushIndex(
    {required double startX, required double endX, required List<double> scaleValues, required int gap, required int dataLength}) {
  final lastIndex = dataLength - 1;
  final minIndex = getIndexInRange(scaleValues, math.min(startX, endX));
  final maxIndex = getIndexInRange(scaleValues, math.max(startX, endX));
  // ponytail: gap <= 0 makes JS produce NaN indexes; treat it as 1.
  final g = math.max(gap, 1);
  return (
    startIndex: minIndex - (minIndex % g),
    endIndex: maxIndex == lastIndex ? lastIndex : maxIndex - (maxIndex % g),
  );
}

/// The brush of a cartesian chart. [rect] is `selectBrushDimensions` with `dy`
/// applied; [data] is the full chart data; [startIndex]/[endIndex] are the
/// chart's data indexes.
class BrushLayer extends StatefulWidget {
  const BrushLayer({
    super.key,
    required this.settings,
    required this.rect,
    required this.data,
    required this.startIndex,
    required this.endIndex,
    required this.onChange,
    required this.onDragEnd,
    required this.textStyle,
    required this.textScaler,
    this.focusedTraveller,
    this.panorama,
  });

  final Brush settings;
  final Rect rect;
  final List<Object?> data;
  final int startIndex, endIndex;

  /// `BrushInternal.onChange`.
  final ValueChanged<BrushStartEndIndex> onChange;
  final VoidCallback onDragEnd;
  final TextStyle textStyle;
  final TextScaler textScaler;

  /// The traveller holding DOM focus (`tabIndex=0`); the chart tracks focus.
  final BrushTravellerId? focusedTraveller;
  final Widget? panorama;

  @override
  State<BrushLayer> createState() => BrushLayerState();
}

class BrushLayerState extends State<BrushLayer> {
  bool isTravellerMoving = false;
  bool isTravellerFocused = false;
  bool isSlideMoving = false;
  bool isTextActive = false;
  double startX = 0, endX = 0;
  double _slideMoveStartX = 0, _brushMoveStartX = 0;
  BrushTravellerId? _movingTravellerId;
  PointScale? _scale;
  List<double>? scaleValues;

  // getDerivedStateFromProps bookkeeping
  Object? _prevData = const Object();
  double? _prevWidth, _prevX, _prevTravellerWidth;
  int? _prevStartIndexControlledFromProps, _prevEndIndexControlledFromProps;

  Timer? _leaveTimer;
  bool _dragListenersAttached = false;
  int? _dragPointer;
  Offset? _touchDown;
  bool _touchMoved = false;
  _Target? _hoverTarget;

  Brush get _props => widget.settings;
  double get _x => widget.rect.left;
  double get _width => widget.rect.width;
  double get _travellerWidth => _props.travellerWidth;

  @override
  void initState() {
    super.initState();
    isTravellerFocused = widget.focusedTraveller != null;
  }

  /// The travellers' onFocus / onBlur.
  @override
  void didUpdateWidget(BrushLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusedTraveller != widget.focusedTraveller) isTravellerFocused = widget.focusedTraveller != null;
  }

  @override
  void dispose() {
    _leaveTimer?.cancel();
    super.dispose();
  }

  /// `createScale`.
  void _createScale() {
    final scale = PointScale(
      domain: List<Object?>.generate(widget.data.length, (i) => i),
      range: [_x, _x + _width - _travellerWidth],
    );
    _scale = scale;
    scaleValues = [for (final d in scale.domain) ?scale.map(d)];
    isTextActive = false;
    isSlideMoving = false;
    isTravellerMoving = false;
    isTravellerFocused = false;
    startX = scale.map(widget.startIndex) ?? double.nan;
    endX = scale.map(widget.endIndex) ?? double.nan;
  }

  /// `getDerivedStateFromProps`; runs before every build like it runs before every render.
  void _deriveStateFromProps() {
    final data = widget.data;
    if (!identical(data, _prevData)) {
      _prevData = data;
      _prevTravellerWidth = _travellerWidth;
      _prevX = _x;
      _prevWidth = _width;
      _prevStartIndexControlledFromProps = _props.startIndex;
      _prevEndIndexControlledFromProps = _props.endIndex;
      if (data.isNotEmpty) {
        _createScale();
      } else {
        _scale = null;
        scaleValues = null;
      }
      return;
    }
    final prevScale = _scale;
    if (prevScale != null && (_width != _prevWidth || _x != _prevX || _travellerWidth != _prevTravellerWidth)) {
      final scale = PointScale(domain: prevScale.domain, range: [_x, _x + _width - _travellerWidth]);
      _scale = scale;
      scaleValues = [for (final d in scale.domain) ?scale.map(d)];
      _prevData = data;
      _prevTravellerWidth = _travellerWidth;
      _prevX = _x;
      _prevWidth = _width;
      startX = scale.map(widget.startIndex) ?? double.nan;
      endX = scale.map(widget.endIndex) ?? double.nan;
      return;
    }
    if (prevScale != null && !isSlideMoving && !isTravellerMoving && !isTravellerFocused && !isTextActive) {
      // Controlled indexes move the travellers, but never in the middle of an interaction.
      // React applies the end index one render later (the store update re-renders); both land.
      final s = _props.startIndex, e = _props.endIndex;
      if (s != null && _prevStartIndexControlledFromProps != s) {
        startX = prevScale.map(s) ?? double.nan;
        _prevStartIndexControlledFromProps = s;
      }
      if (e != null && _prevEndIndexControlledFromProps != e) {
        endX = prevScale.map(e) ?? double.nan;
        _prevEndIndexControlledFromProps = e;
      }
    }
  }

  // -------------------------------------------------------------- handlers

  void _handleDrag(double pageX) {
    _leaveTimer?.cancel();
    _leaveTimer = null;
    if (isTravellerMoving) {
      _handleTravellerMove(pageX);
    } else if (isSlideMoving) {
      _handleSlideDrag(pageX);
    }
  }

  void _handleDragEnd() {
    if (!mounted) return;
    setState(() {
      isTravellerMoving = false;
      isSlideMoving = false;
    });
    widget.onDragEnd();
    _dragListenersAttached = false;
  }

  void _handleLeaveWrapper() {
    if (isTravellerMoving || isSlideMoving) {
      _leaveTimer?.cancel();
      _leaveTimer = Timer(Duration(milliseconds: _props.leaveTimeOut), _handleDragEnd);
    }
  }

  void _handleSlideDragStart(double pageX) {
    setState(() {
      isTravellerMoving = false;
      isSlideMoving = true;
      _slideMoveStartX = pageX;
    });
    _dragListenersAttached = true;
  }

  void _handleSlideDrag(double pageX) {
    final values = scaleValues;
    if (values == null) return;
    final x = _x, width = _width, tw = _travellerWidth;
    var delta = pageX - _slideMoveStartX;
    if (delta > 0) {
      delta = [delta, x + width - tw - endX, x + width - tw - startX].reduce(math.min);
    } else if (delta < 0) {
      delta = [delta, x - startX, x - endX].reduce(math.max);
    }
    final newIndex = getBrushIndex(
        startX: startX + delta, endX: endX + delta, scaleValues: values, gap: _props.gap, dataLength: widget.data.length);
    if (newIndex.startIndex != widget.startIndex || newIndex.endIndex != widget.endIndex) {
      widget.onChange(newIndex);
    }
    setState(() {
      startX += delta;
      endX += delta;
      _slideMoveStartX = pageX;
    });
  }

  void _handleTravellerDragStart(BrushTravellerId id, double pageX) {
    setState(() {
      isSlideMoving = false;
      isTravellerMoving = true;
      _movingTravellerId = id;
      _brushMoveStartX = pageX;
    });
    _dragListenersAttached = true;
  }

  void _handleTravellerMove(double pageX) {
    final id = _movingTravellerId, values = scaleValues;
    if (id == null || values == null) return;
    final prevValue = id == BrushTravellerId.startX ? startX : endX;
    final x = _x, width = _width, tw = _travellerWidth, gap = _props.gap;
    var delta = pageX - _brushMoveStartX;
    if (delta > 0) {
      delta = math.min(delta, x + width - tw - prevValue);
    } else if (delta < 0) {
      delta = math.max(delta, x - prevValue);
    }
    final next = prevValue + delta;
    final newIndex = getBrushIndex(
      startX: id == BrushTravellerId.startX ? next : startX,
      endX: id == BrushTravellerId.endX ? next : endX,
      scaleValues: values,
      gap: gap,
      dataLength: widget.data.length,
    );
    // isFullGap reads the positions from before this move.
    final lastIndex = widget.data.length - 1;
    final g = math.max(gap, 1);
    final isFullGap = (id == BrushTravellerId.startX &&
            (endX > startX ? newIndex.startIndex % g == 0 : newIndex.endIndex % g == 0)) ||
        (endX < startX && newIndex.endIndex == lastIndex) ||
        (id == BrushTravellerId.endX && (endX > startX ? newIndex.endIndex % g == 0 : newIndex.startIndex % g == 0)) ||
        (endX > startX && newIndex.endIndex == lastIndex);
    setState(() {
      if (id == BrushTravellerId.startX) {
        startX = next;
      } else {
        endX = next;
      }
      _brushMoveStartX = pageX;
    });
    if (isFullGap) widget.onChange(newIndex);
  }

  /// `handleTravellerMoveKeyboard`: ArrowLeft (-1) / ArrowRight (1) on a focused traveller.
  void handleTravellerMoveKeyboard(int direction, BrushTravellerId id) {
    final values = scaleValues;
    if (values == null) return;
    final currentIndex = id == BrushTravellerId.startX ? widget.startIndex : widget.endIndex;
    if (currentIndex < 0 || currentIndex >= widget.data.length) return;
    final newIndex = currentIndex + direction;
    if (newIndex == -1 || newIndex >= values.length) return;
    final newScaleValue = values[newIndex];
    if ((id == BrushTravellerId.startX && newScaleValue >= endX) ||
        (id == BrushTravellerId.endX && newScaleValue <= startX)) {
      return;
    }
    setState(() {
      if (id == BrushTravellerId.startX) {
        startX = newScaleValue;
      } else {
        endX = newScaleValue;
      }
    });
    widget.onChange(getBrushIndex(
        startX: startX, endX: endX, scaleValues: values, gap: _props.gap, dataLength: widget.data.length));
  }

  // -------------------------------------------------------------- geometry

  double get _y => widget.rect.top;
  double get _height => widget.rect.height;

  /// `TravellerLayer`: `x = Math.max(travellerX, x)`.
  Rect _travellerRect(double travellerX) => Rect.fromLTWH(math.max(travellerX, _x), _y, _travellerWidth, _height);

  /// `Slide`.
  Rect get _slideRect => Rect.fromLTWH(
      math.min(startX, endX) + _travellerWidth, _y, math.max((endX - startX).abs() - _travellerWidth, 0), _height);

  /// Topmost element under [p] (chart coordinates), in SVG paint order reversed.
  _Target? _hit(Offset p) {
    bool inside(Rect r) => p.dx >= r.left && p.dx < r.right && p.dy >= r.top && p.dy < r.bottom;
    if (inside(_travellerRect(endX))) return _Target.endX;
    if (inside(_travellerRect(startX))) return _Target.startX;
    if (inside(_slideRect)) return _Target.slide;
    return null;
  }

  // -------------------------------------------------------------- pointer input

  /// Mouse enter/leave of the slide and travellers (`handleEnterSlideOrTraveller`).
  void _setHoverTarget(_Target? target) {
    if (target == _hoverTarget) return;
    setState(() {
      if (_hoverTarget != null) isTextActive = false;
      if (target != null) isTextActive = true;
      _hoverTarget = target;
    });
  }

  Offset _toChart(Offset local) => local + widget.rect.topLeft;

  /// The traveller under [chartPosition]: a mouse down there focuses it.
  BrushTravellerId? travellerAt(Offset chartPosition) => switch (_hit(chartPosition)) {
        _Target.startX => BrushTravellerId.startX,
        _Target.endX => BrushTravellerId.endX,
        _ => null,
      };

  void _dragStart(_Target target, double pageX) {
    switch (target) {
      case _Target.slide:
        _handleSlideDragStart(pageX);
      case _Target.startX:
        _handleTravellerDragStart(BrushTravellerId.startX, pageX);
      case _Target.endX:
        _handleTravellerDragStart(BrushTravellerId.endX, pageX);
    }
  }

  void _onPointerDown(PointerDownEvent e) {
    final target = _hit(_toChart(e.localPosition));
    if (e.kind == PointerDeviceKind.mouse) {
      _setHoverTarget(target);
    } else {
      _touchDown = e.position;
      _touchMoved = false;
    }
    if (target == null) return;
    _dragPointer = e.pointer;
    _dragStart(target, e.position.dx);
  }

  void _onPointerMove(PointerMoveEvent e) {
    final mouse = e.kind == PointerDeviceKind.mouse;
    if (mouse) _setHoverTarget(_hit(_toChart(e.localPosition)));
    if (!mouse && _touchDown != null && (e.position - _touchDown!).distance > kTouchSlop) _touchMoved = true;
    if (!_dragListenersAttached || e.pointer != _dragPointer) return;
    _handleDrag(e.position.dx);
  }

  void _onPointerUp(PointerUpEvent e) {
    if (e.kind != PointerDeviceKind.mouse && !_touchMoved) {
      // A tap: browsers follow touchend with an emulated mouseover on the target.
      _setHoverTarget(_hit(_toChart(e.localPosition)));
    }
    _touchDown = null;
    if (_dragListenersAttached) _handleDragEnd();
    _dragPointer = null;
  }

  /// Touch: the next tap elsewhere moves the emulated mouse out of the brush.
  void _onTapOutside(PointerDownEvent e) {
    if (e.kind != PointerDeviceKind.mouse) _setHoverTarget(null);
  }

  // -------------------------------------------------------------- build

  bool get textVisible =>
      isTextActive || isSlideMoving || isTravellerMoving || isTravellerFocused || _props.alwaysShowText;

  @override
  Widget build(BuildContext context) {
    _deriveStateFromProps();
    final r = widget.rect;
    if (widget.data.isEmpty || !r.width.isFinite || !r.height.isFinite || r.width <= 0 || r.height <= 0) {
      return const SizedBox.shrink();
    }
    final cursor = switch (_hoverTarget) {
      _Target.slide => SystemMouseCursors.move,
      _Target.startX || _Target.endX => SystemMouseCursors.resizeColumn,
      null => MouseCursor.defer,
    };
    return Stack(clipBehavior: Clip.none, children: [
      Positioned.fill(child: CustomPaint(painter: _BrushPainter(this, foreground: false))),
      // Panorama: a nested <svg>, which clips its overflow.
      if (widget.panorama != null)
        Positioned.fromRect(rect: r, child: ClipRect(child: IgnorePointer(child: widget.panorama!))),
      Positioned.fill(child: CustomPaint(painter: _BrushPainter(this, foreground: true))),
      Positioned.fromRect(
        rect: r,
        child: TapRegion(
          onTapOutside: _onTapOutside,
          child: MouseRegion(
            cursor: cursor,
            onEnter: (e) => _setHoverTarget(_hit(_toChart(e.localPosition))),
            onHover: (e) => _setHoverTarget(_hit(_toChart(e.localPosition))),
            onExit: (_) {
              _setHoverTarget(null);
              _handleLeaveWrapper();
            },
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              onPointerCancel: (_) => _dragPointer = null,
            ),
          ),
        ),
      ),
    ]);
  }

  // -------------------------------------------------------------- text

  /// `getTextOfTick`.
  String textOfTick(int index) {
    final data = widget.data;
    final text = getValueByDataKey(index >= 0 && index < data.length ? data[index] : null, _props.dataKey, index);
    return _props.tickFormatter != null ? _props.tickFormatter!(text, index) : jsString(text);
  }

  /// `BrushText`: the start label ends 5px left of the travellers, the end
  /// label starts 5px right of them, both vertically centered on the brush.
  List<({String text, Offset position, TextAnchor anchor})> get brushTexts {
    const offset = 5.0;
    final y = _y + _height / 2;
    return [
      (text: textOfTick(widget.startIndex), position: Offset(math.min(startX, endX) - offset, y), anchor: TextAnchor.end),
      (
        text: textOfTick(widget.endIndex),
        position: Offset(math.max(startX, endX) + _travellerWidth + offset, y),
        anchor: TextAnchor.start
      ),
    ];
  }

  /// `getAriaLabel`: reads `name` from the entries, whatever the dataKey.
  String get ariaLabel {
    if (_props.ariaLabel != null && _props.ariaLabel!.isNotEmpty) return _props.ariaLabel!;
    String nameAt(int i) {
      final d = i >= 0 && i < widget.data.length ? widget.data[i] : null;
      return d is Map && d['name'] is String ? d['name'] as String : 'undefined';
    }

    return 'Min value: ${nameAt(widget.startIndex)}, Max value: ${nameAt(widget.endIndex)}';
  }
}

enum _Target { slide, startX, endX }

class _BrushPainter extends CustomPainter {
  _BrushPainter(this.s, {required this.foreground});
  final BrushLayerState s;
  final bool foreground;

  @override
  void paint(Canvas canvas, Size size) {
    final props = s.widget.settings;
    final r = s.widget.rect;
    if (!foreground) {
      // Background
      if (props.fill != null) canvas.drawRect(r, fillPaint(props.fill!));
      if (props.stroke != null) canvas.drawRect(r, strokePaint(props.stroke!, 1));
      return;
    }
    final stroke = props.stroke;
    // Slide
    final slide = s._slideRect;
    if (stroke != null && slide.width > 0 && slide.left.isFinite) {
      canvas.drawRect(slide, fillPaint(stroke, opacity: 0.2));
    }
    // Travellers
    for (final travellerX in [s.startX, s.endX]) {
      if (!travellerX.isFinite) continue;
      final t = s._travellerRect(travellerX);
      final tp = BrushTravellerProps(
          x: t.left, y: t.top, width: t.width, height: t.height, fill: props.fill, stroke: stroke);
      if (props.traveller != null) {
        props.traveller!(canvas, tp);
      } else {
        _defaultTraveller(canvas, tp);
      }
    }
    // BrushText
    if (s.textVisible && s.startX.isFinite && s.endX.isFinite) {
      final style = s.widget.textStyle.copyWith(color: stroke ?? const Color(0xFF000000));
      for (final t in s.brushTexts) {
        paintSvgText(canvas, t.text, t.position.dx, t.position.dy,
            style: style,
            textAnchor: t.anchor,
            verticalAnchor: TextVerticalAnchor.middle,
            scaler: s.widget.textScaler);
      }
    }
  }

  /// `DefaultTraveller`.
  void _defaultTraveller(Canvas canvas, BrushTravellerProps p) {
    final x = p.x, y = p.y, width = p.width, height = p.height;
    final lineY = (y + height / 2).floorToDouble() - 1;
    if (p.stroke != null) canvas.drawRect(Rect.fromLTWH(x, y, width, height), fillPaint(p.stroke!));
    final white = strokePaint(const Color(0xFFFFFFFF), 1);
    canvas.drawLine(Offset(x + 1, lineY), Offset(x + width - 1, lineY), white);
    canvas.drawLine(Offset(x + 1, lineY + 2), Offset(x + width - 1, lineY + 2), white);
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  SemanticsBuilderCallback? get semanticsBuilder => foreground ? _semantics : null;

  List<CustomPainterSemantics> _semantics(Size size) => [
        for (final travellerX in [s.startX, s.endX])
          if (travellerX.isFinite)
            CustomPainterSemantics(
              rect: s._travellerRect(travellerX),
              properties: SemanticsProperties(
                  slider: true,
                  label: s.ariaLabel,
                  value: jsString(travellerX),
                  textDirection: TextDirection.ltr),
            ),
      ];

  @override
  bool shouldRebuildSemantics(_BrushPainter old) => true;

  @override
  bool shouldRepaint(_BrushPainter old) => true;
}
