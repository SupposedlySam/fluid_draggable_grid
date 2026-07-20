import 'package:flutter/foundation.dart';

/// Immutable configuration for a [FluidGridView], supplied once at app init.
///
/// The grid is a fixed field of [columns] x [rows] square cells. Each cell's
/// pixel extent is resolved responsively per viewport: the grid tries to fit
/// every column into the viewport width, clamped between [minCellExtent] and
/// [maxCellExtent]. When the viewport is too small to fit all columns at
/// [minCellExtent] the grid overflows and can be panned in both axes.
@immutable
class FluidGridConfig {
  const FluidGridConfig({
    this.columns = 8,
    this.rows = 12,
    this.minCellExtent = 72,
    this.maxCellExtent = 160,
    this.gap = 12,
    this.insideCornerRadius = 10,
    this.outsideCornerRadius = 22,
    this.breakpoints = defaultBreakpoints,
  })  : assert(columns > 0),
        assert(rows > 0),
        assert(minCellExtent > 0),
        assert(maxCellExtent >= minCellExtent),
        assert(gap >= 0),
        assert(insideCornerRadius >= 0),
        assert(outsideCornerRadius >= 0);

  /// Fixed number of columns in the grid.
  final int columns;

  /// Fixed number of rows in the grid.
  final int rows;

  /// Minimum pixel size of one square grid unit.
  final double minCellExtent;

  /// Maximum pixel size of one square grid unit.
  final double maxCellExtent;

  /// Gap between adjacent cells, identical horizontally and vertically.
  /// Cards inset themselves by `gap / 2` inside their cell footprint, so the
  /// gap is always respected between adjacent cards.
  final double gap;

  /// Corner radius applied to concave (inside) corners of a card outline.
  final double insideCornerRadius;

  /// Corner radius applied to convex (outside) corners of a card outline.
  final double outsideCornerRadius;

  /// Ascending viewport-width breakpoints used to key persisted layouts.
  /// Layout overrides are stored against the breakpoint active when the user
  /// edited, and resolved mobile-first (largest breakpoint <= current width
  /// wins, falling back toward zero).
  final List<double> breakpoints;

  /// Material 3 window-class edges.
  static const List<double> defaultBreakpoints = [0, 600, 905, 1240, 1600];

  /// The breakpoint bucket for a given viewport width (mobile-first).
  double bucketFor(double viewportWidth) {
    var bucket = breakpoints.first;
    for (final b in breakpoints) {
      if (b <= viewportWidth) bucket = b;
    }
    return bucket;
  }

  FluidGridConfig copyWith({
    int? columns,
    int? rows,
    double? minCellExtent,
    double? maxCellExtent,
    double? gap,
    double? insideCornerRadius,
    double? outsideCornerRadius,
    List<double>? breakpoints,
  }) {
    return FluidGridConfig(
      columns: columns ?? this.columns,
      rows: rows ?? this.rows,
      minCellExtent: minCellExtent ?? this.minCellExtent,
      maxCellExtent: maxCellExtent ?? this.maxCellExtent,
      gap: gap ?? this.gap,
      insideCornerRadius: insideCornerRadius ?? this.insideCornerRadius,
      outsideCornerRadius: outsideCornerRadius ?? this.outsideCornerRadius,
      breakpoints: breakpoints ?? this.breakpoints,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is FluidGridConfig &&
        other.columns == columns &&
        other.rows == rows &&
        other.minCellExtent == minCellExtent &&
        other.maxCellExtent == maxCellExtent &&
        other.gap == gap &&
        other.insideCornerRadius == insideCornerRadius &&
        other.outsideCornerRadius == outsideCornerRadius &&
        listEquals(other.breakpoints, breakpoints);
  }

  @override
  int get hashCode => Object.hash(columns, rows, minCellExtent, maxCellExtent,
      gap, insideCornerRadius, outsideCornerRadius, Object.hashAll(breakpoints));
}
