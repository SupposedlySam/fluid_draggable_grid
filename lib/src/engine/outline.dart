import 'dart:ui';

import '../foundation/cell.dart';
import 'grid_metrics.dart';

/// A vertex of a card outline after gap insetting, before rounding.
class OutlineCorner {
  OutlineCorner(this.point, this.incoming, this.outgoing);

  final Offset point;

  /// Unit direction of the edge arriving at this corner.
  final Offset incoming;

  /// Unit direction of the edge leaving this corner.
  final Offset outgoing;

  /// Convex (outside) corners turn clockwise when tracing the outline
  /// clockwise in screen coordinates (y down).
  bool get isConvex =>
      incoming.dx * outgoing.dy - incoming.dy * outgoing.dx > 0;
}

/// Builds the pixel outline of a polyomino [CardShape]: tile-union boundary,
/// inset by gap/2, with outside/inside corner radii applied.
///
/// Cards that touch only diagonally within one shape are traced as a pinch;
/// after insetting, the pinch opens up and the gap stays respected.
class CardOutline {
  CardOutline._(this.paths, this.corners);

  /// One closed path per boundary loop (holes produce inner loops, which
  /// combine correctly with [PathFillType.evenOdd]).
  final Path paths;

  final List<OutlineCorner> corners;

  static CardOutline trace(CardShape shape, GridMetrics metrics) {
    final loops = _traceLoops(shape);
    final path = Path()..fillType = PathFillType.evenOdd;
    final allCorners = <OutlineCorner>[];
    for (final loop in loops) {
      final corners = _insetLoop(loop, shape, metrics);
      allCorners.addAll(corners);
      _appendRounded(path, corners, metrics);
    }
    return CardOutline._(path, allCorners);
  }

  /// Traces boundary loops in grid-vertex coordinates, clockwise (interior
  /// on the right in y-down screen space).
  static List<List<CellIndex>> _traceLoops(CardShape shape) {
    // Directed boundary edges keyed by start vertex. Vertex (c, r) is the
    // top-left corner of cell (c, r).
    final edges = <CellIndex, List<CellIndex>>{};
    void addEdge(CellIndex from, CellIndex to) =>
        (edges[from] ??= []).add(to);

    for (final cell in shape.cells) {
      final c = cell.col, r = cell.row;
      if (!shape.contains(c, r - 1)) {
        addEdge(CellIndex(c, r), CellIndex(c + 1, r)); // north edge, east-bound
      }
      if (!shape.contains(c + 1, r)) {
        addEdge(CellIndex(c + 1, r), CellIndex(c + 1, r + 1)); // east, south
      }
      if (!shape.contains(c, r + 1)) {
        addEdge(CellIndex(c + 1, r + 1), CellIndex(c, r + 1)); // south, west
      }
      if (!shape.contains(c - 1, r)) {
        addEdge(CellIndex(c, r + 1), CellIndex(c, r)); // west, north-bound
      }
    }

    final loops = <List<CellIndex>>[];
    while (edges.isNotEmpty) {
      final start = edges.keys.first;
      final loop = <CellIndex>[start];
      var current = start;
      CellIndex? arrivedFrom;
      while (true) {
        final candidates = edges[current];
        if (candidates == null || candidates.isEmpty) break;
        CellIndex next;
        if (candidates.length == 1) {
          next = candidates.removeLast();
        } else {
          // Pinched vertex (diagonal contact): take the sharpest right turn
          // relative to the incoming direction to keep loops simple.
          next = _rightmostTurn(arrivedFrom ?? current, current, candidates);
          candidates.remove(next);
        }
        if (candidates.isEmpty) edges.remove(current);
        arrivedFrom = current;
        current = next;
        if (current == start) break;
        loop.add(current);
      }
      if (loop.length >= 4) loops.add(loop);
    }
    return loops;
  }

  static CellIndex _rightmostTurn(
      CellIndex from, CellIndex at, List<CellIndex> candidates) {
    final inDir = (at.col - from.col, at.row - from.row);
    var best = candidates.first;
    var bestScore = -3;
    for (final candidate in candidates) {
      final outDir = (candidate.col - at.col, candidate.row - at.row);
      // cross > 0 is a right (clockwise) turn in y-down coordinates.
      final cross = inDir.$1 * outDir.$2 - inDir.$2 * outDir.$1;
      final dot = inDir.$1 * outDir.$1 + inDir.$2 * outDir.$2;
      // Preference: right turn (2) > straight (1) > left turn (0).
      final score = cross > 0
          ? 2
          : cross == 0 && dot > 0
              ? 1
              : 0;
      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }
    return best;
  }

  /// Converts a vertex loop to pixel space, merges collinear runs, and insets
  /// every edge toward the interior by gap/2.
  static List<OutlineCorner> _insetLoop(
      List<CellIndex> loop, CardShape shape, GridMetrics metrics) {
    // Collapse collinear vertices first.
    final vertices = <CellIndex>[];
    for (var i = 0; i < loop.length; i++) {
      final prev = loop[(i - 1 + loop.length) % loop.length];
      final curr = loop[i];
      final next = loop[(i + 1) % loop.length];
      final d1 = (curr.col - prev.col, curr.row - prev.row);
      final d2 = (next.col - curr.col, next.row - curr.row);
      if (d1 != d2) vertices.add(curr);
    }

    final inset = metrics.gap / 2;
    final points = <Offset>[];
    final dirs = <Offset>[];
    for (var i = 0; i < vertices.length; i++) {
      final curr = vertices[i];
      final next = vertices[(i + 1) % vertices.length];
      final origin = metrics.tileOrigin(curr.col, curr.row);
      points.add(origin);
      final d = Offset((next.col - curr.col).sign.toDouble(),
          (next.row - curr.row).sign.toDouble());
      dirs.add(d);
    }

    // Shift each edge toward its interior-side normal (rotate direction 90°
    // clockwise in y-down space), then re-intersect consecutive edges. All
    // edges are axis-aligned, so the intersection just mixes coordinates.
    final corners = <OutlineCorner>[];
    for (var i = 0; i < points.length; i++) {
      final prevDir = dirs[(i - 1 + dirs.length) % dirs.length];
      final currDir = dirs[i];
      final prevNormal = Offset(-prevDir.dy, prevDir.dx);
      final currNormal = Offset(-currDir.dy, currDir.dx);
      final prevPoint = points[(i - 1 + points.length) % points.length] +
          prevNormal * inset;
      final currPoint = points[i] + currNormal * inset;
      // Intersection of the shifted previous edge (through prevPoint, along
      // prevDir) and shifted current edge (through currPoint, along currDir).
      final vertex = prevDir.dx != 0
          ? Offset(currPoint.dx, prevPoint.dy)
          : Offset(prevPoint.dx, currPoint.dy);
      corners.add(OutlineCorner(vertex, prevDir, currDir));
    }
    return corners;
  }

  static void _appendRounded(
      Path path, List<OutlineCorner> corners, GridMetrics metrics) {
    if (corners.isEmpty) return;
    final outside = metrics.config.outsideCornerRadius;
    final inside = metrics.config.insideCornerRadius;

    // Radius per corner, clamped so neighboring arcs never overlap.
    final radii = List<double>.generate(corners.length, (i) {
      final corner = corners[i];
      final desired = corner.isConvex ? outside : inside;
      final prev = corners[(i - 1 + corners.length) % corners.length];
      final next = corners[(i + 1) % corners.length];
      final inLen = (corner.point - prev.point).distance;
      final outLen = (next.point - corner.point).distance;
      return [desired, inLen / 2, outLen / 2]
          .reduce((a, b) => a < b ? a : b);
    });

    for (var i = 0; i <= corners.length; i++) {
      final corner = corners[i % corners.length];
      final r = radii[i % corners.length];
      final arcStart = corner.point - corner.incoming * r;
      final arcEnd = corner.point + corner.outgoing * r;
      if (i == 0) {
        path.moveTo(arcStart.dx, arcStart.dy);
      } else {
        path.lineTo(arcStart.dx, arcStart.dy);
      }
      if (i == corners.length) break;
      if (r > 0) {
        path.arcToPoint(
          arcEnd,
          radius: Radius.circular(r),
          clockwise: corner.isConvex,
        );
      } else {
        path.lineTo(corner.point.dx, corner.point.dy);
      }
    }
    path.close();
  }
}

/// Interpolates between two arbitrary outlines by resampling both to the
/// same number of points along their path metrics. Cheap enough for
/// per-frame use and produces the organic "amoeba" morph between cell-
/// quantized shapes.
///
/// Corner fidelity: a corner arc is a small fraction of the perimeter, so
/// with a fixed coarse sample count it collapses to a straight chamfer for
/// the duration of the morph. Two measures keep corners round: the sample
/// count scales with the longer path's perimeter (unless an explicit
/// [samples] is passed), and the resampled points are reconnected with
/// midpoint quadratics instead of a raw polyline — collinear runs stay
/// perfectly straight while any residual faceting at corners is smoothed.
Path lerpOutline(Path from, Path to, double t, {int? samples}) {
  if (t <= 0) return from;
  if (t >= 1) return to;
  final count = samples ??
      (_longestLoop(from, to) / 3).ceil().clamp(96, 480).toInt();
  final a = _sample(from, count);
  final b = _sample(to, count);
  final loops = a.length < b.length ? a.length : b.length;
  final out = Path()..fillType = PathFillType.evenOdd;
  for (var loop = 0; loop < loops; loop++) {
    final pa = a[loop];
    final pb = b[loop];
    final points = List<Offset>.generate(
        count, (i) => Offset.lerp(pa[i], pb[i], t)!);
    // Closed-loop midpoint smoothing: move to the first edge midpoint, then
    // one quadratic per point with that point as control and the next edge
    // midpoint as endpoint.
    Offset mid(int i) =>
        (points[i % count] + points[(i + 1) % count]) / 2;
    final start = mid(0);
    out.moveTo(start.dx, start.dy);
    for (var i = 1; i <= count; i++) {
      final control = points[i % count];
      final end = mid(i);
      out.quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
    }
    out.close();
  }
  // Loops present in only one shape fade abruptly; acceptable for the rare
  // split/merge frame.
  return out;
}

double _longestLoop(Path from, Path to) {
  var longest = 0.0;
  for (final path in [from, to]) {
    for (final metric in path.computeMetrics()) {
      if (metric.length > longest) longest = metric.length;
    }
  }
  return longest;
}

List<List<Offset>> _sample(Path path, int samples) {
  final result = <List<Offset>>[];
  for (final metric in path.computeMetrics()) {
    final points = <Offset>[];
    for (var i = 0; i < samples; i++) {
      final distance = metric.length * i / samples;
      final tangent = metric.getTangentForOffset(distance);
      if (tangent != null) points.add(tangent.position);
    }
    if (points.length == samples) result.add(points);
  }
  return result;
}
