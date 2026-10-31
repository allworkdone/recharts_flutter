// Port of src/cartesian/getTicks.ts, src/cartesian/getEquidistantTicks.ts,
// src/util/TickUtils.ts, src/util/getEveryNth.ts and getAngledRectangleWidth
// from src/util/CartesianUtils.ts. getStringSize is replaced by [measure].

import 'dart:math' as math;
import 'dart:ui';

import '../components.dart';
import '../util.dart';

class TickItem {
  TickItem({
    required this.coordinate,
    required this.value,
    required this.index,
    this.offset = 0,
    this.tickCoord,
    this.isShow = false,
  });
  final double coordinate;
  final Object? value;
  final int index;
  final double offset;
  double? tickCoord;
  bool isShow;

  TickItem copy({double? tickCoord, bool? isShow}) => TickItem(
        coordinate: coordinate,
        value: value,
        index: index,
        offset: offset,
        tickCoord: tickCoord ?? this.tickCoord,
        isShow: isShow ?? this.isShow,
      );

  @override
  String toString() => 'TickItem($value @ $coordinate)';
}

/// Measures a string like `getStringSize(text, {fontSize, letterSpacing})`.
typedef StringMeasurer = Size Function(String text);

List<T> getEveryNth<T>(List<T> array, int n) {
  if (n < 1) return [];
  if (n == 1) return array;
  return [for (var i = 0; i < array.length; i += n) array[i]];
}

double normalizeAngle(double angle) => ((angle % 180) + 180) % 180;

double getAngledRectangleWidth(Size size, [double angle = 0]) {
  final normalizedAngle = normalizeAngle(angle);
  final angleRadians = normalizedAngle * math.pi / 180;
  final angleThreshold = math.atan(size.height / size.width);
  final angledWidth = angleRadians > angleThreshold && angleRadians < math.pi - angleThreshold
      ? size.height / math.sin(angleRadians)
      : size.width / math.cos(angleRadians);
  return angledWidth.abs();
}

double getAngledTickWidth(Size contentSize, Size unitSize, double angle) => getAngledRectangleWidth(
    Size(contentSize.width + unitSize.width, contentSize.height + unitSize.height), angle);

({double start, double end}) getTickBoundaries(Rect viewBox, int sign, bool isWidth) {
  if (sign == 1) {
    return (
      start: isWidth ? viewBox.left : viewBox.top,
      end: isWidth ? viewBox.left + viewBox.width : viewBox.top + viewBox.height,
    );
  }
  return (
    start: isWidth ? viewBox.left + viewBox.width : viewBox.top + viewBox.height,
    end: isWidth ? viewBox.left : viewBox.top,
  );
}

bool isVisible(int sign, double tickPosition, double Function() getSize, double start, double end) {
  if (sign * tickPosition < sign * start || sign * tickPosition > sign * end) return false;
  final size = getSize();
  return sign * (tickPosition - (sign * size) / 2 - start) >= 0 &&
      sign * (tickPosition + (sign * size) / 2 - end) <= 0;
}

typedef TickSizeFn = double Function(TickItem tick, int index);

List<TickItem> _getTicksEnd(
    int sign, ({double start, double end}) boundaries, TickSizeFn getTickSize, List<TickItem> ticks, double minTickGap) {
  final result = ticks.toList();
  final len = result.length;
  final start = boundaries.start;
  var end = boundaries.end;
  for (var i = len - 1; i >= 0; i--) {
    final initialEntry = result[i];
    var entry = initialEntry;
    double? size;
    double getSize() => size ??= getTickSize(initialEntry, i);
    if (i == len - 1) {
      final gap = sign * (entry.coordinate + (sign * getSize()) / 2 - end);
      result[i] = entry = entry.copy(tickCoord: gap > 0 ? entry.coordinate - gap * sign : entry.coordinate);
    } else {
      result[i] = entry = entry.copy(tickCoord: entry.coordinate);
    }
    final tickCoord = entry.tickCoord!;
    if (isVisible(sign, tickCoord, getSize, start, end)) {
      end = tickCoord - sign * (getSize() / 2 + minTickGap);
      result[i] = entry.copy(isShow: true);
    }
  }
  return result;
}

List<TickItem> _getTicksStart(int sign, ({double start, double end}) boundaries, TickSizeFn getTickSize,
    List<TickItem> ticks, double minTickGap, bool preserveEnd) {
  final result = ticks.toList();
  final len = result.length;
  var start = boundaries.start;
  var end = boundaries.end;
  if (preserveEnd && len > 0) {
    var tail = ticks[len - 1];
    final tailSize = getTickSize(tail, len - 1);
    final tailGap = sign * (tail.coordinate + (sign * tailSize) / 2 - end);
    result[len - 1] = tail = tail.copy(tickCoord: tailGap > 0 ? tail.coordinate - tailGap * sign : tail.coordinate);
    if (isVisible(sign, tail.tickCoord!, () => tailSize, start, end)) {
      end = tail.tickCoord! - sign * (tailSize / 2 + minTickGap);
      result[len - 1] = tail.copy(isShow: true);
    }
  }
  final count = preserveEnd ? len - 1 : len;
  for (var i = 0; i < count; i++) {
    final initialEntry = result[i];
    var entry = initialEntry;
    double? size;
    double getSize() => size ??= getTickSize(initialEntry, i);
    if (i == 0) {
      final gap = sign * (entry.coordinate - (sign * getSize()) / 2 - start);
      result[i] = entry = entry.copy(tickCoord: gap < 0 ? entry.coordinate - gap * sign : entry.coordinate);
    } else {
      result[i] = entry = entry.copy(tickCoord: entry.coordinate);
    }
    final tickCoord = entry.tickCoord!;
    if (isVisible(sign, tickCoord, getSize, start, end)) {
      start = tickCoord + sign * (getSize() / 2 + minTickGap);
      result[i] = entry.copy(isShow: true);
    }
  }
  return result;
}

List<TickItem> getEquidistantTicks(
    int sign, ({double start, double end}) boundaries, TickSizeFn getTickSize, List<TickItem> ticks, double minTickGap) {
  final result = ticks.toList();
  final initialStart = boundaries.start;
  final end = boundaries.end;
  var index = 0;
  var stepsize = 1;
  var start = initialStart;
  while (stepsize <= result.length) {
    if (index >= ticks.length) return getEveryNth(ticks, stepsize);
    final entry = ticks[index];
    final i = index;
    double? size;
    double getSize() => size ??= getTickSize(entry, i);
    final tickCoord = entry.coordinate;
    final isShow = index == 0 || isVisible(sign, tickCoord, getSize, start, end);
    if (!isShow) {
      index = 0;
      start = initialStart;
      stepsize += 1;
    } else {
      start = tickCoord + sign * (getSize() / 2 + minTickGap);
      index += stepsize;
    }
  }
  return [];
}

List<TickItem> getEquidistantPreserveEndTicks(
    int sign, ({double start, double end}) boundaries, TickSizeFn getTickSize, List<TickItem> ticks, double minTickGap) {
  final len = ticks.length;
  if (len == 0) return [];
  final initialStart = boundaries.start;
  final end = boundaries.end;
  for (var stepsize = 1; stepsize <= len; stepsize++) {
    final offset = (len - 1) % stepsize;
    var start = initialStart;
    var ok = true;
    for (var index = offset; index < len; index += stepsize) {
      final entry = ticks[index];
      final i = index;
      double? size;
      double getSize() => size ??= getTickSize(entry, i);
      final tickCoord = entry.coordinate;
      final isShow = index == offset || isVisible(sign, tickCoord, getSize, start, end);
      if (!isShow) {
        ok = false;
        break;
      }
      start = tickCoord + sign * (getSize() / 2 + minTickGap);
    }
    if (ok) return [for (var index = offset; index < len; index += stepsize) ticks[index]];
  }
  return [];
}

/// `getTicks(props, fontSize, letterSpacing)`; [viewBox] is the axis view box
/// (the whole chart for axes and grid).
List<TickItem> getTicks({
  required Object tick,
  required List<TickItem>? ticks,
  required Rect viewBox,
  required double minTickGap,
  required AxisOrientation orientation,
  required AxisInterval interval,
  TickFormatter? tickFormatter,
  String? unit,
  double angle = 0,
  required StringMeasurer measure,
}) {
  if (ticks == null || ticks.isEmpty || tick == false) return [];
  if (interval.number != null) return getEveryNth(ticks, interval.number! + 1);

  final isWidth = orientation == AxisOrientation.top || orientation == AxisOrientation.bottom;
  final unitSize = unit != null && unit.isNotEmpty && isWidth ? measure(unit) : Size.zero;

  double getTickSize(TickItem content, int index) {
    final value = tickFormatter != null ? tickFormatter(content.value, index) : jsString(content.value);
    final size = measure(value);
    return isWidth ? getAngledTickWidth(size, unitSize, angle) : size.height;
  }

  final sign = ticks.length >= 2 ? mathSign(ticks[1].coordinate - ticks[0].coordinate) : 1;
  final boundaries = getTickBoundaries(viewBox, sign, isWidth);

  switch (interval.name) {
    case 'equidistantPreserveStart':
      return getEquidistantTicks(sign, boundaries, getTickSize, ticks, minTickGap);
    case 'equidistantPreserveEnd':
      return getEquidistantPreserveEndTicks(sign, boundaries, getTickSize, ticks, minTickGap);
  }
  final List<TickItem> candidates;
  if (interval.name == 'preserveStart' || interval.name == 'preserveStartEnd') {
    candidates =
        _getTicksStart(sign, boundaries, getTickSize, ticks, minTickGap, interval.name == 'preserveStartEnd');
  } else {
    candidates = _getTicksEnd(sign, boundaries, getTickSize, ticks, minTickGap);
  }
  return candidates.where((e) => e.isShow).toList();
}
