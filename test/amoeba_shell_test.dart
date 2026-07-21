import 'package:amoeba_grid/amoeba_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const config = AmoebaGridConfig(
      columns: 8, rows: 8, gap: 12, insideCornerRadius: 8,
      outsideCornerRadius: 20);
  final metrics = GridMetrics.resolve(config, const Size(1200, 900));

  Widget host(CardShape shape, Widget child) {
    final geometry = AmoebaCardGeometry.compute(shape, metrics);
    return MaterialApp(
      home: SizedBox(
        width: geometry.size.width,
        height: geometry.size.height,
        child: AmoebaCardScope(geometry: geometry, child: child),
      ),
    );
  }

  testWidgets('header sits in the topmost span, not the largest rect',
      (tester) async {
    // L-shape: two-cell arm on top-left (wide enough for a header), wide
    // block below — the largest rect is the bottom block, but the title
    // belongs in the top arm.
    final shape = CardShape(const [
      CellIndex(0, 0), CellIndex(1, 0),
      CellIndex(0, 1), CellIndex(1, 1), CellIndex(2, 1), CellIndex(3, 1),
      CellIndex(4, 1),
    ]);
    final geometry = AmoebaCardGeometry.compute(shape, metrics);
    await tester.pumpWidget(host(
      shape,
      AmoebaShell(
        header: const Text('TITLE'),
        body: const SizedBox.expand(),
      ),
    ));
    final headerTop = tester.getTopLeft(find.text('TITLE')).dy;
    // In the top band (arm), not down at the big block.
    expect(geometry.largestRect.top, greaterThan(0),
        reason: 'sanity: the 5-wide bottom block must be the largest rect');
    expect(headerTop, lessThan(geometry.largestRect.top));
  });

  testWidgets('body scope is cropped below the header and keeps notches',
      (tester) async {
    final shape = CardShape(const [
      CellIndex(0, 0), CellIndex(1, 0),
      CellIndex(0, 1), CellIndex(1, 1), CellIndex(2, 1), CellIndex(3, 1),
    ]);
    AmoebaCardGeometry? seen;
    await tester.pumpWidget(host(
      shape,
      AmoebaShell(
        header: const Text('TITLE'),
        body: Builder(builder: (context) {
          seen = AmoebaCardScope.maybeOf(context);
          return const SizedBox.expand();
        }),
      ),
    ));
    expect(seen, isNotNull);
    final geometry = AmoebaCardGeometry.compute(shape, metrics);
    // The body's box is shorter than the card (header carved off the top)…
    expect(seen!.size.height, lessThan(geometry.size.height));
    // …but still shape-aware: the narrow top-arm region survives as a band
    // whose spans are narrower than the full width (the notch to its right
    // is still visible to flow layouts).
    final narrow = seen!.rowBands
        .any((band) => band.spans.every((s) => s.width < seen!.size.width / 2));
    expect(narrow, isTrue,
        reason: 'cropped scope must keep the notch structure');
  });

  testWidgets('a too-narrow top arm defers the header to the next wide band',
      (tester) async {
    // S-shape with a single-cell arm on top: the header must skip it and
    // land in the wide block below, not strand a title-less icon strip.
    final shape = CardShape(const [
      CellIndex(3, 0),
      CellIndex(0, 1), CellIndex(1, 1), CellIndex(2, 1), CellIndex(3, 1),
    ]);
    final geometry = AmoebaCardGeometry.compute(shape, metrics);
    await tester.pumpWidget(host(
      shape,
      AmoebaShell(
        header: const Text('TITLE'),
        body: const SizedBox.expand(),
      ),
    ));
    final headerTop = tester.getTopLeft(find.text('TITLE')).dy;
    final topArmBand = geometry.rowBands.first;
    expect(headerTop, greaterThanOrEqualTo(topArmBand.end),
        reason: 'the one-cell arm cannot fit a header — it must drop to '
            'the wide band below');
  });

  testWidgets('degrades to a plain column outside a fluid card',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: SizedBox(
        width: 300,
        height: 200,
        child: AmoebaShell(header: Text('TITLE'), body: Text('BODY')),
      ),
    ));
    expect(find.text('TITLE'), findsOneWidget);
    expect(find.text('BODY'), findsOneWidget);
  });
}
