import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluid_draggable_grid/fluid_draggable_grid.dart';
import 'package:fluid_draggable_grid/src/engine/handles.dart';
import 'package:fluid_draggable_grid/src/widgets/card_chrome.dart';

void main() {
  const config = FluidGridConfig(
      columns: 12, rows: 12, minCellExtent: 100, maxCellExtent: 100,
      gap: 12, insideCornerRadius: 10, outsideCornerRadius: 20);

  test('corner drag covering a neighbor relocates it live (controller)', () {
    final controller = FluidGridController(config: config)
      ..registerCards({
        'agg': CardShape.rect(1, 1, 1, 1),
        'side': CardShape.rect(3, 1, 1, 1),
      });
    final metrics = GridMetrics.resolve(config, const Size(800, 600));
    controller.updateMetrics(metrics);

    final se = handlesFor('agg', controller.committedShape('agg')!, metrics)
        .firstWhere((h) => h.corner == CornerKind.southEast && !h.concave);
    controller.startResize(se, se.center);
    controller.updateDrag(se.center + Offset(metrics.pitch * 3.1, 0));

    // Mid-drag, before any drop: side must already be relocated.
    final sub = controller.session!.submissives['side'];
    expect(sub, isNotNull, reason: 'side should be reacting live');
    expect(sub!.relocated, isTrue);
    expect(controller.effectiveShape('side'), isNot(CardShape.rect(3, 1, 1, 1)));
  });

  testWidgets('mid-drag, the submissive card surface renders its retreat',
      (tester) async {
    final controller = FluidGridController(config: config);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FluidGridView(
          controller: controller,
          cards: [
            FluidGridCard(
                id: 'agg',
                initialShape: CardShape.rect(1, 1, 1, 1),
                child: const SizedBox()),
            FluidGridCard(
                id: 'side',
                initialShape: CardShape.rect(3, 1, 1, 1),
                child: const SizedBox()),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final metrics = controller.metrics!;

    final se = handlesFor('agg', controller.committedShape('agg')!, metrics)
        .firstWhere((h) => h.corner == CornerKind.southEast && !h.concave);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(se.center);
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(Offset(metrics.pitch * 3.1 / 20, 0));
      await tester.pump(const Duration(milliseconds: 8));
    }

    // Mid-drag: find the FluidCardSurface rendering the submissive and
    // check the shape it was handed.
    final surfaces =
        tester.widgetList<FluidCardSurface>(find.byType(FluidCardSurface));
    final relocated = controller.session!.submissives['side']!.shape;
    expect(
        surfaces.any((s) => s.shape == relocated), isTrue,
        reason: 'the retreat must render live, not only on drop');

    await gesture.up();
    await tester.pumpAndSettle();
  });
}
