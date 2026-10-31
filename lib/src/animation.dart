// Ports of src/animation/matchBy.ts, AnimatedItems.tsx (+ useAnimationStartSnapshot.ts),
// JavascriptAnimate.tsx / AnimationHandle.ts timing, the default interpolators
// of Line.tsx, Bar.tsx, Area.tsx (with Area's baseLine animation from
// AreaWithAnimation) and Scatter.tsx, src/cartesian/useAnimatedLineLength.ts,
// and ErrorBar.tsx's CSSTransitionAnimate scale.

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

/// `defaultAreaAnimateItems`: added points are drawn at once (the entrance is
/// AreaRevealShape's clip), removed ones are dropped.
List<LinePoint> interpolateAreaPoints(List<AnimationItem<LinePoint>>? items, double t) {
  if (items == null) return const [];
  return [
    for (final i in items)
      switch (i) {
        Matched(:final prev, :final next) => t == 1
            ? next
            : LinePoint(interpolate(prev.x, next.x, t), interpolate(prev.y, next.y, t), next.value, next.payload),
        Added(:final next) => next,
        Removed() => null,
      },
  ].nonNulls.toList();
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

/// `defaultScatterAnimateItems`: points move, added ones grow from size 0,
/// removed ones vanish at once.
List<ScatterPoint> interpolateScatterPoints(List<AnimationItem<ScatterPoint>>? items, double t) {
  if (items == null) return const [];
  return [
    for (final i in items)
      switch (i) {
        Matched(:final prev, :final next) => t == 1
            ? next
            : next.step(next.cx == null ? null : interpolate(prev.cx, next.cx, t),
                next.cy == null ? null : interpolate(prev.cy, next.cy, t), interpolate(prev.size, next.size, t)),
        Added(:final next) => t == 1 ? next : next.step(next.cx, next.cy, interpolate(0, next.size, t)),
        Removed() => null,
      },
  ].nonNulls.toList();
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
  VoidCallback? onAnimationEnd;

  List<T>? target;
  Object? _targetKey;
  List<T>? _startSnapshot;
  List<T>? _previousRendered;
  bool _readyToCommit = true;
  int? _pendingStart;

  /// Bumps when a new animation input arrives (`useAnimationId`).
  int animationId = 0;

  /// `useAnimationCallbacks().isAnimating`.
  bool get isAnimating => _running;

  /// AnimatedItems' `isEntrance`: nothing was rendered before this cycle.
  bool get isEntrance => _startSnapshot == null;

  /// Returns true when a new animation cycle started. A change of [key] (by
  /// value, lists element-wise) also starts one: Area's input is its points
  /// and baseLine.
  bool update(
    List<T>? items, {
    required bool active,
    required int begin,
    required int duration,
    required Object easing,
    VoidCallback? onAnimationStart,
    VoidCallback? onAnimationEnd,
    Object? key,
  }) {
    this.onAnimationEnd = onAnimationEnd;
    _easing = createEasingFunction(easing) ?? _easing;
    final sameKey = key is List && _targetKey is List ? listEquals(key, _targetKey as List) : key == _targetKey;
    _targetKey = key;
    if (target != null && items != null && listEquals(items, target) && sameKey) {
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
    controller.duration = Duration(milliseconds: math.max(1, duration));
    _running = true;
    // AnimationHandle.tick moves INIT -> PENDING on the frame that mounts the
    // item and PENDING -> ACTIVE (progress 0) on the first later frame at
    // least `begin` ms after it. Starting the ticker from that frame's
    // callback gives the same timeline.
    controller.value = 0;
    final id = animationId;
    final binding = SchedulerBinding.instance;
    final pendingSince = binding.schedulerPhase == SchedulerPhase.idle ? null : binding.currentFrameTimeStamp;
    final beginTime = Duration(milliseconds: math.max(0, begin));
    void tick(Duration now) {
      _pendingStart = null;
      if (!_running || id != animationId) return;
      if (now - (pendingSince ?? now) < beginTime) {
        _pendingStart = binding.scheduleFrameCallback(tick);
        return;
      }
      controller.forward(from: 0);
    }

    _pendingStart = binding.scheduleFrameCallback(tick);
    if (onAnimationStart != null) SchedulerBinding.instance.addPostFrameCallback((_) => onAnimationStart());
    return true;
  }

  /// `animationElapsedTime`: easing(round(progress)) as JavascriptAnimation computes it.
  double get t {
    if (!_active) return 1;
    final progress = controller.value;
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

  /// What [step] renders now, without recording it (extra layers, hit tests).
  List<T>? peek(List<T> Function(List<AnimationItem<T>>? items, double t) interpolateFn) =>
      target == null ? null : interpolateFn(matchAnimationItems(_startSnapshot, target, matchBy), t);

  void _cancelPendingStart() {
    if (_pendingStart != null) SchedulerBinding.instance.cancelFrameCallbackWithId(_pendingStart!);
    _pendingStart = null;
  }

  void dispose() {
    _cancelPendingStart();
    controller.dispose();
  }
}

/// Area's baseLine through an animation cycle: its own
/// `useAnimationStartSnapshot` and the step of AreaWithAnimation.
class AreaBaseLineAnimation {
  Object? _previous;
  Object? _startValue;
  bool _readyToCommit = true;

  /// A new animation cycle started (the animator restarted).
  void restart() {
    _startValue = _previous;
    _readyToCommit = false;
  }

  /// The baseLine to draw at [t]: a number or a list of [LinePoint]s.
  Object step(Object baseLine, double t, {required bool isEntrance}) {
    final prev = _startValue;
    final Object stepBaseLine;
    if (t == 1) {
      stepBaseLine = baseLine;
    } else if (baseLine is List<LinePoint>) {
      stepBaseLine = interpolateAreaPoints(
          matchAnimationItems(prev is List<LinePoint> ? prev : null, baseLine, MatchBy.byIndex), t);
    } else {
      stepBaseLine = isEntrance ? baseLine : _interpolateScalarBaseLine(baseLine as double, prev, t);
    }
    // syncStepValue
    if (t == 0) {
      _readyToCommit = true;
    } else {
      if (t == 1) _startValue = stepBaseLine;
      if (_readyToCommit) _previous = stepBaseLine;
    }
    return stepBaseLine;
  }

  /// `interpolateScalarBaseLine`.
  static double _interpolateScalarBaseLine(double baseLine, Object? prev, double t) {
    final from = prev is double && !prev.isNaN ? prev : null;
    return interpolate(from, baseLine.isNaN ? 0 : baseLine, t)!;
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

/// ErrorBar's `CSSTransitionAnimate`: each new line goes from `scaleX|Y(0)` to
/// `(1)` around its origin, a CSS transition that starts with the series
/// animations (the handle's ACTIVE frame). Lines keep their scale while their
/// key (coordinates) stays.
// ponytail: one clock per ErrorBar; a line still scaling when other lines
// appear jumps to full size.
class ErrorBarAnimation {
  ErrorBarAnimation(TickerProvider vsync) : controller = AnimationController(vsync: vsync);
  final AnimationController controller;
  Set<String> _keys = {};
  Set<String> _animating = {};
  EasingFunction _easing = (t) => t;
  double _beginFraction = 0;
  int? _pendingStart;

  void update(Set<String> keys, {required bool active, required int begin, required int duration, required Object easing}) {
    final added = keys.difference(_keys);
    _keys = keys;
    if (!active) {
      _animating = {};
      return;
    }
    if (added.isEmpty) return;
    _animating = added;
    _easing = createEasingFunction(easing) ?? _easing;
    final int total = math.max(0, begin) + math.max(0, duration);
    _beginFraction = total == 0 ? 0 : math.max(0, begin) / total;
    controller.duration = Duration(milliseconds: total == 0 ? 1 : total);
    controller.value = 0;
    if (_pendingStart != null) SchedulerBinding.instance.cancelFrameCallbackWithId(_pendingStart!);
    // Starts a frame late, like SeriesAnimator.
    _pendingStart = SchedulerBinding.instance.scheduleFrameCallback((_) {
      _pendingStart = null;
      controller.forward(from: 0);
    });
  }

  /// The scale of the line with [key] now.
  double scaleOf(String key) {
    if (!_animating.contains(key)) return 1;
    final v = controller.value;
    final progress = _beginFraction >= 1 ? 1.0 : ((v - _beginFraction) / (1 - _beginFraction)).clamp(0.0, 1.0);
    return progress >= 1 ? 1 : _easing(progress);
  }

  void dispose() {
    if (_pendingStart != null) SchedulerBinding.instance.cancelFrameCallbackWithId(_pendingStart!);
    controller.dispose();
  }
}
