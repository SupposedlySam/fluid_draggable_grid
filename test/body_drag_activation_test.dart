import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:amoeba_grid/amoeba_grid.dart';
import 'package:amoeba_grid/src/engine/handles.dart';

void main() {
  const config = AmoebaGridConfig(
    columns: 8,
    rows: 8,
    gap: 10,
    minCellExtent: 80,
    maxCellExtent: 80,
    bodyDragActivation: BodyDragActivation.longPress,
  );

  Future<AmoebaGridController> pumpGrid(WidgetTester tester) async {
    final controller = AmoebaGridController(config: config);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AmoebaGridView(
          controller: controller,
          cards: [
            AmoebaGridCard(
              id: 'a',
              initialShape: CardShape.rect(0, 0, 2, 2),
              child: InkWell(
                onTap: () {},
                child: const Center(child: Text('CONTENT')),
              ),
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('longPress: a quick pan over content does not move the card',
      (tester) async {
    final controller = await pumpGrid(tester);
    final pitch = controller.metrics!.pitch;

    final textCenter = tester.getCenter(find.text('CONTENT'));
    final gesture = await tester.startGesture(textCenter);
    await gesture.moveBy(Offset(pitch * 2.1, 0),
        timeStamp: const Duration(milliseconds: 100));
    await tester.pump();
    final dragging = controller.isDragging;
    await gesture.up();
    await tester.pumpAndSettle();

    expect(dragging, isFalse,
        reason: 'a body pan without a long-press must not start a drag');
    expect(controller.committedShape('a'), CardShape.rect(0, 0, 2, 2));
  });

  testWidgets('longPress: long-press then move drags and commits the card',
      (tester) async {
    final controller = await pumpGrid(tester);
    final pitch = controller.metrics!.pitch;

    final textCenter = tester.getCenter(find.text('CONTENT'));
    final gesture = await tester.startGesture(textCenter);
    // Hold past the long-press deadline (350ms) without moving.
    await tester.pump(const Duration(milliseconds: 400));
    expect(controller.isDragging, isTrue,
        reason: 'the drag session (and lift cue) starts at long-press accept');
    await gesture.moveBy(Offset(pitch * 2.1, 0));
    await tester.pump();
    expect(controller.isDragging, isTrue,
        reason: 'drag session should be live mid-move');
    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.committedShape('a'), CardShape.rect(2, 0, 2, 2));
  });

  testWidgets('longPress: handles still resize immediately (no hold)',
      (tester) async {
    final controller = await pumpGrid(tester);
    final metrics = controller.metrics!;
    final pitch = metrics.pitch;

    final east = handlesFor('a', CardShape.rect(0, 0, 2, 2), metrics)
        .firstWhere((h) =>
            !h.isCorner &&
            h.edge == CardinalEdge.east &&
            h.cell == const CellIndex(1, 0));

    final gridTopLeft = tester.getTopLeft(find.byType(AmoebaGridView));
    final gesture = await tester.startGesture(gridTopLeft + east.center);
    await gesture.moveBy(Offset(pitch * 1.1, 0),
        timeStamp: const Duration(milliseconds: 100));
    await tester.pump();
    final dragging = controller.isDragging;
    await gesture.up();
    await tester.pumpAndSettle();

    expect(dragging, isTrue,
        reason: 'handle drags must not wait for a long-press');
    final committed = controller.committedShape('a')!;
    expect(committed.cells, contains(const CellIndex(2, 0)),
        reason: 'east strip resize should have added a cell');
    expect(committed.cells.length, 5);
  });
}
