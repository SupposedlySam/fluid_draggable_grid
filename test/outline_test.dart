import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluid_draggable_grid/fluid_draggable_grid.dart';
import 'package:fluid_draggable_grid/src/engine/handles.dart';
import 'package:fluid_draggable_grid/src/engine/outline.dart';

void main() {
  const config = FluidGridConfig(
      columns: 8, rows: 8, gap: 12, insideCornerRadius: 8,
      outsideCornerRadius: 20);
  final metrics = GridMetrics.resolve(config, const Size(1200, 900));

  group('CardOutline', () {
    test('rectangle produces four convex corners at the gap inset', () {
      final outline =
          CardOutline.trace(CardShape.rect(1, 1, 2, 1), metrics);
      expect(outline.corners.length, 4);
      expect(outline.corners.every((c) => c.isConvex), isTrue);
      final bounds = outline.paths.getBounds();
      expect(bounds, metrics.shapeBounds(CardShape.rect(1, 1, 2, 1)));
    });

    test('L-shape has five convex and one concave corner', () {
      final shape = CardShape(
          const [CellIndex(0, 0), CellIndex(0, 1), CellIndex(1, 1)]);
      final outline = CardOutline.trace(shape, metrics);
      expect(outline.corners.length, 6);
      expect(outline.corners.where((c) => c.isConvex).length, 5);
      expect(outline.corners.where((c) => !c.isConvex).length, 1);
    });

    test('outline contains cell centers and excludes gap space', () {
      final shape = CardShape.rect(2, 2, 2, 2);
      final outline = CardOutline.trace(shape, metrics);
      expect(
          outline.paths
              .contains(metrics.cellRect(const CellIndex(2, 2)).center),
          isTrue);
      // A point in the gap outside the card.
      final outside = metrics.cellRect(const CellIndex(2, 2)).topLeft -
          const Offset(4, 4);
      expect(outline.paths.contains(outside), isFalse);
    });

    test('diagonal pinch stays gap-respecting and traceable', () {
      final shape = CardShape(const [
        CellIndex(0, 0), CellIndex(1, 0), CellIndex(1, 1), CellIndex(2, 1),
        CellIndex(2, 0),
      ]);
      final outline = CardOutline.trace(shape, metrics);
      expect(outline.paths.computeMetrics().isNotEmpty, isTrue);
    });
  });

  group('handlesFor', () {
    test('a 1x1 card exposes 4 sides and 4 corners', () {
      final handles =
          handlesFor('x', CardShape.rect(0, 0, 1, 1), metrics);
      expect(handles.where((h) => !h.isCorner).length, 4);
      expect(handles.where((h) => h.isCorner).length, 4);
    });

    test('a 2x2 card exposes 8 side handles, one per open cell edge', () {
      final handles =
          handlesFor('x', CardShape.rect(0, 0, 2, 2), metrics);
      expect(handles.where((h) => !h.isCorner).length, 8);
      expect(handles.where((h) => h.isCorner).length, 4);
    });

    test('corners win hit-test ties', () {
      final handles =
          handlesFor('x', CardShape.rect(0, 0, 1, 1), metrics);
      final corner = handles.firstWhere(
          (h) => h.corner == CornerKind.southEast);
      final hit = hitTestHandles(handles, corner.center);
      expect(hit, corner);
    });
  });

  group('lerpOutline', () {
    test('interpolates between two shapes smoothly', () {
      final from =
          CardOutline.trace(CardShape.rect(0, 0, 1, 1), metrics).paths;
      final to =
          CardOutline.trace(CardShape.rect(0, 0, 2, 1), metrics).paths;
      final mid = lerpOutline(from, to, 0.5);
      final midBounds = mid.getBounds();
      expect(midBounds.width, greaterThan(from.getBounds().width));
      expect(midBounds.width, lessThan(to.getBounds().width));
    });
  });
}
