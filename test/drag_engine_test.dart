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
  });
}
