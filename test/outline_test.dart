import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:amoeba_grid/amoeba_grid.dart';
import 'package:amoeba_grid/src/engine/handles.dart';
import 'package:amoeba_grid/src/engine/outline.dart';

void main() {
  const config = AmoebaGridConfig(
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

    test('side handles cover their entire cell edge, not just the midpoint',
        () {
      final handles =
          handlesFor('x', CardShape.rect(0, 0, 2, 2), metrics);
      final north = handles.firstWhere((h) =>
          !h.isCorner &&
          h.edge == CardinalEdge.north &&
          h.cell == const CellIndex(0, 0));
      // Near the end of the cell edge, well away from the midpoint circle.
      final nearEdgeEnd =
          north.center + Offset(metrics.cellExtent * 0.4, -4);
      expect(north.hits(nearEdgeEnd), isTrue);
    });

    test('adjacent cards: each side of the gutter grabs its own card', () {
      final a = CardShape.rect(0, 0, 2, 2);
      final b = CardShape.rect(2, 0, 2, 2);
      final cards = [('a', a), ('b', b)];
      final aRightEdge = metrics.cellRect(const CellIndex(1, 0)).right;
      final y = metrics.cellRect(const CellIndex(1, 0)).center.dy;

      final onLeftHalf =
          interactionAt(Offset(aRightEdge + metrics.gap * 0.25, y),
              cards, metrics);
      expect(onLeftHalf?.$1, 'a');
      expect(onLeftHalf?.$2?.edge, CardinalEdge.east);

      final onRightHalf =
          interactionAt(Offset(aRightEdge + metrics.gap * 0.75, y),
              cards, metrics);
      expect(onRightHalf?.$1, 'b');
      expect(onRightHalf?.$2?.edge, CardinalEdge.west);
    });

    test('a press inside a card is never stolen by a neighbor handle', () {
      final a = CardShape.rect(0, 0, 2, 2);
      final b = CardShape.rect(2, 0, 2, 2);
      final cards = [('a', a), ('b', b)];
      final bLeftEdge = metrics.cellRect(const CellIndex(2, 0)).left;
      final y = metrics.cellRect(const CellIndex(2, 0)).center.dy;

      // 6px inside b: b's own west handle (its interior band), never a's.
      final nearEdge = interactionAt(Offset(bLeftEdge + 6, y), cards, metrics);
      expect(nearEdge?.$1, 'b');
      expect(nearEdge?.$2?.edge, CardinalEdge.west);

      // Deep inside b: b's body — a move, not any handle.
      final deep = interactionAt(Offset(bLeftEdge + 40, y), cards, metrics);
      expect(deep?.$1, 'b');
      expect(deep?.$2, isNull);
    });

    test('handle grab zones do not reach deep into card content', () {
      final handles =
          handlesFor('x', CardShape.rect(0, 0, 2, 2), metrics);
      final north = handles.firstWhere((h) =>
          !h.isCorner &&
          h.edge == CardinalEdge.north &&
          h.cell == const CellIndex(0, 0));
      // Just outside the edge (over the gap): grabbable.
      expect(
          hitTestHandles(handles, north.center + const Offset(0, -10)),
          north);
      // Slightly inside: still grabbable within the interior band.
      expect(
          hitTestHandles(handles, north.center + const Offset(0, 8)),
          north);
      // Deep inside the card content: the body wins, not the handle.
      expect(
          hitTestHandles(handles, north.center + const Offset(0, 20)),
          isNull);
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

    test('keeps corner arcs round mid-morph (no chamfer)', () {
      // Morphing a shape onto itself is the drag-in-place case where the
      // resampled preview visibly chamfered every corner: coarse uniform
      // samples put ~2 points on a 20px arc and connected them with a
      // straight cut. The arc's 45-degree apex bulges outside that chord,
      // so containment of a point just inside the apex proves the morph
      // frame still follows the arc.
      final shape = CardShape.rect(0, 0, 1, 1);
      final outline = CardOutline.trace(shape, metrics).paths;
      final bounds = outline.getBounds();
      final r = config.outsideCornerRadius;
      final center = bounds.topLeft + Offset(r, r);
      final apexInset =
          center + const Offset(-1, -1) / 1.4142135 * (r - 1.5);
      expect(outline.contains(apexInset), isTrue,
          reason: 'sanity: the probe sits inside the true outline');
      final mid = lerpOutline(outline, outline, 0.5);
      expect(mid.contains(apexInset), isTrue,
          reason: 'mid-morph outline must still bulge to the arc apex');
    });
  });
}
