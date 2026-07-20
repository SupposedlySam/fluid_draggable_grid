import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../foundation/cell.dart';
import '../foundation/config.dart';

/// Resolved pixel geometry for one viewport size.
///
/// The grid uses square units. The config's column/row counts are minimums:
/// when the viewport fits more units at [FluidGridConfig.maxCellExtent],
/// the field grows to fill it. Cell extent flexes between the config's min
/// and max; when even the minimum count can't fit at [minCellExtent], the
/// content overflows and pans.
@immutable
class GridMetrics {
  const GridMetrics._({
    required this.config,
    required this.cellExtent,
    required this.viewportSize,
    required this.columns,
    required this.rows,
  });

  /// [minColumns]/[minRows] extend the field to cover occupied cells, so a
  /// card placed on a wide window can never fall outside the pannable area
  /// when the window shrinks.
  factory GridMetrics.resolve(
    FluidGridConfig config,
    Size viewportSize, {
    int minColumns = 0,
    int minRows = 0,
  }) {
    int unitsThatFit(double viewportExtent) =>
        ((viewportExtent - config.gap) /
                (config.maxCellExtent + config.gap))
            .floor();
    final columns = math.max(math.max(config.columns, minColumns),
        unitsThatFit(viewportSize.width));
    final rows = math.max(math.max(config.rows, minRows),
        unitsThatFit(viewportSize.height));
    final available = viewportSize.width - config.gap * (columns + 1);
    final ideal = available / columns;
    final extent =
        ideal.clamp(config.minCellExtent, config.maxCellExtent).toDouble();
    return GridMetrics._(
      config: config,
      cellExtent: extent,
      viewportSize: viewportSize,
      columns: columns,
      rows: rows,
    );
  }

  final FluidGridConfig config;
  final double cellExtent;
  final Size viewportSize;

  /// Effective grid dimensions: config counts grown to fill the viewport.
  final int columns;
  final int rows;

  /// Distance from one cell origin to the next (cell + one gap).
  double get pitch => cellExtent + config.gap;

  double get gap => config.gap;

  /// Total scrollable content size, including outer padding of one gap.
  Size get contentSize => Size(
        columns * pitch + gap,
        rows * pitch + gap,
      );

  /// Tile = cell plus half a gap on every side. Tiles partition the content
  /// area; a card's visual region is the union of its cells' tiles deflated
  /// by gap/2, which bridges gaps inside a card and guarantees exactly one
  /// [gap] between adjacent cards.
  Offset tileOrigin(int col, int row) =>
      Offset(gap / 2 + col * pitch, gap / 2 + row * pitch);

  /// The visible (gap-inset) rect of a single cell.
  Rect cellRect(CellIndex cell) {
    final tile = tileOrigin(cell.col, cell.row);
    return Rect.fromLTWH(
      tile.dx + gap / 2,
      tile.dy + gap / 2,
      cellExtent,
      cellExtent,
    );
  }

  /// Bounding rect (gap-inset) of a whole shape.
  Rect shapeBounds(CardShape shape) {
    final tl = cellRect(CellIndex(shape.minCol, shape.minRow));
    final br = cellRect(CellIndex(shape.maxCol, shape.maxRow));
    return Rect.fromLTRB(tl.left, tl.top, br.right, br.bottom);
  }

  /// The cell under a content-space point, clamped into the grid.
  CellIndex cellAt(Offset contentPoint) {
    final col = ((contentPoint.dx - gap / 2) / pitch)
        .floor()
        .clamp(0, columns - 1);
    final row = ((contentPoint.dy - gap / 2) / pitch)
        .floor()
        .clamp(0, rows - 1);
    return CellIndex(col, row);
  }

  bool cellInBounds(CellIndex cell) =>
      cell.col >= 0 && cell.col < columns && cell.row >= 0 && cell.row < rows;

  /// Snap steps for a drag: how many whole cells a pixel delta has crossed,
  /// switching at the 50% point of each successive cell (gap midpoints
  /// included, since pitch covers cell + gap).
  int snapSteps(double pixelDelta) => (pixelDelta / pitch + 0.5).floor();

  @override
  bool operator ==(Object other) =>
      other is GridMetrics &&
      other.config == config &&
      other.cellExtent == cellExtent &&
      other.viewportSize == viewportSize &&
      other.columns == columns &&
      other.rows == rows;

  @override
  int get hashCode =>
      Object.hash(config, cellExtent, viewportSize, columns, rows);
}
