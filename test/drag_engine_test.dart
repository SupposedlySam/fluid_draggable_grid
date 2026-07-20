import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluid_draggable_grid/fluid_draggable_grid.dart';
import 'package:fluid_draggable_grid/src/engine/drag_engine.dart';

void main() {
  const config = FluidGridConfig(columns: 8, rows: 8);
  final metrics = GridMetrics.resolve(config, const Size(1200, 800));

  group('applyStripResize', () {
    test('extends a single row strip eastward', () {
      final shape = CardShape.rect(0, 0, 2, 2);
      final result = applyStripResize(
          shape, const CellIndex(1, 0), CardinalEdge.east, 2, metrics);
      expect(result.cells.length, 6);
      expect(result.contains(3, 0), isTrue);
      expect(result.contains(3, 1), isFalse, reason: 'only row 0 extends');
    });

    test('retracts from the strip end and keeps connectivity', () {
      final shape = CardShape.rect(0, 0, 3, 1);
      final result = applyStripResize(
          shape, const CellIndex(2, 0), CardinalEdge.east, -2, metrics);
      expect(result, CardShape.rect(0, 0, 1, 1));
    });

    test('never empties the shape', () {
      final shape = CardShape.rect(0, 0, 1, 1);
      final result = applyStripResize(
          shape, const CellIndex(0, 0), CardinalEdge.east, -5, metrics);
      expect(result.cells.length, 1);
    });

    test('clamps extension at the grid boundary', () {
      final shape = CardShape.rect(6, 0, 2, 1);
      final result = applyStripResize(
          shape, const CellIndex(7, 0), CardinalEdge.east, 3, metrics);
      expect(result, shape);
    });
  });

  group('applyCornerResize', () {
    test('extending both axes fills the diagonal corner block', () {
      final shape = CardShape.rect(0, 0, 2, 2);
      final handle = GridHandle(
        cardId: 'x',
        cell: const CellIndex(1, 1),
        center: Offset.zero,
        hitRadius: 10,
        corner: CornerKind.southEast,
      );
      final result = applyCornerResize(shape, handle, 1, 1, metrics);
      expect(result, CardShape.rect(0, 0, 3, 3));
    });

    test('concave corner pulls both edge segments and fills the notch', () {
      // L-shape: vertical arm (0,0)-(0,1), foot (1,1). Concave NE corner
      // anchored on (0,0) east edge and (1,1) north edge.
      final shape = CardShape(
          const [CellIndex(0, 0), CellIndex(0, 1), CellIndex(1, 1)]);
      final handle = GridHandle(
        cardId: 'x',
        cell: const CellIndex(0, 0),
        cellV: const CellIndex(1, 1),
        center: Offset.zero,
        hitRadius: 10,
        corner: CornerKind.northEast,
        concave: true,
      );
      // Dragging the notch eastward extends the vertical arm's east
      // segment, filling the notch into a full 2x2.
      final result = applyCornerResize(shape, handle, 1, 0, metrics);
      expect(result, CardShape.rect(0, 0, 2, 2));
    });
  });

  group('applySideResize (L-gesture)', () {
    test('perpendicular movement grows only the new section', () {
      // 2x2 card at rows 2-3; grab east handle of its top row (1,2),
      // drag right 2 and up 1: a 2x2 block merges onto the top-right.
      final shape = CardShape.rect(0, 2, 2, 2);
      final result = applySideResize(
          shape, const CellIndex(1, 2), CardinalEdge.east, 2, -1, metrics);
      final expected = {
        ...shape.cells,
        const CellIndex(2, 2), const CellIndex(3, 2), // primary strip
        const CellIndex(2, 1), const CellIndex(3, 1), // perpendicular growth
      };
      expect(result, CardShape(expected));
      expect(result.contains(0, 1), isFalse,
          reason: 'the original card must not expand');
      expect(result.contains(1, 1), isFalse,
          reason: 'the original card must not expand');
    });

    test('without perpendicular movement it stays a strip resize', () {
      final shape = CardShape.rect(0, 0, 2, 2);
      final result = applySideResize(
          shape, const CellIndex(1, 0), CardinalEdge.east, 2, 0, metrics);
      expect(result.cells.length, 6);
      expect(result.contains(3, 0), isTrue);
      expect(result.contains(3, 1), isFalse);
    });

    test('negative primary steps retract and ignore perpendicular', () {
      final shape = CardShape.rect(0, 0, 3, 1);
      final result = applySideResize(
          shape, const CellIndex(2, 0), CardinalEdge.east, -1, 2, metrics);
      expect(result, CardShape.rect(0, 0, 2, 1));
    });

    test('north handle L-gesture grows east/west of the new section', () {
      final shape = CardShape.rect(2, 2, 2, 2);
      final result = applySideResize(
          shape, const CellIndex(2, 2), CardinalEdge.north, 1, 1, metrics);
      final expected = {
        ...shape.cells,
        const CellIndex(2, 1), // primary: up from (2,2)
        const CellIndex(3, 1), // perpendicular: east of the new cell
      };
      expect(result, CardShape(expected));
    });
  });

  group('trimSubmissive', () {
    test('west entry cedes cells through the aggressor far edge per row', () {
      final submissive = CardShape.rect(3, 0, 3, 2);
      // Aggressor overlaps only row 0, columns 3..4.
      final aggressor = CardShape.rect(2, 0, 3, 1).cells;
      final trimmed =
          trimSubmissive(submissive, aggressor, CardinalEdge.west)!;
      expect(trimmed.contains(3, 0), isFalse);
      expect(trimmed.contains(4, 0), isFalse);
      expect(trimmed.contains(5, 0), isTrue);
      // Row 1 untouched.
      expect(trimmed.contains(3, 1), isTrue);
    });

    test('returns null when nothing would remain', () {
      final submissive = CardShape.rect(3, 0, 1, 1);
      final aggressor = CardShape.rect(2, 0, 3, 1).cells;
      expect(
          trimSubmissive(submissive, aggressor, CardinalEdge.west), isNull);
    });

    test('keeps the largest component when a trim splits the shape', () {
      // Vertical bar overlapped in its middle cell by a horizontal aggressor
      // entering from the west: middle row cedes fully, splitting the bar.
      final submissive = CardShape.rect(3, 0, 1, 5);
      final aggressor = CardShape.rect(1, 2, 4, 1).cells;
      final trimmed =
          trimSubmissive(submissive, aggressor, CardinalEdge.west)!;
      expect(trimmed.isConnected, isTrue);
      expect(trimmed.cells.length, 2);
    });
  });

  group('relocateBeyond', () {
    test('finds the nearest clear spot in the travel direction', () {
      final shape = CardShape.rect(3, 0, 1, 1);
      final blocked = CardShape.rect(2, 0, 3, 1).cells;
      final relocated =
          relocateBeyond(shape, blocked, CardinalEdge.east, metrics)!;
      expect(relocated, CardShape.rect(5, 0, 1, 1));
    });

    test('returns null when the grid edge blocks relocation', () {
      final shape = CardShape.rect(7, 0, 1, 1);
      final blocked = CardShape.rect(6, 0, 2, 1).cells;
      expect(relocateBeyond(shape, blocked, CardinalEdge.east, metrics),
          isNull);
    });
  });

  group('GridMetrics', () {
    test('snapSteps switches at the 50% point of each pitch', () {
      final pitch = metrics.pitch;
      expect(metrics.snapSteps(pitch * 0.49), 0);
      expect(metrics.snapSteps(pitch * 0.51), 1);
      expect(metrics.snapSteps(pitch * 1.51), 2);
      expect(metrics.snapSteps(-pitch * 0.51), -1);
    });

    test('cell extent clamps between min and max', () {
      final tight = GridMetrics.resolve(config, const Size(300, 400));
      expect(tight.cellExtent, config.minCellExtent);
      final wide = GridMetrics.resolve(config, const Size(4000, 400));
      expect(wide.cellExtent, config.maxCellExtent);
    });

    test('grid grows beyond config counts to fill the viewport', () {
      const small = FluidGridConfig(
          columns: 4,
          rows: 4,
          minCellExtent: 60,
          maxCellExtent: 100,
          gap: 10);
      final grown = GridMetrics.resolve(small, const Size(1000, 500));
      // (1000 - 10) / (100 + 10) = 9 columns fit at max extent.
      expect(grown.columns, 9);
      expect(grown.cellExtent, 100);
      // (500 - 10) / 110 = 4.45 -> still the 4-row minimum.
      expect(grown.rows, 4);
      // Narrow viewports never drop below the config counts.
      final narrow = GridMetrics.resolve(small, const Size(200, 200));
      expect(narrow.columns, 4);
      expect(narrow.rows, 4);
    });

    test('occupied cells extend the grid on small viewports', () {
      const small = FluidGridConfig(
          columns: 4,
          rows: 4,
          minCellExtent: 60,
          maxCellExtent: 100,
          gap: 10);
      // A card parked at column 10 on a wide window must stay reachable
      // when the window shrinks to phone size.
      final tiny = GridMetrics.resolve(small, const Size(300, 400),
          minColumns: 11, minRows: 6);
      expect(tiny.columns, 11);
      expect(tiny.rows, 6);
      expect(tiny.contentSize.width, greaterThan(300));
    });
  });
}
