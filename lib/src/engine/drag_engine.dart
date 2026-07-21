import 'package:flutter/foundation.dart';

import '../foundation/cell.dart';
import 'grid_metrics.dart';
import 'handles.dart';

/// Applies a side-handle drag to a shape: extends or retracts the single
/// row/column strip the handle sits on ("drag only part of the card out or
/// in"), quantized at 50% crossings by the caller.
///
/// Returns the original shape when the operation would leave the shape
/// empty, disconnected, or out of grid bounds beyond what can be clamped.
CardShape applyStripResize(
  CardShape shape,
  CellIndex handleCell,
  CardinalEdge edge,
  int steps,
  GridMetrics metrics,
) {
  if (steps == 0) return shape;
  final (dc, dr) = edge.outward;

  if (steps > 0) {
    final added = <CellIndex>[];
    for (var i = 1; i <= steps; i++) {
      final next = handleCell.translate(dc * i, dr * i);
      if (!metrics.cellInBounds(next)) break;
      if (shape.cells.contains(next)) continue;
      added.add(next);
    }
    if (added.isEmpty) return shape;
    return CardShape({...shape.cells, ...added});
  }

  // Retract: peel cells starting at the handle's strip end, moving inward.
  var current = shape;
  for (var i = 0; i < -steps; i++) {
    final target = handleCell.translate(-dc * (i), -dr * (i));
    if (!current.cells.contains(target)) break;
    if (current.cells.length <= 1) break;
    final candidate =
        CardShape(current.cells.where((c) => c != target));
    if (!candidate.isConnected) break;
    current = candidate;
  }
  return current;
}

/// The contiguous run of cells sharing the same open [edge] boundary as
/// [cell] — the straight edge segment a corner drag moves as one unit.
List<CellIndex> edgeSegment(CardShape shape, CellIndex cell, CardinalEdge edge) {
  final (dc, dr) = edge.outward;
  bool onEdge(CellIndex c) =>
      shape.cells.contains(c) && !shape.contains(c.col + dc, c.row + dr);
  assert(onEdge(cell));
  // Walk perpendicular to the edge normal in both directions.
  final (pc, pr) = edge.isHorizontalDrag ? (0, 1) : (1, 0);
  final run = [cell];
  for (var step = 1;; step++) {
    final next = cell.translate(pc * step, pr * step);
    if (!onEdge(next)) break;
    run.add(next);
  }
  for (var step = 1;; step++) {
    final prev = cell.translate(-pc * step, -pr * step);
    if (!onEdge(prev)) break;
    run.add(prev);
  }
  return run;
}

/// Applies a corner drag with standard corner rules: both full edge
/// segments that meet at the corner move, plus — when both axes extend —
/// the diagonal fill that keeps the corner square. Concave corners work the
/// same way; their two edge segments belong to different anchor cells and
/// pulling them outward fills the notch, so no diagonal fill applies.
CardShape applyCornerResize(
  CardShape shape,
  GridHandle handle,
  int hSteps,
  int vSteps,
  GridMetrics metrics,
) {
  final (hEdge, vEdge) = handle.axes;
  final hSegment = edgeSegment(shape, handle.cell, hEdge!);
  final vSegment = edgeSegment(shape, handle.cellV, vEdge!);

  var result = shape;
  for (final cell in hSegment) {
    result = applyStripResize(result, cell, hEdge, hSteps, metrics);
  }
  for (final cell in vSegment) {
    result = applyStripResize(result, cell, vEdge, vSteps, metrics);
  }

  if (hSteps > 0 && vSteps > 0 && !handle.concave) {
    final (hdc, _) = hEdge.outward;
    final (_, vdr) = vEdge.outward;
    final fill = <CellIndex>{};
    for (var i = 1; i <= hSteps; i++) {
      for (var j = 1; j <= vSteps; j++) {
        final cell = handle.cell.translate(hdc * i, vdr * j);
        if (metrics.cellInBounds(cell)) fill.add(cell);
      }
    }
    if (fill.isNotEmpty) result = CardShape({...result.cells, ...fill});
  }
  return result;
}

/// Applies a side-handle drag as an L-shaped gesture: [primarySteps] along
/// the edge's outward axis carve the new section (one strip per crossed
/// cell), and [perpSteps] then grow ONLY that new section perpendicularly —
/// the original card never changes. Dragging inward (negative primary)
/// stays a plain strip retract.
///
/// Example: on a 2x2 card, grab the east handle of the top row, drag right
/// 2 cells and up 1 — a 2x2 block appears merged onto the card's top-right.
CardShape applySideResize(
  CardShape shape,
  CellIndex handleCell,
  CardinalEdge edge,
  int primarySteps,
  int perpSteps,
  GridMetrics metrics,
) {
  if (primarySteps <= 0) {
    if (perpSteps == 0) {
      return applyStripResize(shape, handleCell, edge, primarySteps, metrics);
    }
    // Inward L-gesture (mirror of the outward carve below): retract |primarySteps| along the edge
    // normal AND deepen the notch |perpSteps| perpendicular, removing that whole block — not just
    // the single strip. Keeps the card connected (largest component) and never empties it.
    final (dc, dr) = edge.outward;
    final (pc, pr) =
        edge.isHorizontalDrag ? (0, perpSteps.sign) : (perpSteps.sign, 0);
    final removed = <CellIndex>{};
    for (var i = 0; i < -primarySteps; i++) {
      for (var j = 0; j <= perpSteps.abs(); j++) {
        removed.add(handleCell.translate(-dc * i + pc * j, -dr * i + pr * j));
      }
    }
    final remaining = shape.cells.where((c) => !removed.contains(c));
    if (remaining.isEmpty) return shape;
    final result = CardShape(remaining);
    return result.isConnected ? result : result.largestComponent;
  }
  final (dc, dr) = edge.outward;
  final (pc, pr) =
      edge.isHorizontalDrag ? (0, perpSteps.sign) : (perpSteps.sign, 0);
  final added = <CellIndex>{};
  for (var i = 1; i <= primarySteps; i++) {
    for (var j = 0; j <= perpSteps.abs(); j++) {
      final cell =
          handleCell.translate(dc * i + pc * j, dr * i + pr * j);
      if (metrics.cellInBounds(cell) && !shape.cells.contains(cell)) {
        added.add(cell);
      }
    }
  }
  if (added.isEmpty) return shape;
  return CardShape({...shape.cells, ...added});
}

/// Where a SMOTHERED submissive [shape] goes when it must run in [retreatDir], treating [blocked]
/// (the aggressor plus every OTHER card) as fixed — a runner never displaces another card. The
/// runner tactics, in order:
///   1. FULL space — the whole card fits somewhere along the retreat direction: relocate at size.
///   2. PARTIAL space — only part fits: keep the largest connected retreat-facing piece (the card
///      shrinks to fill the gap, aggressor-facing cells trimmed away).
///   3. NO space — return a single open cell adjacent (incl. diagonal) to the card, furthest toward
///      the retreat direction; or null when even that doesn't exist (the caller then drops a 1x1
///      into the aggressor, which cedes the cell).
CardShape? runnerShape(
  CardShape shape,
  Set<CellIndex> blocked,
  CardinalEdge retreatDir,
  GridMetrics metrics,
) {
  final (dc, dr) = retreatDir.outward;
  final maxStep = retreatDir.isHorizontalDrag ? metrics.columns : metrics.rows;
  CardShape? bestPartial;
  for (var step = 1; step <= maxStep; step++) {
    final cand = shape.translate(dc * step, dr * step);
    final inBounds = cand.cells.where(metrics.cellInBounds).toSet();
    if (inBounds.isEmpty) break; // slid fully off the grid
    final clear = inBounds.where((c) => !blocked.contains(c)).toSet();
    // 1. Whole card fits, in bounds and clear of everything.
    if (inBounds.length == shape.cells.length &&
        clear.length == shape.cells.length) {
      return cand;
    }
    // 2. Track the largest connected clear piece seen (the retreat-facing remainder).
    if (clear.isNotEmpty) {
      final piece = CardShape(clear).largestComponent;
      if (bestPartial == null ||
          piece.cells.length > bestPartial.cells.length) {
        bestPartial = piece;
      }
    }
  }
  if (bestPartial != null) return bestPartial;

  // 3. One open cell adjacent (8-neighbourhood) to the card, furthest toward the retreat direction.
  CellIndex? best;
  var bestScore = -1 << 30;
  for (final c in shape.cells) {
    for (var ec = -1; ec <= 1; ec++) {
      for (var er = -1; er <= 1; er++) {
        if (ec == 0 && er == 0) continue;
        final n = c.translate(ec, er);
        if (shape.cells.contains(n) ||
            blocked.contains(n) ||
            !metrics.cellInBounds(n)) {
          continue;
        }
        final score = n.col * dc + n.row * dr;
        if (score > bestScore) {
          bestScore = score;
          best = n;
        }
      }
    }
  }
  return best == null ? null : CardShape({best});
}

/// A submissive card's transient reaction to the aggressor.
@immutable
class SubmissiveState {
  const SubmissiveState({
    required this.entryEdge,
    required this.shape,
    required this.relocated,
  });

  /// The first edge of this card the aggressor came through. Recorded on
  /// first contact and kept for the rest of the drag session.
  final CardinalEdge entryEdge;

  /// The card's transient (deferred) shape while the aggressor overlaps it.
  final CardShape shape;

  /// True when the card had nothing left to cede and jumped to the side
  /// opposite the aggressor's approach.
  final bool relocated;
}

/// Trims [submissive] so it defers its entry-side edge to the aggressor's
/// cells: in every overlapped row (for horizontal entry) or column (for
/// vertical entry), cells from the entry side through the aggressor's far
/// edge are ceded. Returns null when nothing would remain (the < 1x1 case).
CardShape? trimSubmissive(
    CardShape submissive, Set<CellIndex> aggressor, CardinalEdge entryEdge) {
  final removed = <CellIndex>{};
  final overlap = submissive.cells.intersection(aggressor);
  switch (entryEdge) {
    case CardinalEdge.west || CardinalEdge.east:
      final overlappedRows = {for (final c in overlap) c.row};
      for (final row in overlappedRows) {
        final aggressorCols =
            aggressor.where((c) => c.row == row).map((c) => c.col);
        if (aggressorCols.isEmpty) continue;
        final far = entryEdge == CardinalEdge.west
            ? aggressorCols.reduce((a, b) => a > b ? a : b)
            : aggressorCols.reduce((a, b) => a < b ? a : b);
        removed.addAll(submissive.cells.where((s) =>
            s.row == row &&
            (entryEdge == CardinalEdge.west ? s.col <= far : s.col >= far)));
      }
    case CardinalEdge.north || CardinalEdge.south:
      final overlappedCols = {for (final c in overlap) c.col};
      for (final col in overlappedCols) {
        final aggressorRows =
            aggressor.where((c) => c.col == col).map((c) => c.row);
        if (aggressorRows.isEmpty) continue;
        final far = entryEdge == CardinalEdge.north
            ? aggressorRows.reduce((a, b) => a > b ? a : b)
            : aggressorRows.reduce((a, b) => a < b ? a : b);
        removed.addAll(submissive.cells.where((s) =>
            s.col == col &&
            (entryEdge == CardinalEdge.north ? s.row <= far : s.row >= far)));
      }
  }
  final remaining = submissive.cells.difference(removed);
  if (remaining.isEmpty) return null;
  final result = CardShape(remaining);
  return result.isConnected ? result : result.largestComponent;
}

/// Finds the minimal translation of [shape] in [direction] (the aggressor's
/// travel direction, i.e. opposite its entry edge into the card) that clears
/// [blocked] and stays in bounds. Returns null when no translation fits.
CardShape? relocateBeyond(
  CardShape shape,
  Set<CellIndex> blocked,
  CardinalEdge direction,
  GridMetrics metrics,
) {
  final (dc, dr) = direction.outward;
  final maxSteps =
      direction.isHorizontalDrag ? metrics.columns : metrics.rows;
  for (var step = 1; step <= maxSteps; step++) {
    final candidate = shape.translate(dc * step, dr * step);
    final inBounds = candidate.cells.every(metrics.cellInBounds);
    if (!inBounds) return null;
    if (!candidate.cells.any(blocked.contains)) return candidate;
  }
  return null;
}
