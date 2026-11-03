// Port of src/component/DefaultTooltipContent.tsx (CSS box as widgets),
// src/component/TooltipBoundingBox.tsx and src/util/tooltip/translate.ts.
// The CSS `transition: transform 400ms ease` is reproduced by animating the
// translate from wherever the box currently is to the new target.

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../components.dart';
import '../core/easing.dart';
import '../render/svg_text.dart';
import '../util.dart';
import '../css_color.dart' show textColorOf;

/// `getTooltipTranslateXY` for one dimension.
double getTooltipTranslateXY({
  required bool allowEscapeViewBox,
  required double coordinate,
  required double offset,
  double? position,
  required bool reverseDirection,
  required double tooltipDimension,
  required double viewBoxStart,
  required double viewBoxDimension,
}) {
  if (position != null) return position;
  final negative = coordinate - tooltipDimension - (offset > 0 ? offset : 0);
  final positive = coordinate + offset;
  if (allowEscapeViewBox) return reverseDirection ? negative : positive;
  if (reverseDirection) {
    if (negative < viewBoxStart) return positive > viewBoxStart ? positive : viewBoxStart;
    return negative > viewBoxStart ? negative : viewBoxStart;
  }
  if (positive + tooltipDimension > viewBoxStart + viewBoxDimension) {
    return negative > viewBoxStart ? negative : viewBoxStart;
  }
  return positive > viewBoxStart ? positive : viewBoxStart;
}

/// `getTooltipTranslate`; null where Recharts hides the box (no size or coordinate).
Offset? getTooltipTranslate({
  required ({bool x, bool y}) allowEscapeViewBox,
  required Offset? coordinate,
  required double offset,
  ({double? x, double? y})? position,
  required ({bool x, bool y}) reverseDirection,
  required Size tooltipBox,
  required Rect viewBox,
}) {
  if (coordinate == null || tooltipBox.width <= 0 || tooltipBox.height <= 0) return null;
  return Offset(
    getTooltipTranslateXY(
      allowEscapeViewBox: allowEscapeViewBox.x,
      coordinate: coordinate.dx,
      offset: offset,
      position: position?.x,
      reverseDirection: reverseDirection.x,
      tooltipDimension: tooltipBox.width,
      viewBoxStart: viewBox.left,
      viewBoxDimension: viewBox.width,
    ),
    getTooltipTranslateXY(
      allowEscapeViewBox: allowEscapeViewBox.y,
      coordinate: coordinate.dy,
      offset: offset,
      position: position?.y,
      reverseDirection: reverseDirection.y,
      tooltipDimension: tooltipBox.height,
      viewBoxStart: viewBox.top,
      viewBoxDimension: viewBox.height,
    ),
  );
}

Object? _defaultFormatter(Object? value) =>
    value is List && value.length == 2 && isNumOrStr(value[0]) && isNumOrStr(value[1]) ? value.map(jsString).join(' ~ ') : value;

/// `DefaultTooltipContent`.
class DefaultTooltipContent extends StatelessWidget {
  const DefaultTooltipContent({
    super.key,
    required this.payload,
    this.label,
    this.separator = ' : ',
    this.contentStyle = const TooltipContentStyle(),
    this.itemStyle,
    this.labelStyle,
    this.itemSorter,
    this.formatter,
    this.labelFormatter,
  });

  final List<TooltipPayloadEntry> payload;
  final Object? label;
  final String separator;
  final TooltipContentStyle contentStyle;
  final TextStyle? itemStyle;
  final TextStyle? labelStyle;
  final Object? itemSorter;
  final TooltipFormatter? formatter;
  final Object? Function(Object? label, List<TooltipPayloadEntry> payload)? labelFormatter;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    final base = withCssNormalLineHeight(DefaultTextStyle.of(context).style, scaler);
    final sorted = switch (itemSorter) {
      'name' => sortByKey(payload, (e) => e.name),
      'value' => sortByKey(payload, (e) => e.value),
      'dataKey' => sortByKey(payload, (e) => e.dataKey is Function ? null : e.dataKey),
      Object? Function(TooltipPayloadEntry) f => sortByKey(payload, f),
      _ => payload,
    };
    final items = <Widget>[];
    for (var i = 0; i < sorted.length; i++) {
      final entry = sorted[i];
      if (entry.type == 'none') continue;
      Object? finalValue = entry.value;
      Object? finalName = entry.name;
      final f = entry.formatter ?? formatter;
      final formatted = f != null ? f(entry.value, entry.name, entry, i, payload) : _defaultFormatter(entry.value);
      if (formatted is List && formatted.length == 2) {
        finalValue = formatted[0];
        finalName = formatted[1];
      } else if (formatted != null) {
        finalValue = formatted;
      } else {
        continue;
      }
      final hasName = isNumOrStr(finalName);
      items.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text.rich(
          TextSpan(children: [
            if (hasName) TextSpan(text: jsString(finalName)),
            if (hasName) TextSpan(text: separator),
            finalValue is InlineSpan ? finalValue : TextSpan(text: jsString(finalValue)),
            TextSpan(text: entry.unit ?? ''),
          ]),
          style: base.copyWith(color: textColorOf(entry.color) ?? const Color(0xFF000000)).merge(itemStyle),
          softWrap: false,
        ),
      ));
    }
    Object? finalLabel = label ?? '';
    if (label != null && labelFormatter != null) finalLabel = labelFormatter!(label, payload);
    final labelText = finalLabel is String ? finalLabel : jsString(finalLabel);
    return Container(
      padding: contentStyle.padding,
      decoration: BoxDecoration(
        color: contentStyle.backgroundColor,
        border: contentStyle.border,
        borderRadius: contentStyle.borderRadius,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (finalLabel is Widget) finalLabel else if (labelText.isNotEmpty) Text(labelText, style: base.merge(labelStyle), softWrap: false),
          ...items,
        ],
      ),
    );
  }
}

/// `TooltipBoundingBox`: positions [child] by `translate(x, y)` relative to the
/// chart and transitions between positions while [active].
class TooltipBoundingBox extends SingleChildRenderObjectWidget {
  const TooltipBoundingBox({
    super.key,
    required this.vsync,
    required this.active,
    required this.hasPayload,
    required this.coordinate,
    required this.viewBox,
    required this.offset,
    required this.allowEscapeViewBox,
    required this.reverseDirection,
    this.position,
    required this.animate,
    required this.animationDuration,
    required this.animationEasing,
    required super.child,
  });

  final TickerProvider vsync;
  final bool active;
  final bool hasPayload;
  final Offset? coordinate;
  final Rect viewBox;
  final double offset;
  final ({bool x, bool y}) allowEscapeViewBox;
  final ({bool x, bool y}) reverseDirection;
  final ({double? x, double? y})? position;
  final bool animate;
  final int animationDuration;
  final Object animationEasing;

  @override
  RenderTooltipBoundingBox createRenderObject(BuildContext context) => RenderTooltipBoundingBox(vsync)..update(this);

  @override
  void updateRenderObject(BuildContext context, RenderTooltipBoundingBox renderObject) => renderObject.update(this);
}

class RenderTooltipBoundingBox extends RenderShiftedBox {
  RenderTooltipBoundingBox(this._vsync) : super(null);

  final TickerProvider _vsync;
  Ticker? _ticker;
  late TooltipBoundingBox _config;

  /// The translate currently on screen; CSS starts from `transform: none`.
  Offset _current = Offset.zero;
  Offset _from = Offset.zero;
  Offset? _to;
  Duration _elapsed = Duration.zero;
  EasingFunction _easing = (t) => t;
  bool _visible = false;

  void update(TooltipBoundingBox config) {
    _config = config;
    _easing = createEasingFunction(config.animationEasing) ?? _easing;
    markNeedsLayout();
  }

  /// The translate the box is heading to, for tests and the parity harness.
  Offset? get targetTranslate => _to;
  Offset get currentTranslate => _current;
  bool get isVisible => _visible;

  @override
  void performLayout() {
    size = constraints.biggest;
    final c = child;
    if (c == null) return;
    c.layout(const BoxConstraints(), parentUsesSize: true);
    var target = getTooltipTranslate(
      allowEscapeViewBox: _config.allowEscapeViewBox,
      coordinate: _config.coordinate,
      offset: _config.offset,
      position: _config.position,
      reverseDirection: _config.reverseDirection,
      tooltipBox: c.size,
      viewBox: _config.viewBox,
    );
    // Without a coordinate translate.ts gives TOOLTIP_HIDDEN, but TooltipBoundingBox spreads `visibility`
    // after it: an active tooltip with a payload shows at the wrapper's (0, 0), no offset.
    if (target == null && _config.coordinate == null && c.size.width > 0 && c.size.height > 0) target = Offset.zero;
    _visible = target != null && _config.active && _config.hasPayload;
    if (target == null || target == _to) return;
    _to = target;
    final transition = _config.animate && _config.active;
    if (transition && _current != target) {
      _from = _current;
      _elapsed = Duration.zero;
      // A new CSS transition starts from the current position with a fresh clock.
      (_ticker ??= _vsync.createTicker(_tick))
        ..stop()
        ..start();
    } else {
      _ticker?.stop();
      _current = target;
    }
  }

  void _tick(Duration elapsed) {
    _elapsed = elapsed;
    final progress = (_elapsed.inMicroseconds / 1000 / _config.animationDuration).clamp(0.0, 1.0);
    final to = _to ?? _current;
    _current = Offset.lerp(_from, to, progress >= 1 ? 1 : _easing(progress))!;
    if (progress >= 1) {
      _current = to;
      _ticker?.stop();
    }
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final c = child;
    if (c == null || !_visible) return;
    (c.parentData as BoxParentData).offset = _current;
    context.paintChild(c, offset + _current);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => false;

  @override
  void detach() {
    _ticker?.stop();
    super.detach();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }
}

/// The Tooltip as every chart renders it: the custom `content` or
/// [DefaultTooltipContent], in a [TooltipBoundingBox] over [viewBox].
Widget tooltipLayer(
  Tooltip tooltip, {
  required TickerProvider vsync,
  required bool reducedMotion,
  required Rect viewBox,
  required bool active,
  required List<TooltipPayloadEntry> payload,
  Object? label,
  Offset? coordinate,
  Object? activeIndex,
}) {
  final content = tooltip.content != null
      ? tooltip.content!(TooltipContentProps(
          active: active,
          payload: payload,
          label: label,
          coordinate: coordinate,
          activeIndex: activeIndex,
        ))
      : DefaultTooltipContent(
          payload: payload,
          label: label,
          separator: tooltip.separator,
          contentStyle: tooltip.contentStyle,
          itemStyle: tooltip.itemStyle,
          labelStyle: tooltip.labelStyle,
          itemSorter: tooltip.itemSorter,
          formatter: tooltip.formatter,
          labelFormatter: tooltip.labelFormatter,
        );
  return TooltipBoundingBox(
    vsync: vsync,
    active: active,
    hasPayload: payload.isNotEmpty,
    coordinate: coordinate,
    viewBox: viewBox,
    offset: tooltip.offset,
    allowEscapeViewBox: tooltip.allowEscapeViewBox,
    reverseDirection: tooltip.reverseDirection,
    position: tooltip.position,
    animate: tooltip.isAnimationActive ?? !reducedMotion,
    animationDuration: tooltip.animationDuration,
    animationEasing: tooltip.animationEasing,
    child: content,
  );
}
