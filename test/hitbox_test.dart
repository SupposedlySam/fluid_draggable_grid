import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluid_draggable_grid/fluid_draggable_grid.dart';
import 'package:fluid_draggable_grid/src/engine/handles.dart';

/// Exhaustive grab-zone boundary tests. Geometry is pinned: cell 100px,
/// gap 12px, pitch 112px, hitRadius 26, side interior reach 12, side
/// tangent reach 56 (full cell edge + half gap each side), corner pull 6
/// (outside radius 20 * 0.3), concave pull 5 (inside radius 10 * 0.3 + 2).
void main() {
  const config = FluidGridConfig(
    columns: 12,
    rows: 12,
    minCellExtent: 100,
    maxCellExtent: 100,
    gap: 12,
    insideCornerRadius: 10,
    outsideCornerRadius: 20,
  );
  final metrics = GridMetrics.resolve(config, const Size(400, 400));

  Offset perpendicular(Offset unit) => Offset(-unit.dy, unit.dx);

  group('side handle bounds', () {
    // Lone 2x2 card; north handle of its top-left cell.
    final shape = CardShape.rect(1, 1, 2, 2);
    final cards = [('x', shape)];
    late final GridHandle north = handlesFor('x', shape, metrics).firstWhere(
        (h) =>
            !h.isCorner &&
            h.edge == CardinalEdge.north &&
            h.cell == const CellIndex(1, 1));

    (String, GridHandle?)? at(Offset point) =>
        interactionAt(point, cards, metrics);

    test('outward reach: grabbable 25px above the edge, not 27px', () {
      expect(at(north.center + const Offset(0, -25))?.$2, north);
      expect(at(north.center + const Offset(0, -27)), isNull);
    });

    test('interior reach: 11px inside resizes, 13px inside moves the body',
        () {
      expect(at(north.center + const Offset(0, 11))?.$2, north);
      final deeper = at(north.center + const Offset(0, 13));
      expect(deeper?.$1, 'x');
      expect(deeper?.$2, isNull, reason: 'body move, not a resize');
    });

    test('tangent reach covers the cell edge + half gap on each side', () {
      expect(north.hits(north.center + const Offset(55, 0)), isTrue);
      expect(north.hits(north.center + const Offset(-55, 0)), isTrue);
      expect(north.hits(north.center + const Offset(57, 0)), isFalse);
      expect(north.hits(north.center + const Offset(-57, 0)), isFalse);
    });

    test('no dead spot over the bridged gap of a multi-cell edge', () {
      // Gap midline between the two north-edge strips.
      final gapMidline = Offset(
          metrics.cellRect(const CellIndex(1, 1)).right + metrics.gap / 2,
          north.center.dy);
      final hit = at(gapMidline)?.$2;
      expect(hit, isNotNull);
      expect(hit!.edge, CardinalEdge.north);
    });

    test('the corner region outranks the side band', () {
      final cornerPoint = metrics.cellRect(const CellIndex(1, 1)).topLeft;
      final hit = at(cornerPoint)?.$2;
      expect(hit, isNotNull);
      expect(hit!.isCorner, isTrue);
      expect(hit.corner, CornerKind.northWest);
    });
  });

  group('convex corner bounds', () {
    final shape = CardShape.rect(1, 1, 2, 2);
    final cards = [('x', shape)];
    late final GridHandle corner = handlesFor('x', shape, metrics)
        .firstWhere((h) => h.corner == CornerKind.northWest && !h.concave);
    final out = corner.outwardUnit;

    (String, GridHandle?)? at(Offset point) =>
        interactionAt(point, cards, metrics);

    test('outward reach along the diagonal: 31px yes, 33px no', () {
      expect(at(corner.center + out * 31)?.$2, corner);
      expect(at(corner.center + out * 33), isNull);
    });

    test('the whole visible disc responds: inner half resizes, not moves',
        () {
      // Center is pulled 6px inward; interior reach is compensated to 18.
      expect(at(corner.center - out * 17)?.$2, corner);
      final deeper = at(corner.center - out * 19);
      expect(deeper?.$1, 'x');
      expect(deeper?.$2, isNull);
    });

    test('tangent reach across the diagonal: 25px yes, 27px no', () {
      final perp = perpendicular(out);
      expect(corner.hits(corner.center + perp * 25), isTrue);
      expect(corner.hits(corner.center - perp * 25), isTrue);
      expect(corner.hits(corner.center + perp * 27), isFalse);
      expect(corner.hits(corner.center - perp * 27), isFalse);
    });
  });

  group('concave corner bounds', () {
    // L-shape: arm (0,0)-(0,1), foot (1,1); notch cell is (1,0).
    final shape = CardShape(
        const [CellIndex(0, 0), CellIndex(0, 1), CellIndex(1, 1)]);
    final cards = [('x', shape)];
    late final GridHandle notch = handlesFor('x', shape, metrics)
        .firstWhere((h) => h.concave);
    final out = notch.outwardUnit;

    (String, GridHandle?)? at(Offset point) =>
        interactionAt(point, cards, metrics);

    test('is the northEast notch of the L', () {
      expect(notch.corner, CornerKind.northEast);
    });

    test('grabbable into the notch: 30px yes (beats the side bands)', () {
      final hit = at(notch.center + out * 30)?.$2;
      expect(hit, notch, reason: 'corner priority + nearest center');
    });

    test('deep in the notch, the bordering side band takes over', () {
      // 20px above the foot's north edge, mid-cell: outside the concave
      // zone but inside the north side handle's outward reach.
      final footNorth = handlesFor('x', shape, metrics).firstWhere((h) =>
          !h.isCorner &&
          h.edge == CardinalEdge.north &&
          h.cell == const CellIndex(1, 1));
      final hit = at(footNorth.center + const Offset(0, -20))?.$2;
      expect(hit, footNorth);
    });

    test('inner half of the disc resizes; deeper is a body move', () {
      expect(at(notch.center - out * 16)?.$2, notch);
      final deeper = at(notch.center - out * 19);
      expect(deeper?.$1, 'x');
      expect(deeper?.$2, isNull);
    });

    test('the middle of the notch cell is dead space', () {
      final notchCellCenter =
          metrics.cellRect(const CellIndex(1, 0)).center;
      expect(at(notchCellCenter), isNull);
    });
  });

  group('card body and open space', () {
    final shape = CardShape.rect(1, 1, 2, 2);
    final cards = [('x', shape)];

    (String, GridHandle?)? at(Offset point) =>
        interactionAt(point, cards, metrics);

    test('the card center is a body move', () {
      final result = at(metrics.shapeBounds(shape).center);
      expect(result?.$1, 'x');
      expect(result?.$2, isNull);
    });

    test('the internal bridged gap belongs to the body', () {
      // Between the card's own two columns, mid-height: inside the outline,
      // far from any open edge.
      final internalGap = Offset(
          metrics.cellRect(const CellIndex(1, 1)).right + metrics.gap / 2,
          metrics.shapeBounds(shape).center.dy);
      final result = at(internalGap);
      expect(result?.$1, 'x');
      expect(result?.$2, isNull);
    });

    test('empty space beyond every reach hits nothing (canvas pans)', () {
      final farAway = metrics.shapeBounds(shape).bottomRight +
          const Offset(60, 60);
      expect(at(farAway), isNull);
    });
  });

  group('adjacent cards share the gutter fairly', () {
    // Horizontal neighbors: a | b, and vertical neighbors: p over q.
    final a = CardShape.rect(1, 1, 2, 2);
    final b = CardShape.rect(3, 1, 2, 2);
    final p = CardShape.rect(1, 1, 2, 2);
    final q = CardShape.rect(1, 3, 2, 2);

    test('left to right: left half of the gutter grabs the left card', () {
      final gutterLeft = metrics.cellRect(const CellIndex(2, 1)).right;
      final y = metrics.cellRect(const CellIndex(2, 1)).center.dy;
      final result = interactionAt(
          Offset(gutterLeft + 3, y), [('a', a), ('b', b)], metrics);
      expect(result?.$1, 'a');
      expect(result?.$2?.edge, CardinalEdge.east);
    });

    test('right to left: right half of the gutter grabs the right card', () {
      final gutterLeft = metrics.cellRect(const CellIndex(2, 1)).right;
      final y = metrics.cellRect(const CellIndex(2, 1)).center.dy;
      final result = interactionAt(
          Offset(gutterLeft + metrics.gap - 3, y), [('a', a), ('b', b)],
          metrics);
      expect(result?.$1, 'b');
      expect(result?.$2?.edge, CardinalEdge.west);
    });

    test('top to bottom: top half of the gutter grabs the upper card', () {
      final gutterTop = metrics.cellRect(const CellIndex(1, 2)).bottom;
      final x = metrics.cellRect(const CellIndex(1, 2)).center.dx;
      final result = interactionAt(
          Offset(x, gutterTop + 3), [('p', p), ('q', q)], metrics);
      expect(result?.$1, 'p');
      expect(result?.$2?.edge, CardinalEdge.south);
    });

    test('bottom to top: bottom half of the gutter grabs the lower card',
        () {
      final gutterTop = metrics.cellRect(const CellIndex(1, 2)).bottom;
      final x = metrics.cellRect(const CellIndex(1, 2)).center.dx;
      final result = interactionAt(
          Offset(x, gutterTop + metrics.gap - 3), [('p', p), ('q', q)],
          metrics);
      expect(result?.$1, 'q');
      expect(result?.$2?.edge, CardinalEdge.north);
    });

    test('a press just inside either card always gets that card', () {
      final bLeft = metrics.cellRect(const CellIndex(3, 1)).left;
      final aRight = metrics.cellRect(const CellIndex(2, 1)).right;
      final y = metrics.cellRect(const CellIndex(2, 1)).center.dy;
      final cards = [('a', a), ('b', b)];

      final insideB = interactionAt(Offset(bLeft + 6, y), cards, metrics);
      expect(insideB?.$1, 'b');
      expect(insideB?.$2?.edge, CardinalEdge.west);

      final insideA = interactionAt(Offset(aRight - 6, y), cards, metrics);
      expect(insideA?.$1, 'a');
      expect(insideA?.$2?.edge, CardinalEdge.east);
    });
  });

  group('end to end: gutter presses resize the correct card', () {
    Future<FluidGridController> pumpPair(WidgetTester tester,
        Map<String, CardShape> shapes) async {
      final controller = FluidGridController(config: config);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FluidGridView(
            controller: controller,
            cards: [
              for (final entry in shapes.entries)
                FluidGridCard(
                  id: entry.key,
                  initialShape: entry.value,
                  child: const ColoredBox(color: Colors.blueGrey),
                ),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return controller;
    }

    Future<void> expectResize(WidgetTester tester,
        FluidGridController controller, Offset press,
        {required String card, required CardinalEdge edge}) async {
      final gesture =
          await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.down(tester.getTopLeft(find.byType(FluidGridView)) +
          press);
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(const Offset(2, 2));
        await tester.pump(const Duration(milliseconds: 8));
      }
      expect(controller.isDragging, isTrue);
      expect(controller.session!.kind, DragKind.resize);
      expect(controller.session!.cardId, card);
      expect(controller.session!.handle!.edge, edge);
      await gesture.up();
      await tester.pumpAndSettle();
    }

    testWidgets('horizontal pair, both directions', (tester) async {
      final controller = await pumpPair(tester, {
        'a': CardShape.rect(1, 1, 2, 2),
        'b': CardShape.rect(3, 1, 2, 2),
      });
      final gutterLeft = metrics.cellRect(const CellIndex(2, 1)).right;
      final y = metrics.cellRect(const CellIndex(2, 1)).center.dy;
      await expectResize(tester, controller, Offset(gutterLeft + 3, y),
          card: 'a', edge: CardinalEdge.east);
      await expectResize(tester, controller,
          Offset(gutterLeft + metrics.gap - 3, y),
          card: 'b', edge: CardinalEdge.west);
    });

    testWidgets('vertical pair, both directions', (tester) async {
      final controller = await pumpPair(tester, {
        'p': CardShape.rect(1, 1, 2, 2),
        'q': CardShape.rect(1, 3, 2, 2),
      });
      final gutterTop = metrics.cellRect(const CellIndex(1, 2)).bottom;
      final x = metrics.cellRect(const CellIndex(1, 2)).center.dx;
      await expectResize(tester, controller, Offset(x, gutterTop + 3),
          card: 'p', edge: CardinalEdge.south);
      await expectResize(tester, controller,
          Offset(x, gutterTop + metrics.gap - 3),
          card: 'q', edge: CardinalEdge.north);
    });
  });
}
