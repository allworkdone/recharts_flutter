// The registry behind `syncId` (src/synchronisation: the eventCenter and
// TOOLTIP_SYNC_EVENT of useTooltipChartSynchronisation.ts and
// useSynchronisedEventsFromOtherCharts.ts, `syncMethod="index"`): charts with
// the same id, cartesian or polar, share the active tooltip index, and
// cartesian charts with a Brush share its range.

import 'dart:ui';

import '../engine/polar_scene.dart' show PolarCoordinate;

/// A chart taking part in `syncId`.
abstract interface class TooltipSyncPeer {
  bool get mounted;

  /// The tooltip state of another chart: [coordinate] is in that chart's
  /// [sourceViewBox] and is mapped onto this one's.
  ///
  /// [polar] is a polar chart's coordinate with its polar parts; only x and y are rescaled, so a polar
  /// receiver draws its cursor from it. Cartesian charts ignore it.
  void receiveTooltipSync(
      bool active, int? index, Offset? coordinate, Object? dataKey, Rect sourceViewBox, PolarCoordinate? polar);

  /// The Brush range of another chart; charts without a Brush ignore it.
  void receiveBrushSync(({int startIndex, int endIndex}) range);
}

final Map<Object, Set<TooltipSyncPeer>> _groups = {};

void joinSyncGroup(Object id, TooltipSyncPeer peer) => _groups.putIfAbsent(id, () => {}).add(peer);

void leaveSyncGroup(Object id, TooltipSyncPeer peer) {
  _groups[id]?.remove(peer);
  if (_groups[id]?.isEmpty ?? false) _groups.remove(id);
}

/// The other charts of group [id].
List<TooltipSyncPeer> syncPeers(Object id, TooltipSyncPeer self) => [
      for (final p in _groups[id] ?? const <TooltipSyncPeer>{})
        if (!identical(p, self)) p,
    ];
