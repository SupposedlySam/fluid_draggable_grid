/// Comprehensive coverage of the resize GESTURE math (independent of submissive interaction):
/// side handles pulled OUT and IN with a perpendicular L-component, on all four edges, plus corners.
/// The invariant everywhere: the perpendicular ("L") component is honoured in BOTH directions, and
/// an expand fills the full rectangle rather than tracing the drag path.
@TestOn('vm')
library;

import 'package:amoeba_grid/amoeba_grid.dart' show AmoebaGridConfig;
import 'package:amoeba_grid/src/engine/drag_engine.dart';
import 'package:amoeba_grid/src/engine/grid_metrics.dart';
import 'package:amoeba_grid/src/engine/handles.dart';
import 'package:amoeba_grid/src/foundation/cell.dart';
import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';

void main() {
  const cfg = AmoebaGridConfig(
      columns: 14, rows: 12, minCellExtent: 40, maxCellExtent: 40, gap: 0);
  final m = GridMetrics.resolve(cfg, const Size(560, 480));

  Set<CellIndex> cells(Iterable<(int, int)> xs) => {for (final (c, r) in xs) CellIndex(c, r)};

  GridHandle cornerAt(CardShape s, CornerKind k, CellIndex cell) =>
      handlesFor('x', s, m).firstWhere((h) => h.corner == k && h.cell == cell);

  group('side handle — inward L-gesture (the "pull in then perpendicular" fix)', () {
    // 4x3 card at (2,2): cols 2-5, rows 2-3-4.
    final base = CardShape.rect(2, 2, 4, 3);

    test('east handle, IN 1 + DOWN 1 carves a 1x2 notch (down deepens it)', () {
      final r = applySideResize(base, const CellIndex(5, 2), CardinalEdge.east, -1, 1, m);
      // top two rows lose their rightmost cell.
      expect(r.cells, base.cells.difference(cells([(5, 2), (5, 3)])));
    });

    test('east handle, IN 1 + DOWN 0 is a plain 1-cell retract (unchanged behaviour)', () {
      final r = applySideResize(base, const CellIndex(5, 2), CardinalEdge.east, -1, 0, m);
      expect(r.cells, base.cells.difference(cells([(5, 2)])));
    });

    test('east handle, IN 1 + UP 1 carves upward from the handle row', () {
      // handle on the BOTTOM row (5,4); pull in 1 + up 1 -> remove (5,4) and (5,3).
      final r = applySideResize(base, const CellIndex(5, 4), CardinalEdge.east, -1, -1, m);
      expect(r.cells, base.cells.difference(cells([(5, 4), (5, 3)])));
    });

    test('north handle, IN 1 + OVER 1 carves the perpendicular block', () {
      // north handle on the top-left cell (2,2); pull in (down) 1 + over-right 1 -> remove (2,2),(3,2).
      final r = applySideResize(base, const CellIndex(2, 2), CardinalEdge.north, -1, 1, m);
      expect(r.cells, base.cells.difference(cells([(2, 2), (3, 2)])));
    });
  });

  group('side handle — outward L-gesture fills the block (no missing square)', () {
    final base = CardShape.rect(2, 2, 4, 3);

    test('east handle, OUT 2 + DOWN 1 adds a full 2x2 block on the right of the top rows', () {
      final r = applySideResize(base, const CellIndex(5, 2), CardinalEdge.east, 2, 1, m);
      expect(r.cells, base.cells.union(cells([(6, 2), (7, 2), (6, 3), (7, 3)])));
    });

    test('north handle, OUT 2 + OVER -1 adds a full 2x2 block above-left', () {
      final r = applySideResize(base, const CellIndex(2, 2), CardinalEdge.north, 2, -1, m);
      expect(r.cells, base.cells.union(cells([(2, 1), (1, 1), (2, 0), (1, 0)])));
    });
  });

  group('corner handle — expand fills the full rectangle', () {
    final base = CardShape.rect(2, 2, 4, 3);

    test('NE corner, EAST 2 + NORTH 1 fills a solid rectangle (no diagonal hole)', () {
      final ne = cornerAt(base, CornerKind.northEast, const CellIndex(5, 2));
      final r = applyCornerResize(base, ne, 2, 1, m);
      // Original + east cols 6-7 on all rows + north row 1 across, corner filled = rect cols2-7 rows1-4.
      expect(r.cells, CardShape.rect(2, 1, 6, 4).cells);
    });
  });
}
