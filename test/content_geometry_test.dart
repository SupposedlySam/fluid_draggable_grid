import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluid_draggable_grid/fluid_draggable_grid.dart';

void main() {
  const config = FluidGridConfig(
      columns: 8, rows: 8, gap: 10, minCellExtent: 80, maxCellExtent: 80);
  final metrics = GridMetrics.resolve(config, const Size(400, 400));
  final pitch = metrics.pitch; // 90

  group('FluidCardGeometry', () {
    test('rectangle: one band, one region, largestRect covers everything',
        () {
      final geometry =
          FluidCardGeometry.compute(CardShape.rect(1, 1, 3, 2), metrics);
      expect(geometry.rowBands.length, 1);
      expect(geometry.rowBands.single.spans.length, 1);
      expect(geometry.regions.length, 1);
      expect(geometry.largestRect,
          Offset.zero & geometry.size);
      // 3 cells + 2 bridged gaps wide.
      expect(geometry.size.width, closeTo(3 * 80 + 2 * 10, 0.001));
    });

    test('L-shape: bands narrow at the arm, two regions', () {
      // Vertical arm 1 wide x 2 tall + foot extending right on the bottom.
      final shape = CardShape(
          const [CellIndex(0, 0), CellIndex(0, 1), CellIndex(1, 1)]);
      final geometry = FluidCardGeometry.compute(shape, metrics);

      expect(geometry.rowBands.length, 2);
      expect(geometry.rowBands[0].spans.single.width, closeTo(80, 0.001));
      expect(geometry.rowBands[1].spans.single.width,
          closeTo(2 * 80 + 10, 0.001));
      expect(geometry.regions.length, 2);
      // Largest region is the 2-cell one (either orientation is 2 cells).
      expect(
          geometry.regions.first.cellWidth * geometry.regions.first.cellHeight,
          2);
    });

    test('adjacent identical rows merge into one band across the gap', () {
      final geometry =
          FluidCardGeometry.compute(CardShape.rect(0, 0, 2, 3), metrics);
      expect(geometry.rowBands.length, 1);
      expect(geometry.rowBands.single.extent,
          closeTo(3 * 80 + 2 * 10, 0.001));
    });

    test('interior notch splits a band into two spans', () {
      // 3x2 with the top-middle cell missing: U rotated 180.
      final shape = CardShape(const [
        CellIndex(0, 0), CellIndex(2, 0),
        CellIndex(0, 1), CellIndex(1, 1), CellIndex(2, 1),
      ]);
      final geometry = FluidCardGeometry.compute(shape, metrics);
      expect(geometry.rowBands.first.spans.length, 2);
      expect(geometry.rowBands.last.spans.length, 1);
      // Largest rect is the full bottom row.
      expect(geometry.largestRect.width, closeTo(3 * 80 + 2 * 10, 0.001));
      expect(geometry.largestRect.height, closeTo(80, 0.001));
    });

    test('deflate trims spans and re-anchors coordinates', () {
      final geometry =
          FluidCardGeometry.compute(CardShape.rect(0, 0, 2, 2), metrics)
              .deflate(const EdgeInsets.all(15));
      expect(geometry.size.width, closeTo(2 * 80 + 10 - 30, 0.001));
      expect(geometry.rowBands.single.spans.single.left, 0);
      expect(geometry.largestRect.topLeft, Offset.zero);
      expect(geometry.insets, const EdgeInsets.all(15));
    });

    test('cropTo produces rectangular sub-geometry', () {
      final shape = CardShape(
          const [CellIndex(0, 0), CellIndex(0, 1), CellIndex(1, 1)]);
      final geometry = FluidCardGeometry.compute(shape, metrics);
      final cropped = geometry.cropTo(geometry.largestRect);
      expect(cropped.regions.length, 1);
      expect(cropped.size, geometry.largestRect.size);
      // Every surviving band spans the full crop width — rectangular.
      for (final band in cropped.rowBands) {
        expect(band.spans.single.width, closeTo(cropped.size.width, 0.001));
      }
    });

    test('column bands transpose the same structure', () {
      final shape = CardShape(
          const [CellIndex(0, 0), CellIndex(0, 1), CellIndex(1, 1)]);
      final geometry = FluidCardGeometry.compute(shape, metrics);
      expect(geometry.columnBands.length, 2);
      // First column spans both rows; second only the bottom row.
      expect(geometry.columnBands[0].spans.single.height,
          closeTo(2 * 80 + 10, 0.001));
      expect(geometry.columnBands[1].spans.single.height,
          closeTo(80, 0.001));
    });

    test('pitch sanity', () {
      expect(pitch, 90);
    });

    test('deflate insets interior card edges, not just the bounding box',
        () {
      // L-shape: arm (0,0)-(0,1), foot (1,1). The foot's top and the arm's
      // right are card edges created by the notch — interior to the
      // bounding box, but they must still receive padding.
      final shape = CardShape(
          const [CellIndex(0, 0), CellIndex(0, 1), CellIndex(1, 1)]);
      final geometry = FluidCardGeometry.compute(shape, metrics)
          .deflate(const EdgeInsets.all(10));

      final arm = geometry.regions
          .firstWhere((r) => r.cellWidth == 1 && r.cellHeight == 2);
      final foot = geometry.regions
          .firstWhere((r) => r.cellWidth == 1 && r.cellHeight == 1);

      // Arm (original local 0,0,80,170): all four sides on the outline.
      expect(arm.rect, const Rect.fromLTRB(0, 0, 60, 150));
      // Foot (original local 90,90,170,170): top/right/bottom on the
      // outline get 10; the left faces the bridged gap and keeps its edge.
      expect(foot.rect, const Rect.fromLTRB(80, 90, 150, 150));
    });

    test('cropTo stays pure windowing (no outline insets)', () {
      final geometry =
          FluidCardGeometry.compute(CardShape.rect(0, 0, 2, 2), metrics);
      final cropped =
          geometry.cropTo(const Rect.fromLTRB(20, 20, 120, 120));
      expect(cropped.size, const Size(100, 100));
      expect(cropped.largestRect.topLeft, Offset.zero);
    });
  });
}
