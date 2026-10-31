// Ports of src/animation/matchBy.ts, AnimatedItems.tsx (+ useAnimationStartSnapshot.ts),
// JavascriptAnimate.tsx / AnimationHandle.ts timing, the default interpolators
// of Line.tsx and Bar.tsx, and src/cartesian/useAnimatedLineLength.ts.

import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'core/curve.dart';
import 'core/easing.dart';
import 'engine/model.dart';
import 'util.dart';

enum MatchBy { byIndex, append }

sealed class AnimationItem<T> {
  const AnimationItem();
}

class Matched<T> extends AnimationItem<T> {
  const Matched(this.prev, this.next);
  final T prev, next;
}

class Added<T> extends AnimationItem<T> {
  const Added(this.next);
  final T next;
}

class Removed<T> extends AnimationItem<T> {
  const Removed(this.prev);
  final T prev;
}

List<AnimationItem<T>> _tag<T>(List<T?> alignedPrev, List<T> next) => [
      for (var i = 0; i < next.length; i++)
        if (alignedPrev[i] != null) Matched<T>(alignedPrev[i] as T, next[i]) else Added<T>(next[i]),
    ];

/// `matchAnimationItems(prev, next, matchBy)`.
List<AnimationItem<T>>? matchAnimationItems<T>(List<T>? prev, List<T>? next, MatchBy matchBy) {
  if (next == null) return null;
  if (prev == null) return [for (final n in next) Added<T>(n)];
  if (matchBy == MatchBy.byIndex) {
    final factor = prev.length / next.length;
    return _tag([for (var i = 0; i < next.length; i++) prev.isEmpty ? null : prev[(i * factor).floor()]], next);
  }
  return _tag([for (var i = 0; i < next.length; i++) i < prev.length ? prev[i] : null], next);
}

/// `defaultLineAnimateItems`.
List<LinePoint> interpolateLinePoints(List<AnimationItem<LinePoint>>? items, double t) {
  if (items == null) return const [];
  if (t == 1) {
    return [
      for (final i in items)
        if (i is Matched<LinePoint>) i.next else if (i is Added<LinePoint>) i.next,
    ];
  }
  var total = 0.0;
  var count = 0;
  for (final i in items) {
    if (i is Matched<LinePoint> && i.prev.x != null && i.next.x != null) {
      total += i.next.x! - i.prev.x!;
      count++;
    }
  }
  final shift = count > 0 ? total / count : 0.0;
  final out = <LinePoint>[];
  for (final i in items) {
    switch (i) {
      case Matched(:final prev, :final next):
        out.add(LinePoint(interpolate(prev.x, next.x, t), interpolate(prev.y, next.y, t), next.value, next.payload));
      case Added(:final next):
        out.add(next.x != null
            ? LinePoint(interpolate(next.x! - shift, next.x, t), next.y, next.value, next.payload)
            : next);
      case Removed(:final prev):
        if (prev.x != null) {
          out.add(LinePoint(interpolate(prev.x, prev.x! + shift, t), prev.y, prev.value, prev.payload));
        }
    }
  }
  return out;
}

/// `defaultBarAnimateItems`.
List<BarRect> interpolateBarRects(List<AnimationItem<BarRect>>? items, double t, ChartLayout layout) {
  if (items == null) return const [];
  if (t == 1) {
    return [
      for (final i in items)
        if (i is Matched<BarRect>) i.next else if (i is Added<BarRect>) i.next,
    ];
  }
  final horizontal = layout == ChartLayout.horizontal;
  return [
    for (final i in items)
      switch (i) {
        Removed(:final prev) => horizontal
            ? prev.copyWith(height: interpolate(prev.height, 0, t), y: interpolate(prev.y, prev.y + prev.height, t))
            : prev.copyWith(width: interpolate(prev.width, 0, t)),
        Matched(:final prev, :final next) => next.copyWith(
            x: interpolate(prev.x, next.x, t),
            y: interpolate(prev.y, next.y, t),
            width: interpolate(prev.width, next.width, t),
            height: interpolate(prev.height, next.height, t),
          ),
        Added(:final next) => horizontal
            ? next.copyWith(height: interpolate(0, next.height, t), y: interpolate(next.stackedBarStart, next.y, t))
            : next.copyWith(width: interpolate(0, next.width, t), x: interpolate(next.stackedBarStart, next.x, t)),
      },
  ];
}

/// One `AnimatedItems` + `JavascriptAnimate` pair for a graphical item.
///
/// A new animation starts whenever the target items change by value (Recharts
/// restarts when its memoized selector output changes identity). The start
/// snapshot is whatever was last rendered, so interrupted animations continue
/// from their current state.
class SeriesAnimator<T> {
  SeriesAnimator(TickerProvider vsync, {required this.matchBy}) : controller = AnimationController(vsync: vsync) {
    controller.addStatusListener((s) {
      if (s == AnimationStatus.completed && _running) {
        _running = false;
        onAnimationEnd?.call();
      }
    });
  }

  final MatchBy matchBy;
  final AnimationController controller;
  EasingFunction _easing = (t) => t;
  bool _active = true;
  bool _running = false;
  double _beginFraction = 0;
  VoidCallback? onAnimationEnd;

  List<T>? target;
  List<T>? _startSnapshot;
  List<T>? _previousRendered;
  bool _readyToCommit = true;
  int? _pendingStart;

  /// Bumps when a new animation input arrives (`useAnimationId`).
  int animationId = 0;

  /// `useAnimationCallbacks().isAnimating`.
  bool get isAnimating => _running;

  /// Returns true when a new animation cycle started.
  bool update(
    List<T>? items, {
    required bool active,
    required int begin,
    required int duration,
    required Object easing,
    VoidCallback? onAnimationStart,
    VoidCallback? onAnimationEnd,
  }) {
    this.onAnimationEnd = onAnimationEnd;
    _easing = createEasingFunction(easing) ?? _easing;
    if (target != null && items != null && listEquals(items, target)) {
      if (!active && _active) {
        _active = false;
        controller.value = 1;
      }
      return false;
    }
    _cancelPendingStart();
    if (items == null) {
      // Recharts unmounts a hidden item; showing it again is a fresh entrance.
      final changed = target != null || _previousRendered != null;
      target = _startSnapshot = _previousRendered = null;
      _running = false;
      return changed;
    }
    final isFirst = target == null && _previousRendered == null;
    target = items;
    _startSnapshot = _previousRendered;
    _readyToCommit = isFirst;
    animationId++;
    _active = active;
    if (!_active) {
      controller.value = 1;
      _running = false;
      return true;
    }
    final int totalMs = math.max(0, begin) + math.max(0, duration);
    final total = totalMs;
    _beginFraction = total == 0 ? 0 : math.max(0, begin) / total;
    controller.duration = Duration(milliseconds: totalMs == 0 ? 1 : totalMs);
    _running = true;
    // AnimationHandle.tick moves INIT -> PENDING -> ACTIVE on successive
    // frames, so Recharts reaches progress 0 one frame after the frame that
    // could have started it. Starting the ticker from the next frame's
    // callback gives the same timeline.
    controller.value = 0;
    final id = animationId;
    _pendingStart = SchedulerBinding.instance.scheduleFrameCallback((_) {
      _pendingStart = null;
      if (_running && id == animationId) controller.forward(from: 0);
    });
    if (onAnimationStart != null) SchedulerBinding.instance.addPostFrameCallback((_) => onAnimationStart());
    return true;
  }

  /// `animationElapsedTime`: easing(round(progress)) as JavascriptAnimation computes it.
  double get t {
    if (!_active) return 1;
    final v = controller.value;
    final progress = _beginFraction >= 1 ? 1.0 : ((v - _beginFraction) / (1 - _beginFraction)).clamp(0.0, 1.0);
    if (progress >= 1) return 1;
    return _easing(round4(progress));
  }

  /// The items to render this frame; records them as the next start snapshot.
  List<T>? step(List<T> Function(List<AnimationItem<T>>? items, double t) interpolateFn, {bool canCommit = true}) {
    final items = target;
    if (items == null) return null;
    final t = this.t;
    final stepData = interpolateFn(matchAnimationItems(_startSnapshot, items, matchBy), t);
    if (t == 0) {
      _readyToCommit = true;
    } else {
      if (t == 1) _startSnapshot = stepData;
      if (_readyToCommit && canCommit) _previousRendered = stepData;
    }
    return stepData;
  }

  void _cancelPendingStart() {
    if (_pendingStart != null) SchedulerBinding.instance.cancelFrameCallbackWithId(_pendingStart!);
    _pendingStart = null;
  }

  void dispose() {
    _cancelPendingStart();
    controller.dispose();
  }
}

/// `useAnimatedLineLength`.
class AnimatedLineLength {
  double _startingLength = 0;
  double _maxAnimatedLength = 0;
  bool _reachedFull = false;
  int _animationId = -1;

  double? visibleLength(int animationId, double t, double totalLength) {
    if (animationId != _animationId) {
      _startingLength = _maxAnimatedLength;
      _animationId = animationId;
    }
    if (_reachedFull) return null;
    final visible = math.min(round4(_startingLength + t * totalLength), totalLength);
    if (t > 0 && totalLength > 0) {
      _maxAnimatedLength = math.max(_maxAnimatedLength, visible);
      if (visible >= totalLength) {
        _reachedFull = true;
        return null;
      }
    }
    return visible;
  }
}

/// `getStrokeDasharray(length, totalLength, lines)` from LineDrawShape.tsx.
List<double> animatedStrokeDasharray(double length, double totalLength, List<double>? userLines) {
  if (userLines == null || userLines.isEmpty) return [length, totalLength];
  final lines = userLines.length.isOdd ? [...userLines, ...userLines] : userLines;
  final lineLength = lines.fold<double>(0, (a, b) => a + b);
  if (lineLength == 0) return [length, totalLength];
  final count = (length / lineLength).floor();
  final remainLength = length % lineLength;
  var remainLines = <double>[];
  var sum = 0.0;
  for (var i = 0; i < lines.length; sum += lines[i], i++) {
    if (sum + lines[i] > remainLength) {
      remainLines = [...lines.sublist(0, i), remainLength - sum];
      break;
    }
  }
  final emptyLines = remainLines.length.isEven ? [0.0, totalLength] : [totalLength];
  return [for (var i = 0; i < count; i++) ...lines, ...remainLines, ...emptyLines];
}
