import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../foundation/cell.dart';
import 'grid_metrics.dart';
import 'outline_cache.dart';

/// One flow band: a slice of the card along the main axis whose available
/// cross-axis space is constant. For row bands (vertical flow) [start]/[end]
/// are top/bottom and [spans] are the free horizontal runs; for column bands
/// (horizontal flow) they are left/right with vertical runs. Adjacent cell
/// rows/columns with identical runs merge into one band bridging the gap,
/// matching the card's visual interior.
@immutable
class FluidBand {
  const FluidBand({
    required this.start,
    required this.end,
    required this.spans,
  });

  final double start;
  final double end;

  /// Free rects inside this band, sorted along the cross axis. Each rect's
  /// main-axis extent equals `end - start`.
  final List<Rect> spans;

  double get extent => end - start;
}

/// One rectangular sub-region of a card's polyomino, from the maximal-
/// rectangle decomposition. Regions are sorted by area descending;
/// region 0 is the largest inscribed rectangle.
@immutable
class FluidRegion {
  const FluidRegion({
    required this.index,
    required this.rect,
    required this.cellWidth,
    required this.cellHeight,
  });

  final int index;

  /// Card-local pixel rect (gaps between the region's own cells bridged).
  final Rect rect;

  final int cellWidth;
  final int cellHeight;

  bool get isLargest => index == 0;
}

/// Shape-aware layout data for one card, in card-local pixels (origin at
/// the shape's bounding rect top-left). Published to card content by
/// `FluidCardScope`; consumed by the Fluid* content widgets.
@immutable
class FluidCardGeometry {
  const FluidCardGeometry._({
    required this.shape,
    required this.metrics,
    required this.size,
    required this.path,
    required this.rowBands,
    required this.columnBands,
    required this.largestRect,
    required this.regions,
    required this.insets,
  });

  factory FluidCardGeometry.compute(CardShape shape, GridMetrics metrics) {
    final bounds = metrics.shapeBounds(shape);
    final origin = bounds.topLeft;
    final path = OutlineCache.instance
        .outlineFor(shape, metrics)
        .paths
        .shift(-origin);
    final regions = _decompose(shape, metrics, origin);
    return FluidCardGeometry._(
      shape: shape,
      metrics: metrics,
      size: bounds.size,
      path: path,
      rowBands: _bands(shape, metrics, origin, Axis.vertical),
      columnBands: _bands(shape, metrics, origin, Axis.horizontal),
      largestRect: regions.first.rect,
      regions: regions,
      insets: EdgeInsets.zero,
    );
  }

  final CardShape shape;
  final GridMetrics metrics;

  /// Local content box size (the card's bounding rect, minus [insets]).
  final Size size;

  /// The card outline in local coordinates (clip-accurate at rest).
  final Path path;

  /// Bands for vertical flow (FluidColumn, FluidText).
  final List<FluidBand> rowBands;

  /// Bands for horizontal flow (FluidRow).
  final List<FluidBand> columnBands;

  /// Largest rectangle fully inside the polyomino — the "safe area" clear
  /// of every notch.
  final Rect largestRect;

  /// Maximal-rectangle decomposition of the whole shape, area-descending.
  final List<FluidRegion> regions;

  /// Accumulated padding applied by FluidPadding / cropping, relative to
  /// the card's original content box.
  final EdgeInsets insets;

  /// A copy with [padding] carved off every side: local origin moves to
  /// (padding.left, padding.top), spans and regions are trimmed, and
  /// anything that falls outside disappears. Used by FluidPadding so nested
  /// fluid widgets keep seeing correct geometry.
  ///
  /// With [fromOutline] (the default), padding is applied against the card
  /// *outline*, not just the bounding box: any rect side that lies on an
  /// open card edge — including interior edges created by notches and steps
  /// — is inset, so content respects the padding on every card edge. Sides
  /// facing the card interior (bridged gaps, other regions) are untouched.
  FluidCardGeometry deflate(EdgeInsets padding, {bool fromOutline = true}) {
    final shifted = Offset(-padding.left, -padding.top);
    final newSize = Size(
      (size.width - padding.horizontal).clamp(0.0, double.infinity),
      (size.height - padding.vertical).clamp(0.0, double.infinity),
    );
    final window = Offset.zero & newSize;

    Rect? clip(Rect rect) {
      final inset =
          fromOutline ? _insetOutlineSides(rect, padding) : rect;
      final moved = inset.shift(shifted).intersect(window);
      return (moved.width <= 0 || moved.height <= 0) ? null : moved;
    }

    List<FluidBand> clipBands(List<FluidBand> bands, Axis axis) {
      final result = <FluidBand>[];
      for (final band in bands) {
        final spans = <Rect>[];
        for (final span in band.spans) {
          final clipped = clip(span);
          if (clipped != null) spans.add(clipped);
        }
        if (spans.isEmpty) continue;
        // Outline insets can trim spans of one band unevenly.
        var start = double.infinity;
        var end = double.negativeInfinity;
        for (final span in spans) {
          start = math.min(
              start, axis == Axis.vertical ? span.top : span.left);
          end = math.max(
              end, axis == Axis.vertical ? span.bottom : span.right);
        }
        result.add(FluidBand(start: start, end: end, spans: spans));
      }
      return result;
    }

    final newRegions = <FluidRegion>[];
    for (final region in regions) {
      final clipped = clip(region.rect);
      if (clipped == null) continue;
      newRegions.add(FluidRegion(
        index: newRegions.length,
        rect: clipped,
        cellWidth: region.cellWidth,
        cellHeight: region.cellHeight,
      ));
    }
    newRegions.sort((a, b) {
      final byArea = (b.rect.width * b.rect.height)
          .compareTo(a.rect.width * a.rect.height);
      return byArea;
    });
    final reindexed = [
      for (final (i, r) in newRegions.indexed)
        FluidRegion(
            index: i,
            rect: r.rect,
            cellWidth: r.cellWidth,
            cellHeight: r.cellHeight),
    ];

    return FluidCardGeometry._(
      shape: shape,
      metrics: metrics,
      size: newSize,
      path: path.shift(shifted),
      rowBands: clipBands(rowBands, Axis.vertical),
      columnBands: clipBands(columnBands, Axis.horizontal),
      largestRect: reindexed.isEmpty
          ? Rect.zero
          : reindexed.first.rect,
      regions: reindexed,
      insets: EdgeInsets.fromLTRB(
        insets.left + padding.left,
        insets.top + padding.top,
        insets.right + padding.right,
        insets.bottom + padding.bottom,
      ),
    );
  }

  /// A copy scoped to a rectangular window of the current box — used when a
  /// child is placed inside a region or the largest rect, so nested fluid
  /// widgets see plain rectangular geometry. Pure windowing: no
  /// outline-based insets.
  FluidCardGeometry cropTo(Rect window) => deflate(
        EdgeInsets.fromLTRB(
          window.left,
          window.top,
          (size.width - window.right).clamp(0.0, double.infinity),
          (size.height - window.bottom).clamp(0.0, double.infinity),
        ),
        fromOutline: false,
      );

  /// Insets each side of [rect] that lies on an open card edge. A side is
  /// "on the outline" when probe points just beyond it fall outside the
  /// card path — true for the bounding edges and for interior edges at
  /// notches/steps, false for sides facing bridged gaps inside the card.
  /// Mixed sides (partly open, partly interior) are inset conservatively so
  /// padding is guaranteed wherever the side meets the outline.
  Rect _insetOutlineSides(Rect rect, EdgeInsets padding) {
    const probeFractions = [0.15, 0.5, 0.85];
    bool openBeyondVertical(double x) => probeFractions.any((t) =>
        !path.contains(Offset(x, rect.top + rect.height * t)));
    bool openBeyondHorizontal(double y) => probeFractions.any((t) =>
        !path.contains(Offset(rect.left + rect.width * t, y)));

    return Rect.fromLTRB(
      openBeyondVertical(rect.left - 1)
          ? rect.left + padding.left
          : rect.left,
      openBeyondHorizontal(rect.top - 1) ? rect.top + padding.top : rect.top,
      openBeyondVertical(rect.right + 1)
          ? rect.right - padding.right
          : rect.right,
      openBeyondHorizontal(rect.bottom + 1)
          ? rect.bottom - padding.bottom
          : rect.bottom,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FluidCardGeometry &&
      other.shape == shape &&
      other.metrics == metrics &&
      other.size == size &&
      other.insets == insets;

  @override
  int get hashCode => Object.hash(shape, metrics, size, insets);

  // --- construction helpers -----------------------------------------------

  /// Contiguous runs of shape cells per row (vertical) or column
  /// (horizontal), merged across adjacent lines with identical runs so a
  /// band spans the bridged gap inside the card.
  static List<FluidBand> _bands(
      CardShape shape, GridMetrics metrics, Offset origin, Axis axis) {
    final vertical = axis == Axis.vertical;
    final lineStart = vertical ? shape.minRow : shape.minCol;
    final lineEnd = vertical ? shape.maxRow : shape.maxCol;

    List<(int, int)> runsFor(int line) {
      final positions = shape.cells
          .where((c) => (vertical ? c.row : c.col) == line)
          .map((c) => vertical ? c.col : c.row)
          .toList()
        ..sort();
      final runs = <(int, int)>[];
      for (final p in positions) {
        if (runs.isNotEmpty && runs.last.$2 == p - 1) {
          runs[runs.length - 1] = (runs.last.$1, p);
        } else {
          runs.add((p, p));
        }
      }
      return runs;
    }

    Rect lineCellRect(int line, int cross) => metrics.cellRect(
        vertical ? CellIndex(cross, line) : CellIndex(line, cross));

    final bands = <FluidBand>[];
    List<(int, int)>? openRuns;
    var openStartLine = 0;
    var lastLine = 0;

    void close(int endLine) {
      final runs = openRuns;
      if (runs == null) return;
      final firstRect = lineCellRect(openStartLine, runs.first.$1);
      final lastRect = lineCellRect(endLine, runs.first.$1);
      final start =
          (vertical ? firstRect.top : firstRect.left) -
              (vertical ? origin.dy : origin.dx);
      final end = (vertical ? lastRect.bottom : lastRect.right) -
          (vertical ? origin.dy : origin.dx);
      final spans = <Rect>[];
      for (final (a, b) in runs) {
        final aRect = lineCellRect(openStartLine, a).shift(-origin);
        final bRect = lineCellRect(openStartLine, b).shift(-origin);
        spans.add(vertical
            ? Rect.fromLTRB(aRect.left, start, bRect.right, end)
            : Rect.fromLTRB(start, aRect.top, end, bRect.bottom));
      }
      bands.add(FluidBand(start: start, end: end, spans: spans));
      openRuns = null;
    }

    for (var line = lineStart; line <= lineEnd; line++) {
      final runs = runsFor(line);
      if (runs.isEmpty) {
        close(lastLine);
        continue;
      }
      if (openRuns != null &&
          line == lastLine + 1 &&
          listEquals(openRuns, runs)) {
        lastLine = line;
        continue;
      }
      close(lastLine);
      openRuns = runs;
      openStartLine = line;
      lastLine = line;
    }
    close(lastLine);
    return bands;
  }

  /// Greedy maximal-rectangle decomposition: repeatedly peel the largest
  /// inscribed rectangle (histogram method) off the remaining cells.
  static List<FluidRegion> _decompose(
      CardShape shape, GridMetrics metrics, Offset origin) {
    final remaining = Set.of(shape.cells);
    final minCol = shape.minCol, minRow = shape.minRow;
    final cols = shape.maxCol - minCol + 1;
    final rows = shape.maxRow - minRow + 1;

    final regions = <FluidRegion>[];
    while (remaining.isNotEmpty && regions.length < 24) {
      final block = _largestBlock(remaining, minCol, minRow, cols, rows);
      final (c0, r0, w, h) = block;
      for (var c = c0; c < c0 + w; c++) {
        for (var r = r0; r < r0 + h; r++) {
          remaining.remove(CellIndex(c, r));
        }
      }
      final tl = metrics.cellRect(CellIndex(c0, r0));
      final br = metrics.cellRect(CellIndex(c0 + w - 1, r0 + h - 1));
      regions.add(FluidRegion(
        index: 0,
        rect: Rect.fromLTRB(tl.left, tl.top, br.right, br.bottom)
            .shift(-origin),
        cellWidth: w,
        cellHeight: h,
      ));
    }
    regions.sort((a, b) => (b.cellWidth * b.cellHeight)
        .compareTo(a.cellWidth * a.cellHeight));
    return [
      for (final (i, r) in regions.indexed)
        FluidRegion(
            index: i,
            rect: r.rect,
            cellWidth: r.cellWidth,
            cellHeight: r.cellHeight),
    ];
  }

  /// Largest rectangle of set cells (absolute cell coords), stack-based
  /// histogram scan.
  static (int, int, int, int) _largestBlock(
      Set<CellIndex> cells, int minCol, int minRow, int cols, int rows) {
    final heights = List.filled(cols, 0);
    var best = (minCol, minRow, 1, 1);
    var bestArea = 0;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        heights[c] =
            cells.contains(CellIndex(minCol + c, minRow + r))
                ? heights[c] + 1
                : 0;
      }
      final stack = <int>[];
      for (var c = 0; c <= cols; c++) {
        final h = c == cols ? 0 : heights[c];
        while (stack.isNotEmpty && heights[stack.last] >= h) {
          final height = heights[stack.removeLast()];
          final left = stack.isEmpty ? 0 : stack.last + 1;
          final width = c - left;
          if (height * width > bestArea) {
            bestArea = height * width;
            best = (minCol + left, minRow + r - height + 1, width, height);
          }
        }
        stack.add(c);
      }
    }
    return best;
  }
}
