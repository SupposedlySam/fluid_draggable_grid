import 'package:flutter_test/flutter_test.dart';
import 'package:fluid_draggable_grid/fluid_draggable_grid.dart';

void main() {
  group('CardShape', () {
    test('rect factory covers the full block', () {
      final shape = CardShape.rect(1, 2, 3, 2);
      expect(shape.cells.length, 6);
      expect(shape.contains(1, 2), isTrue);
      expect(shape.contains(3, 3), isTrue);
      expect(shape.contains(4, 3), isFalse);
      expect(shape.minCol, 1);
      expect(shape.maxRow, 3);
    });

    test('connectivity detects splits', () {
      final connected = CardShape.rect(0, 0, 2, 1);
      expect(connected.isConnected, isTrue);
      final split = CardShape(
          const [CellIndex(0, 0), CellIndex(2, 0)]);
      expect(split.isConnected, isFalse);
      expect(split.largestComponent.cells.length, 1);
    });

    test('row and column runs follow contiguity', () {
      // L-shape: (0,0) (1,0) (0,1)
      final shape = CardShape(
          const [CellIndex(0, 0), CellIndex(1, 0), CellIndex(0, 1)]);
      expect(shape.rowRun(1, 0).length, 2);
      expect(shape.colRun(0, 1).length, 2);
      expect(shape.rowRun(0, 1).length, 1);
    });

    test('json roundtrip preserves cells', () {
      final shape = CardShape(
          const [CellIndex(2, 3), CellIndex(3, 3), CellIndex(3, 4)]);
      expect(CardShape.fromJson(shape.toJson()), shape);
    });
  });

  group('FluidGridLayoutData', () {
    const config = FluidGridConfig();

    test('resolves mobile-first with fallback through smaller buckets', () {
      final narrowShape = CardShape.rect(0, 0, 1, 1);
      final wideShape = CardShape.rect(0, 0, 4, 2);
      final data = const FluidGridLayoutData.empty()
          .withBucketShapes(0, {'a': narrowShape}).withBucketShapes(
              905, {'a': wideShape});

      expect(data.resolve('a', 400, config), narrowShape);
      expect(data.resolve('a', 700, config), narrowShape);
      expect(data.resolve('a', 1000, config), wideShape);
      expect(data.resolve('a', 2000, config), wideShape);
      expect(data.resolve('missing', 1000, config), isNull);
    });

    test('encode/decode roundtrip', () {
      final data = const FluidGridLayoutData.empty().withBucketShapes(
          600, {'card': CardShape.rect(1, 1, 2, 3)});
      final decoded = FluidGridLayoutData.decode(data.encode());
      expect(decoded.resolve('card', 800, config),
          CardShape.rect(1, 1, 2, 3));
    });

    test('bucketFor picks the largest breakpoint at or below width', () {
      expect(config.bucketFor(500), 0);
      expect(config.bucketFor(600), 600);
      expect(config.bucketFor(1500), 1240);
    });
  });
}
