import 'package:flutter/foundation.dart';

/// Where the gallery puts the tooltip card relative to the pointer. Parity
/// mode never uses this: it renders fixtures exactly as Recharts would.
enum TooltipMode {
  /// Recharts' default: 10px right of and below the pointer, flipping near edges.
  below('Below (Recharts)', {}),

  /// Above the finger, dropping below only when there is no room.
  above('Above finger', {
    'reverseDirection': {'x': false, 'y': true},
    'offset': 16,
  }),

  /// Pinned to the chart's top edge while following the pointer sideways.
  pinnedTop('Pinned top', {
    'position': {'y': 0},
  });

  const TooltipMode(this.label, this.props);
  final String label;
  final Map<String, Object> props;

  /// A finger covers whatever sits just below it, so touch platforms start above.
  static TooltipMode get platformDefault =>
      defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS
          ? TooltipMode.above
          : TooltipMode.below;
}

/// A copy of [node] (a fixture or any part of it) with [mode]'s props merged
/// into every `Tooltip` element.
Object? withTooltipMode(Object? node, TooltipMode mode) => switch (node) {
      final Map m when m['type'] == 'Tooltip' => <String, dynamic>{
          ...m.cast<String, dynamic>(),
          'props': <String, dynamic>{...?(m['props'] as Map?)?.cast<String, dynamic>(), ...mode.props},
        },
      final Map m => <String, dynamic>{for (final e in m.entries) e.key as String: withTooltipMode(e.value, mode)},
      final List l => <dynamic>[for (final e in l) withTooltipMode(e, mode)],
      _ => node,
    };
