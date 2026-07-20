import 'package:flutter/foundation.dart';

/// A single grid cell address (column, row).
@immutable
class CellIndex {
  const CellIndex(this.col, this.row);

  final int col;
  final int row;

  CellIndex translate(int dc, int dr) => CellIndex(col + dc, row + dr);

  List<int> toJson() => [col, row];

  static CellIndex fromJson(List<dynamic> json) =>
      CellIndex(json[0] as int, json[1] as int);

  @override
  bool operator ==(Object other) =>
      other is CellIndex && other.col == col && other.row == row;

  @override
  int get hashCode => Object.hash(col, row);

  @override
  String toString() => '($col,$row)';
}

/// A cardinal edge of a cell or card.
enum CardinalEdge {
  north,
  east,
  south,
  west;

  bool get isHorizontalDrag => this == east || this == west;

  CardinalEdge get opposite => switch (this) {
        north => south,
        east => west,
        south => north,
        west => east,
      };

  /// Unit cell step outward through this edge.
  (int, int) get outward => switch (this) {
        north => (0, -1),
        east => (1, 0),
        south => (0, 1),
        west => (-1, 0),
      };
}

/// A corner of a card outline.
enum CornerKind { northWest, northEast, southEast, southWest }

/// An immutable set of grid cells describing the footprint of one card.
///
/// Shapes are not constrained to rectangles: dragging a side handle extends
/// or retracts a single row/column strip, producing polyomino shapes. The
/// cell coordinates are absolute grid coordinates, so a shape encodes both
/// the card's position and its silhouette.
@immutable
class CardShape {
  CardShape(Iterable<CellIndex> cells) : cells = Set.unmodifiable(cells) {
    assert(this.cells.isNotEmpty, 'A CardShape must contain at least 1 cell');
  }

  /// A `width x height` rectangle anchored at (col, row).
  factory CardShape.rect(int col, int row, int width, int height) {
    assert(width > 0 && height > 0);
    return CardShape([
      for (var c = col; c < col + width; c++)
        for (var r = row; r < row + height; r++) CellIndex(c, r),
    ]);
  }

  final Set<CellIndex> cells;

  bool contains(int col, int row) => cells.contains(CellIndex(col, row));

  int get minCol => cells.map((c) => c.col).reduce((a, b) => a < b ? a : b);
  int get maxCol => cells.map((c) => c.col).reduce((a, b) => a > b ? a : b);
  int get minRow => cells.map((c) => c.row).reduce((a, b) => a < b ? a : b);
  int get maxRow => cells.map((c) => c.row).reduce((a, b) => a > b ? a : b);

  CardShape translate(int dc, int dr) =>
      CardShape(cells.map((c) => c.translate(dc, dr)));

  bool overlaps(CardShape other) => cells.any(other.cells.contains);

  Set<CellIndex> intersection(CardShape other) =>
      cells.intersection(other.cells);

  /// Whether every cell is reachable from every other via edge adjacency.
  bool get isConnected {
    final visited = <CellIndex>{cells.first};
    final frontier = [cells.first];
    while (frontier.isNotEmpty) {
      final cell = frontier.removeLast();
      for (final (dc, dr) in const [(0, -1), (1, 0), (0, 1), (-1, 0)]) {
        final next = cell.translate(dc, dr);
        if (cells.contains(next) && visited.add(next)) frontier.add(next);
      }
    }
    return visited.length == cells.length;
  }

  /// The largest edge-connected component of [cells]. Used when a transient
  /// trim splits a shape: the biggest island survives, ties broken by
  /// top-left-most cell for determinism.
  CardShape get largestComponent {
    final remaining = Set.of(cells);
    Set<CellIndex>? best;
    while (remaining.isNotEmpty) {
      final seed = remaining.first;
      final component = <CellIndex>{seed};
      final frontier = [seed];
      while (frontier.isNotEmpty) {
        final cell = frontier.removeLast();
        for (final (dc, dr) in const [(0, -1), (1, 0), (0, 1), (-1, 0)]) {
          final next = cell.translate(dc, dr);
          if (remaining.contains(next) && component.add(next)) {
            frontier.add(next);
          }
        }
      }
      remaining.removeAll(component);
      if (best == null || component.length > best.length) best = component;
    }
    return CardShape(best!);
  }

  /// Cells of the maximal contiguous horizontal run in [row] that includes
  /// [col]. Used for east/west strip resizing.
  List<CellIndex> rowRun(int col, int row) {
    assert(contains(col, row));
    var start = col;
    while (contains(start - 1, row)) {
      start--;
    }
    var end = col;
    while (contains(end + 1, row)) {
      end++;
    }
    return [for (var c = start; c <= end; c++) CellIndex(c, row)];
  }

  /// Cells of the maximal contiguous vertical run in [col] that includes
  /// [row]. Used for north/south strip resizing.
  List<CellIndex> colRun(int col, int row) {
    assert(contains(col, row));
    var start = row;
    while (contains(col, start - 1)) {
      start--;
    }
    var end = row;
    while (contains(col, end + 1)) {
      end++;
    }
    return [for (var r = start; r <= end; r++) CellIndex(col, r)];
  }

  List<List<int>> toJson() {
    final sorted = cells.toList()
      ..sort((a, b) => a.row != b.row ? a.row - b.row : a.col - b.col);
    return [for (final c in sorted) c.toJson()];
  }

  static CardShape fromJson(List<dynamic> json) => CardShape(
      [for (final c in json) CellIndex.fromJson(c as List<dynamic>)]);

  @override
  bool operator ==(Object other) =>
      other is CardShape && setEquals(other.cells, cells);

  @override
  int get hashCode => Object.hashAllUnordered(cells);

  @override
  String toString() => 'CardShape(${cells.length} cells, '
      'bounds: $minCol..$maxCol x $minRow..$maxRow)';
}
