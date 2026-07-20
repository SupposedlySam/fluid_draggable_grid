import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../foundation/cell.dart';
import 'grid_metrics.dart';

/// One grabbable resize affordance on a card edge or corner.
///
/// Side handles sit at the midpoint of every open cell edge (one per grid
/// unit the edge spans — gap midpoints fall on the same centers since the
/// pitch covers cell + gap). Corner handles sit at every convex corner,
/// pulled inward along the diagonal to account for the outside corner
/// radius.
@immutable
class GridHandle {
  const GridHandle({
    required this.cardId,
    required this.cell,
    required this.center,
    required this.hitRadius,
    this.edge,
    this.corner,
  }) : assert((edge == null) != (corner == null),
            'A handle is either a side or a corner');

  final String cardId;

  /// The card cell this handle belongs to.
  final CellIndex cell;

  /// Content-space center of the grab region.
  final Offset center;

  final double hitRadius;

  /// Set for side handles.
  final CardinalEdge? edge;

  /// Set for corner handles.
  final CornerKind? corner;

  bool get isCorner => corner != null;

  /// Outward drag directions as (horizontal, vertical). Sides report one
  /// axis; corners report both.
  (CardinalEdge?, CardinalEdge?) get axes {
    if (edge != null) {
      return edge!.isHorizontalDrag ? (edge, null) : (null, edge);
    }
    return switch (corner!) {
      CornerKind.northWest => (CardinalEdge.west, CardinalEdge.north),
      CornerKind.northEast => (CardinalEdge.east, CardinalEdge.north),
      CornerKind.southEast => (CardinalEdge.east, CardinalEdge.south),
      CornerKind.southWest => (CardinalEdge.west, CardinalEdge.south),
    };
  }

  bool hits(Offset point) => (point - center).distance <= hitRadius;

  String get debugLabel =>
      '${edge?.name ?? corner!.name}@$cell of $cardId';

  @override
  bool operator ==(Object other) =>
      other is GridHandle &&
      other.cardId == cardId &&
      other.cell == cell &&
      other.edge == edge &&
      other.corner == corner &&
      other.center == center;

  @override
  int get hashCode => Object.hash(cardId, cell, edge, corner, center);
}

/// Computes the handles for one card shape.
List<GridHandle> handlesFor(
    String cardId, CardShape shape, GridMetrics metrics) {
  final handles = <GridHandle>[];
  final hitRadius = (metrics.cellExtent * 0.38).clamp(12.0, 26.0);
  final outsideRadius = metrics.config.outsideCornerRadius;

  for (final cell in shape.cells) {
    final rect = metrics.cellRect(cell);
    final open = {
      for (final edge in CardinalEdge.values)
        edge: !shape.cells.contains(
            cell.translate(edge.outward.$1, edge.outward.$2)),
    };

    if (open[CardinalEdge.north]!) {
      handles.add(GridHandle(
        cardId: cardId,
        cell: cell,
        edge: CardinalEdge.north,
        center: rect.topCenter,
        hitRadius: hitRadius,
      ));
    }
    if (open[CardinalEdge.south]!) {
      handles.add(GridHandle(
        cardId: cardId,
        cell: cell,
        edge: CardinalEdge.south,
        center: rect.bottomCenter,
        hitRadius: hitRadius,
      ));
    }
    if (open[CardinalEdge.east]!) {
      handles.add(GridHandle(
        cardId: cardId,
        cell: cell,
        edge: CardinalEdge.east,
        center: rect.centerRight,
        hitRadius: hitRadius,
      ));
    }
    if (open[CardinalEdge.west]!) {
      handles.add(GridHandle(
        cardId: cardId,
        cell: cell,
        edge: CardinalEdge.west,
        center: rect.centerLeft,
        hitRadius: hitRadius,
      ));
    }

    // Convex corners: two adjacent open sides. Pull the grab center inward
    // along the diagonal by ~the outside corner radius so the affordance
    // hugs the rounded corner arc.
    final pull = outsideRadius * 0.3;
    void addCorner(CornerKind kind, CardinalEdge a, CardinalEdge b,
        Offset cornerPoint, Offset inwardDiagonal) {
      if (open[a]! && open[b]!) {
        handles.add(GridHandle(
          cardId: cardId,
          cell: cell,
          corner: kind,
          center: cornerPoint + inwardDiagonal * pull,
          hitRadius: hitRadius,
        ));
      }
    }

    addCorner(CornerKind.northWest, CardinalEdge.north, CardinalEdge.west,
        rect.topLeft, const Offset(0.7071, 0.7071));
    addCorner(CornerKind.northEast, CardinalEdge.north, CardinalEdge.east,
        rect.topRight, const Offset(-0.7071, 0.7071));
    addCorner(CornerKind.southEast, CardinalEdge.south, CardinalEdge.east,
        rect.bottomRight, const Offset(-0.7071, -0.7071));
    addCorner(CornerKind.southWest, CardinalEdge.south, CardinalEdge.west,
        rect.bottomLeft, const Offset(0.7071, -0.7071));
  }
  return handles;
}

/// Finds the best handle under [point]: corners win over sides, then the
/// nearest center wins.
GridHandle? hitTestHandles(List<GridHandle> handles, Offset point) {
  GridHandle? best;
  var bestScore = double.infinity;
  for (final handle in handles) {
    if (!handle.hits(point)) continue;
    final distance = (point - handle.center).distance;
    final score = handle.isCorner ? distance - 1000 : distance;
    if (score < bestScore) {
      bestScore = score;
      best = handle;
    }
  }
  return best;
}
