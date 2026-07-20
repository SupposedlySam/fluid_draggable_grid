import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../foundation/cell.dart';
import 'grid_metrics.dart';

/// One grabbable resize affordance on a card edge or corner.
///
/// Side handles sit at the midpoint of every open cell edge (one per grid
/// unit the edge spans — gap midpoints fall on the same centers since the
/// pitch covers cell + gap). Corner handles sit at every convex corner
/// (pulled inward along the diagonal to account for the outside corner
/// radius) and at every concave corner (nudged into the notch to hug the
/// inside radius); both kinds drive standard both-axes corner resizes.
@immutable
class GridHandle {
  const GridHandle({
    required this.cardId,
    required this.cell,
    required this.center,
    required this.hitRadius,
    this.edge,
    this.corner,
    CellIndex? cellV,
    this.concave = false,
  })  : cellV = cellV ?? cell,
        assert((edge == null) != (corner == null),
            'A handle is either a side or a corner');

  final String cardId;

  /// Anchor cell for the horizontal-axis edge segment (and the only anchor
  /// for side handles and convex corners).
  final CellIndex cell;

  /// Anchor cell for the vertical-axis edge segment. Concave corners join
  /// two edges belonging to different cells; convex corners use [cell].
  final CellIndex cellV;

  /// True for inside (concave) corner handles.
  final bool concave;

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

  /// How far a handle's grab zone reaches into the card interior. The
  /// outside half of the zone (over the gap) is fully grabbable, but inward
  /// reach is capped so pressing card *content* near an edge grabs the card
  /// body (move) instead of silently starting a resize.
  static const double interiorReach = 12.0;

  /// Unit vector pointing away from the card interior: the edge normal for
  /// sides, the corner diagonal for convex corners, and the notch diagonal
  /// for concave corners.
  Offset get outwardUnit {
    if (edge != null) {
      return switch (edge!) {
        CardinalEdge.north => const Offset(0, -1),
        CardinalEdge.east => const Offset(1, 0),
        CardinalEdge.south => const Offset(0, 1),
        CardinalEdge.west => const Offset(-1, 0),
      };
    }
    return switch (corner!) {
      CornerKind.northWest => const Offset(-0.7071, -0.7071),
      CornerKind.northEast => const Offset(0.7071, -0.7071),
      CornerKind.southEast => const Offset(0.7071, 0.7071),
      CornerKind.southWest => const Offset(-0.7071, 0.7071),
    };
  }

  bool hits(Offset point) {
    final delta = point - center;
    if (delta.distance > hitRadius) return false;
    final outwardDepth =
        delta.dx * outwardUnit.dx + delta.dy * outwardUnit.dy;
    return outwardDepth >= -interiorReach;
  }

  String get debugLabel =>
      '${edge?.name ?? corner!.name}@$cell of $cardId';

  @override
  bool operator ==(Object other) =>
      other is GridHandle &&
      other.cardId == cardId &&
      other.cell == cell &&
      other.cellV == cellV &&
      other.edge == edge &&
      other.corner == corner &&
      other.concave == concave &&
      other.center == center;

  @override
  int get hashCode =>
      Object.hash(cardId, cell, cellV, edge, corner, concave, center);
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

    // Concave corners: two perpendicular neighbors present, diagonal
    // missing. The two boundary edges meeting at the notch belong to those
    // neighbors: the vertical neighbor carries the horizontal-axis edge and
    // the horizontal neighbor carries the vertical-axis edge. The grab
    // center sits on the notch vertex, nudged into the notch to hug the
    // inside corner radius.
    final concavePull = metrics.config.insideCornerRadius * 0.3 + 2;
    void addConcave(CornerKind kind, CellIndex vNeighbor, CellIndex hNeighbor,
        CellIndex diagonal, Offset notchDiagonal) {
      final present = shape.cells.contains(vNeighbor) &&
          shape.cells.contains(hNeighbor) &&
          !shape.cells.contains(diagonal);
      if (!present) return;
      final hRect = metrics.cellRect(vNeighbor);
      final vRect = metrics.cellRect(hNeighbor);
      final vertex = switch (kind) {
        CornerKind.northEast => Offset(hRect.right, vRect.top),
        CornerKind.southEast => Offset(hRect.right, vRect.bottom),
        CornerKind.southWest => Offset(hRect.left, vRect.bottom),
        CornerKind.northWest => Offset(hRect.left, vRect.top),
      };
      handles.add(GridHandle(
        cardId: cardId,
        cell: vNeighbor,
        cellV: hNeighbor,
        corner: kind,
        concave: true,
        center: vertex + notchDiagonal * concavePull,
        hitRadius: hitRadius,
      ));
    }

    final north = cell.translate(0, -1);
    final east = cell.translate(1, 0);
    final south = cell.translate(0, 1);
    final west = cell.translate(-1, 0);
    addConcave(CornerKind.northEast, north, east, cell.translate(1, -1),
        const Offset(0.7071, -0.7071));
    addConcave(CornerKind.southEast, south, east, cell.translate(1, 1),
        const Offset(0.7071, 0.7071));
    addConcave(CornerKind.southWest, south, west, cell.translate(-1, 1),
        const Offset(-0.7071, 0.7071));
    addConcave(CornerKind.northWest, north, west, cell.translate(-1, -1),
        const Offset(-0.7071, -0.7071));
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
