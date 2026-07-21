@TestOn('vm')
library;

import 'package:amoeba_grid/amoeba_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression: a grid disposed before any handle was ever hovered used to lazily construct the
/// _handleReveal AnimationController INSIDE dispose(), where createTicker's ancestor lookup on a
/// deactivated element throws "Looking up a deactivated widget's ancestor is unsafe".
void main() {
  testWidgets('disposing the view before any hover does not throw', (tester) async {
    final controller = AmoebaGridController(config: const AmoebaGridConfig());
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AmoebaGridView(
          controller: controller,
          cards: [
            AmoebaGridCard(
              id: 'a',
              initialShape: CardShape.rect(0, 0, 2, 2),
              child: const SizedBox(),
            ),
          ],
        ),
      ),
    ));

    // Tear the view down without ever hovering a handle.
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    expect(tester.takeException(), isNull);
  });
}
