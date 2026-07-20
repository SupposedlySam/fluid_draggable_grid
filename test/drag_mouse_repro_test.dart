import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluid_draggable_grid/fluid_draggable_grid.dart';

class _AllDevices extends MaterialScrollBehavior {
  const _AllDevices();
  @override
  Set<PointerDeviceKind> get dragDevices => PointerDeviceKind.values.toSet();
}

void main() {
  testWidgets('mouse drag over InkWell content, small increments',
      (tester) async {
    const config = FluidGridConfig(
        columns: 8, rows: 8, gap: 10, minCellExtent: 80, maxCellExtent: 80);
    final controller = FluidGridController(config: config);

    await tester.pumpWidget(MaterialApp(
      scrollBehavior: const _AllDevices(),
      home: Scaffold(
        body: FluidGridView(
          controller: controller,
          cards: [
            FluidGridCard(
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
    final pitch = controller.metrics!.pitch;

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(tester.getCenter(find.text('CONTENT')));
    await tester.pump();
    // Real mice move in small increments.
    for (var i = 0; i < 24; i++) {
      await gesture.moveBy(Offset(pitch * 2.2 / 24, 0));
      await tester.pump(const Duration(milliseconds: 8));
    }
    final wasDragging = controller.isDragging;
    await gesture.up();
    await tester.pumpAndSettle();

    expect(wasDragging, isTrue, reason: 'session should be live mid-drag');
    expect(controller.committedShape('a'), CardShape.rect(2, 0, 2, 2));
  });
}
