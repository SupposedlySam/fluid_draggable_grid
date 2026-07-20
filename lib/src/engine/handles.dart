import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../foundation/cell.dart';
import 'grid_metrics.dart';
import 'outline_cache.dart';

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
    double? interiorReach,
    double? outwardReach,
    double? tangentReach,
  })  : cellV = cellV ?? cell,
        interiorReach = interiorReach ?? defaultInteriorReach,
        outwardReach = outwardReach ?? hitRadius,
        tangentReach = tangentReach ?? hitRadius,
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

  /// Default inward reach of a grab zone, measured from the card edge:
  /// capped so pressing card *content* near an edge grabs the card body
  /// (move) instead of silently starting a resize.
  static const double defaultInteriorReach = 12.0;

  /// How far the grab zone reaches into the card interior from [center].
  final double interiorReach;

  /// How far the grab zone reaches outward past [center] (into the gap or
  /// empty cells). Card ownership is resolved by containment first (see
  /// [interactionAt]), so generous outward reach never steals presses from
  /// inside an adjacent card.
  final double outwardReach;

  /// Reach along the edge direction. Side handles cover their *entire* cell
  /// edge (the visible circle at the midpoint is the affordance; the whole
  /// edge is grabbable); corners use their circular radius.
  final double tangentReach;

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
    final outwardDepth =
        delta.dx * outwardUnit.dx + delta.dy * outwardUnit.dy;
    if (outwardDepth > outwardReach || outwardDepth < -interiorReach) {
      return false;
    }
    final tangentDelta = delta - outwardUnit * outwardDepth;
    return tangentDelta.distance <= tangentReach;
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
  // Side handles cover their whole cell edge plus half the bridged gap on
  // each side, so adjacent strips' zones meet exactly at gap midlines and
  // a multi-cell edge has no dead spots.
  final sideTangentReach = (metrics.cellExtent + metrics.gap) / 2;

  for (final cell in shape.cells) {
    final rect = metrics.cellRect(cell);
    final open = {
      for (final edge in CardinalEdge.values)
        edge: !shape.cells.contains(
            cell.translate(edge.outward.$1, edge.outward.$2)),
    };

    void addSide(CardinalEdge edge, Offset center) {
      if (!open[edge]!) return;
      handles.add(GridHandle(
        cardId: cardId,
        cell: cell,
        edge: edge,
        center: center,
        hitRadius: hitRadius,
        tangentReach: sideTangentReach,
      ));
    }

    addSide(CardinalEdge.north, rect.topCenter);
    addSide(CardinalEdge.south, rect.bottomCenter);
    addSide(CardinalEdge.east, rect.centerRight);
    addSide(CardinalEdge.west, rect.centerLeft);

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
          // The center sits pulled inward from the corner: compensate both
          // reaches so the entire visible disc responds — its inner half
          // resizes instead of falling through to a card move.
          interiorReach: GridHandle.defaultInteriorReach + pull,
          outwardReach: hitRadius + pull,
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
        interiorReach: GridHandle.defaultInteriorReach + concavePull,
        outwardReach: hitRadius + concavePull,
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

/// Resolves what a pointer at [point] grabs, honoring card ownership:
///
/// 1. The card whose outline *contains* the point owns it — its edge-band
///    handles win near the edge, its body (a move) everywhere else. A
///    neighbor's handle can never steal a press from inside a card.
/// 2. When no card contains the point (gutters, empty cells), every card's
///    outward handle zones compete and the nearest wins — so in the gap
///    between two adjacent cards, each card's handle is grabbable on its
///    own side of the gutter's midline.
(String cardId, GridHandle? handle)? interactionAt(
  Offset point,
  List<(String, CardShape)> cardsTopFirst,
  GridMetrics metrics,
) {
  for (final (id, shape) in cardsTopFirst) {
    final contains = OutlineCache.instance
        .outlineFor(shape, metrics)
        .paths
        .contains(point);
    if (contains) {
      return (id, hitTestHandles(handlesFor(id, shape, metrics), point));
    }
  }
  GridHandle? best;
  var bestScore = double.infinity;
  for (final (id, shape) in cardsTopFirst) {
    for (final handle in handlesFor(id, shape, metrics)) {
      if (!handle.hits(point)) continue;
      final distance = (point - handle.center).distance;
      final score = handle.isCorner ? distance - 1000 : distance;
      if (score < bestScore) {
        bestScore = score;
        best = handle;
      }
    }
  }
  return best == null ? null : (best.cardId, best);
}
