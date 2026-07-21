import 'package:amoeba_grid/amoeba_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The dashboard's "My Open PRs" zigzag: row0 = cols 1..4, row1 = cols
  // 0..3 — the bounding box has empty corners top-left and bottom-right,
  // which is where content used to leak onto the page background.
  final shape = CardShape(const [
    CellIndex(1, 0), CellIndex(2, 0), CellIndex(3, 0), CellIndex(4, 0),
    CellIndex(0, 1), CellIndex(1, 1), CellIndex(2, 1), CellIndex(3, 1),
  ]);
  const config = AmoebaGridConfig(
      columns: 5, rows: 2, minCellExtent: 100, maxCellExtent: 100,
      gap: 12, insideCornerRadius: 10, outsideCornerRadius: 22);

  Future<void> pump(WidgetTester tester, AmoebaGridController controller,
      {required int itemCount}) {
    return tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 5 * 112.0 + 12,
          height: 2 * 112.0 + 12,
          child: AmoebaGridView(
            controller: controller,
            cards: [
              AmoebaGridCard(
                id: 'zig',
                initialShape: shape,
                child: AmoebaShell(
                  header: const Text('TITLE'),
                  body: AmoebaListView(
                    itemExtent: 44,
                    itemCount: itemCount,
                    itemBuilder: (context, i) => SizedBox.expand(
                        key: ValueKey('row$i'),
                        child: const ColoredBox(color: Color(0xFF3355FF))),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ));
  }

  testWidgets('the shell body is hard-clipped to the outline path',
      (tester) async {
    final controller = AmoebaGridController(config: config);
    addTearDown(controller.dispose);
    await pump(tester, controller, itemCount: 10);
    await tester.pumpAndSettle();
    // A ClipPath ancestor guarantees nothing paints outside the silhouette
    // no matter what a body child does.
    final clip = find.ancestor(
        of: find.byKey(const ValueKey('row0')),
        matching: find.byType(ClipPath));
    expect(clip, findsWidgets,
        reason: 'body content must be clipped to the card outline');
  });

}
