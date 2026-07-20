import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../foundation/cell.dart';
import '../foundation/config.dart';

/// Resolved pixel geometry for one viewport size.
///
/// The grid uses square units. Cell extent flexes between the config's min
/// and max so the fixed column count fills the viewport when possible; when
/// it can't, the content overflows and pans.
@immutable
class GridMetrics {
  const GridMetrics._({
    required this.config,
    required this.cellExtent,
    required this.viewportSize,
  });

  factory GridMetrics.resolve(FluidGridConfig config, Size viewportSize) {
    final available =
        viewportSize.width - config.gap * (config.columns + 1);
    final ideal = available / config.columns;
    final extent =
        ideal.clamp(config.minCellExtent, config.maxCellExtent).toDouble();
    return GridMetrics._(
      config: config,
      cellExtent: extent,
      viewportSize: viewportSize,
    );
  }

  final FluidGridConfig config;
  final double cellExtent;
  final Size viewportSize;

  /// Distance from one cell origin to the next (cell + one gap).
  double get pitch => cellExtent + config.gap;

  double get gap => config.gap;

  /// Total scrollable content size, including outer padding of one gap.
  Size get contentSize => Size(
        config.columns * pitch + gap,
        config.rows * pitch + gap,
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
        .clamp(0, config.columns - 1);
    final row = ((contentPoint.dy - gap / 2) / pitch)
        .floor()
        .clamp(0, config.rows - 1);
    return CellIndex(col, row);
  }

  bool cellInBounds(CellIndex cell) =>
      cell.col >= 0 &&
      cell.col < config.columns &&
      cell.row >= 0 &&
      cell.row < config.rows;

  /// Snap steps for a drag: how many whole cells a pixel delta has crossed,
  /// switching at the 50% point of each successive cell (gap midpoints
  /// included, since pitch covers cell + gap).
  int snapSteps(double pixelDelta) => (pixelDelta / pitch + 0.5).floor();

  @override
  bool operator ==(Object other) =>
      other is GridMetrics &&
      other.config == config &&
      other.cellExtent == cellExtent &&
      other.viewportSize == viewportSize;

  @override
  int get hashCode => Object.hash(config, cellExtent, viewportSize);
}
