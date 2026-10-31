// Port of src/component/ResponsiveContainer.tsx and responsiveContainerUtils.ts.
// The parent's constraints stand in for the measured DOM box.

import 'package:flutter/widgets.dart';

import '../util.dart';

/// Provides the calculated chart size to descendant charts, which then ignore
/// their own width/height (`ResponsiveContainerContext`).
class ResponsiveContainerScope extends InheritedWidget {
  const ResponsiveContainerScope({super.key, required this.size, required super.child});
  final Size size;

  static Size? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ResponsiveContainerScope>()?.size;

  @override
  bool updateShouldNotify(ResponsiveContainerScope old) => old.size != size;
}

/// `calculateChartDimensions`.
({double? width, double? height}) calculateChartDimensions(
  double? containerWidth,
  double? containerHeight, {
  Object? width = '100%',
  Object? height = '100%',
  double? aspect,
  double? maxHeight,
}) {
  width ??= '100%';
  height ??= '100%';
  double? calculatedWidth = isPercent(width) ? containerWidth : jsNumber(width);
  double? calculatedHeight = isPercent(height) ? containerHeight : jsNumber(height);
  if (aspect != null && aspect > 0) {
    if (calculatedWidth != null && calculatedWidth != 0 && !calculatedWidth.isNaN) {
      calculatedHeight = calculatedWidth / aspect;
    } else if (calculatedHeight != null && calculatedHeight != 0 && !calculatedHeight.isNaN) {
      calculatedWidth = calculatedHeight * aspect;
    }
    if (maxHeight != null && maxHeight > 0 && calculatedHeight != null && calculatedHeight > maxHeight) {
      calculatedHeight = maxHeight;
    }
  }
  return (width: calculatedWidth, height: calculatedHeight);
}

class ResponsiveContainer extends StatelessWidget {
  const ResponsiveContainer({
    super.key,
    this.width,
    this.height,
    this.aspect,
    this.minWidth = 0,
    this.minHeight,
    this.maxHeight,
    this.onResize,
    required this.child,
  });

  /// A number or a percent string such as `'80%'` (default `'100%'`).
  final Object? width;

  /// A number or a percent string (default `'100%'`).
  final Object? height;
  final double? aspect;
  final double minWidth;
  final double? minHeight;
  final double? maxHeight;
  final void Function(double width, double height)? onResize;
  final Widget child;

  double _resolve(Object? v, double parent) {
    if (isPercent(v)) {
      final pct = jsNumber((v as String).substring(0, v.length - 1));
      return parent.isFinite ? parent * pct / 100 : 0;
    }
    return jsNumber(v);
  }

  @override
  Widget build(BuildContext context) {
    // getDefaultWidthAndHeight
    var w = width, h = height;
    if (w == null && h == null) {
      w = '100%';
      h = '100%';
    } else if (w == null) {
      w = aspect != null && aspect! > 0 ? null : '100%';
    } else {
      h ??= aspect != null && aspect! > 0 ? null : '100%';
    }
    return LayoutBuilder(builder: (context, constraints) {
      // The outer div: width/height/min/max from props, measured and rounded.
      var containerWidth = w == null ? constraints.maxWidth : _resolve(w, constraints.maxWidth);
      var containerHeight = h == null ? 0.0 : _resolve(h, constraints.maxHeight);
      if (!containerWidth.isFinite) containerWidth = 0;
      containerWidth = jsRound(containerWidth < minWidth ? minWidth : containerWidth);
      if (minHeight != null && containerHeight < minHeight!) containerHeight = minHeight!;
      if (maxHeight != null && containerHeight > maxHeight!) containerHeight = maxHeight!;
      containerHeight = jsRound(containerHeight);
      final dims = calculateChartDimensions(containerWidth, containerHeight,
          width: w, height: h, aspect: aspect, maxHeight: maxHeight);
      final cw = dims.width ?? 0, ch = dims.height ?? 0;
      if (onResize != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => onResize!(containerWidth, containerHeight));
      }
      final boxHeight = h == null ? ch : containerHeight;
      if (!(cw > 0 && ch > 0)) return SizedBox(width: containerWidth, height: boxHeight);
      return SizedBox(
        width: containerWidth,
        height: boxHeight,
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: cw,
          maxWidth: cw,
          minHeight: ch,
          maxHeight: ch,
          child: ResponsiveContainerScope(size: Size(cw, ch), child: child),
        ),
      );
    });
  }
}
