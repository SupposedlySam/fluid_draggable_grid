/// Acceptance criteria for submissive-card behaviour.
///   Partial overlap  -> TRIMMED (cede the overlap).
///   Split            -> BISECTED (keep the larger side).
///   Fully overlapped -> RUNNER: retreat OPPOSITE the aggressor's advance AT THE SMOTHER FRAME, then
///                       take FULL space at original size / PARTIAL space by shrinking / else a 1x1
///                       (an open adjacent cell, or dropped into the aggressor which cedes it).
///                       A runner never displaces another card, and is never killed.
@TestOn('vm')
library;

import 'package:amoeba_grid/amoeba_grid.dart';
import 'package:amoeba_grid/src/engine/drag_engine.dart';
import 'package:flutter/widgets.dart' show Offset, Size;
import 'package:flutter_test/flutter_test.dart';

// Drive a MOVE of [id] by (dCol,dRow) and return the transient shape of [ids].
Map<String, CardShape> _move(AmoebaGridController c, String id, int dCol, int dRow,
    GridMetrics m, double pitch, List<String> ids) {
  final origin = c.committedShape(id)!;
  final start = m.cellRect(CellIndex(origin.minCol, origin.minRow)).center;
  c.startMove(id, start);
  c.updateDrag(start + Offset(dCol * pitch, dRow * pitch));
  return {for (final k in ids) k: c.effectiveShape(k)!};
}

void main() {
  const cfg = AmoebaGridConfig(
      columns: 12, rows: 10, minCellExtent: 40, maxCellExtent: 40, gap: 0);
  final m = GridMetrics.resolve(cfg, const Size(480, 400));
  final pitch = m.pitch;

  AmoebaGridController seed(Map<String, CardShape> shapes) => AmoebaGridController(config: cfg)
    ..registerCards(shapes)
    ..updateMetrics(m);

  Map<String, CardShape> live(AmoebaGridController c, Iterable<String> ids) =>
      {for (final id in ids) id: c.effectiveShape(id)!};

  void noneKilled(Map<String, CardShape> l) {
    for (final e in l.entries) {
      expect(e.value.cells, isNotEmpty, reason: '"${e.key}" was killed');
    }
  }

  void noOverlap(Map<String, CardShape> l) {
    final owner = <CellIndex, String>{};
    for (final e in l.entries) {
      for (final cell in e.value.cells) {
        expect(owner.containsKey(cell), isFalse,
            reason: '${e.key} overlaps ${owner[cell]} at $cell');
        owner[cell] = e.key;
      }
    }
  }

  group('runnerShape — the three sizing tactics (pure)', () {
    test('FULL space: relocates at original size, clear of everything', () {
      final shape = CardShape.rect(3, 3, 2, 1); // cols 3-4, row 3
      final blocked = CardShape.rect(3, 3, 3, 1).cells; // over it + one east
      final r = runnerShape(shape, blocked, CardinalEdge.west, m)!; // clear to the west
      expect(r.cells.length, 2, reason: 'kept original size');
      expect(r.cells.every((c) => !blocked.contains(c)), isTrue);
    });

    test('PARTIAL space: shrinks to fit the gap', () {
      final shape = CardShape.rect(2, 3, 3, 1); // cols 2-4, row 3
      final blocked = CardShape.rect(2, 3, 4, 1).cells; // over it + one east; west edge is close
      final r = runnerShape(shape, blocked, CardinalEdge.west, m)!;
      expect(r.cells.length, lessThan(3), reason: 'shrank to fit');
      expect(r.cells, isNotEmpty);
      expect(r.cells.every((c) => !blocked.contains(c) && m.cellInBounds(c)), isTrue);
    });

    test('NO room in the retreat path: a single open adjacent cell toward the retreat', () {
      // Block a whole region around+above (5,5) so the north slide finds nothing, leaving only the
      // (4,4) diagonal open — the 1x1 fallback must land there.
      final shape = CardShape({const CellIndex(5, 5)});
      final blocked = <CellIndex>{
        for (var c = 3; c <= 7; c++)
          for (var r = 0; r <= 6; r++)
            if (!(c == 5 && r == 5) && !(c == 4 && r == 4)) CellIndex(c, r),
      };
      final r = runnerShape(shape, blocked, CardinalEdge.north, m)!;
      expect(r.cells.length, 1);
      expect(r.cells.first, const CellIndex(4, 4), reason: 'the one open adjacent cell');
    });

    test('NO open cell at all: null (caller drops a 1x1 into the aggressor)', () {
      final shape = CardShape({const CellIndex(5, 5)});
      final blocked = <CellIndex>{
        for (var c = 3; c <= 7; c++)
          for (var r = 0; r <= 6; r++)
            if (!(c == 5 && r == 5)) CellIndex(c, r),
      };
      expect(runnerShape(shape, blocked, CardinalEdge.north, m), isNull);
    });
  });

  group('trimmed & bisected (unchanged)', () {
    test('partial overlap trims the overlapped column', () {
      final c = seed({'A': CardShape.rect(0, 4, 3, 3), 'B': CardShape.rect(3, 4, 3, 3)});
      final l = _move(c, 'A', 1, 0, m, pitch, ['A', 'B']);
      noneKilled(l);
      expect(l['B']!.cells, CardShape.rect(4, 4, 2, 3).cells);
    });

    test('a cut through the middle keeps the larger side', () {
      final c = seed({'A': CardShape.rect(0, 4, 4, 1), 'B': CardShape.rect(3, 3, 1, 5)});
      final l = _move(c, 'A', 0, 0, m, pitch, ['A', 'B']);
      noneKilled(l);
      expect(l['B']!.cells, CardShape.rect(3, 5, 1, 3).cells);
    });
  });

  group('retreat direction comes from the SMOTHER frame', () {
    test('east-trim then north-smother -> runner goes SOUTH, not west', () {
      final c = seed({'A': CardShape.rect(2, 4, 2, 2), 'B': CardShape.rect(4, 3, 1, 2)});
      final start = m.cellRect(const CellIndex(2, 4)).center;
      c.startMove('A', start);
      c.updateDrag(start + Offset(2 * pitch, 0)); // east 2 -> B trimmed (keeps its top, row 3)
      c.updateDrag(start + Offset(2 * pitch, -1 * pitch)); // + north 1 -> smother on the NORTH step
      final l = live(c, ['A', 'B']);
      noneKilled(l);
      noOverlap(l);
      final aMaxRow = l['A']!.cells.map((c) => c.row).reduce((a, b) => a > b ? a : b);
      expect(l['B']!.cells.every((cell) => cell.row > aMaxRow), isTrue,
          reason: 'B ran SOUTH because the smother happened on the north step; '
              'B=${l['B']!.cells}, A maxRow=$aMaxRow');
    });
  });

  group('a runner never displaces another card; never killed', () {
    test('C (not overlapped) is untouched while B runs', () {
      final c = seed({
        'A': CardShape.rect(0, 4, 3, 3),
        'B': CardShape.rect(4, 5, 1, 1),
        'C': CardShape.rect(9, 5, 1, 1), // far away, not overlapped
      });
      final cBefore = c.committedShape('C')!;
      final l = _move(c, 'A', 4, 0, m, pitch, ['A', 'B', 'C']);
      noneKilled(l);
      noOverlap(l);
      expect(l['C']!.cells, cBefore.cells, reason: 'C must not be displaced');
    });
  });
}
