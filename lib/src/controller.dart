import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'engine/drag_engine.dart';
import 'engine/grid_metrics.dart';
import 'engine/handles.dart';
import 'foundation/cell.dart';
import 'foundation/config.dart';
import 'foundation/diagnostics.dart';
import 'foundation/storage.dart';

/// What kind of drag a session is.
enum DragKind { move, resize }

/// Live state of an in-flight drag.
class DragSession {
  DragSession({
    required this.kind,
    required this.cardId,
    required this.originShape,
    required this.startPointer,
    this.handle,
  });

  final DragKind kind;
  final String cardId;

  /// The aggressor's committed shape when the drag began.
  final CardShape originShape;

  final Offset startPointer;

  /// Set for resize sessions.
  final GridHandle? handle;

  Offset pointer = Offset.zero;

  /// Snapped candidate shape shown as the preview.
  late CardShape preview = originShape;

  /// The preview from the previous update — the aggressor's last position
  /// before the current one, used to determine which submissive edge a
  /// fresh contact came through (edge-to-edge geometry).
  late CardShape lastPreview = originShape;

  /// Transient reactions of other cards, keyed by card id. Cards drop out
  /// of this map the moment they stop overlapping (submitted values are
  /// transient) and their recorded entry edge clears with them, so a
  /// re-contact from a different side computes a fresh entry edge without
  /// dropping the card.
  final Map<String, SubmissiveState> submissives = {};

  /// Aggressed edge per card, held only while contact lasts.
  final Map<String, CardinalEdge> entryEdges = {};

  /// Retreat direction per SMOTHERED card, captured at the moment of smother
  /// (opposite the aggressor's advance that frame) and held stable while the
  /// card stays a runner, so the retreat tracks the smother, not first contact.
  final Map<String, CardinalEdge> smotherDirs = {};

  /// Last snapped cell-delta, used to derive the approach direction when a
  /// new card is first contacted.
  (int, int) lastCellDelta = (0, 0);

  Offset get pixelDelta => pointer - startPointer;
}

/// Owns committed card shapes, drag sessions, and persistence.
///
/// The grid widget drives this controller from gestures; apps can also read
/// it to observe layout state. Committed shapes resolve as:
/// user override for the active width bucket (mobile-first fallback through
/// smaller buckets) -> programmatic initial shape.
class AmoebaGridController extends ChangeNotifier {
  AmoebaGridController({
    required this.config,
    AmoebaGridStorage? storage,
    String? storageKey,
  }) : _store = AmoebaGridLayoutStore(
          storage ?? AmoebaGridMemoryStorage(),
          storageKey: storageKey ?? AmoebaGridLayoutStore.defaultKey,
        );

  final AmoebaGridConfig config;
  final AmoebaGridLayoutStore _store;

  AmoebaGridLayoutData _layoutData = const AmoebaGridLayoutData.empty();
  final Map<String, CardShape> _initialShapes = {};
  final Map<String, CardShape> _committed = {};

  GridMetrics? _metrics;
  DragSession? _session;
  bool _loaded = false;

  GridMetrics? get metrics => _metrics;
  DragSession? get session => _session;
  bool get isDragging => _session != null;
  bool get isLoaded => _loaded;

  Iterable<String> get cardIds => _initialShapes.keys;

  /// Columns/rows needed to cover every committed shape. The grid view
  /// feeds these back into metrics resolution so user-placed cards always
  /// stay inside the pannable field, however small the window gets.
  int get occupiedColumns => _committed.values
      .fold(0, (max, shape) => shape.maxCol + 1 > max ? shape.maxCol + 1 : max);

  int get occupiedRows => _committed.values
      .fold(0, (max, shape) => shape.maxRow + 1 > max ? shape.maxRow + 1 : max);

  /// Registers the programmatic cards. Called by the widget; safe to call
  /// again when the card list changes.
  void registerCards(Map<String, CardShape> initialShapes) {
    if (mapEquals(initialShapes, _initialShapes)) return;
    _initialShapes
      ..clear()
      ..addAll(initialShapes);
    _recomputeCommitted();
  }

  /// Loads persisted user shaping. User values override initial values.
  Future<void> load() async {
    _layoutData = await _store.load();
    _loaded = true;
    _recomputeCommitted();
  }

  /// Called by the widget whenever the resolved metrics change (viewport
  /// resize). A width-bucket change re-resolves overrides, so different
  /// viewport sizes can have different layouts.
  void updateMetrics(GridMetrics metrics) {
    final previous = _metrics;
    if (previous == metrics) return;
    _metrics = metrics;
    final bucketChanged = previous == null ||
        config.bucketFor(previous.viewportSize.width) !=
            config.bucketFor(metrics.viewportSize.width);
    AmoebaGridDiagnostics.emit(AmoebaGridEventKind.metricsResolved,
        'metrics resolved', {
      'cellExtent': metrics.cellExtent,
      'viewport': '${metrics.viewportSize}',
      'bucket': config.bucketFor(metrics.viewportSize.width),
    });
    if (bucketChanged) {
      _recomputeCommitted();
    } else {
      notifyListeners();
    }
  }

  void _emitCommittedLayout(String reason) {
    if (!AmoebaGridDiagnostics.isActive) return;
    AmoebaGridDiagnostics.emit(AmoebaGridEventKind.layoutCommitted, reason, {
      for (final entry in _committed.entries)
        entry.key: '(${entry.value.minCol},${entry.value.minRow})..'
            '(${entry.value.maxCol},${entry.value.maxRow}) '
            '${entry.value.cells.length}c',
    });
  }

  void _recomputeCommitted() {
    final width = _metrics?.viewportSize.width;
    _committed.clear();
    for (final entry in _initialShapes.entries) {
      final override = width == null
          ? null
          : _layoutData.resolve(entry.key, width, config);
      _committed[entry.key] = override ?? entry.value;
    }
    _emitCommittedLayout('committed layout recomputed');
    notifyListeners();
  }

  /// The shape a card is currently showing: transient while a drag session
  /// touches it, committed otherwise.
  CardShape? effectiveShape(String cardId) {
    final session = _session;
    if (session != null) {
      if (session.cardId == cardId) return session.preview;
      final submissive = session.submissives[cardId];
      if (submissive != null) return submissive.shape;
    }
    return _committed[cardId];
  }

  CardShape? committedShape(String cardId) => _committed[cardId];

  // --- Drag lifecycle -----------------------------------------------------

  void startMove(String cardId, Offset pointer) {
    final origin = _committed[cardId];
    final metrics = _metrics;
    if (origin == null || metrics == null) return;
    _session = DragSession(
      kind: DragKind.move,
      cardId: cardId,
      originShape: origin,
      startPointer: pointer,
    )..pointer = pointer;
    AmoebaGridDiagnostics.emit(AmoebaGridEventKind.dragStart, 'move start',
        {'card': cardId, 'origin': '$origin'});
    notifyListeners();
  }

  void startResize(GridHandle handle, Offset pointer) {
    final origin = _committed[handle.cardId];
    final metrics = _metrics;
    if (origin == null || metrics == null) return;
    _session = DragSession(
      kind: DragKind.resize,
      cardId: handle.cardId,
      originShape: origin,
      startPointer: pointer,
      handle: handle,
    )..pointer = pointer;
    AmoebaGridDiagnostics.emit(AmoebaGridEventKind.dragStart, 'resize start',
        {'card': handle.cardId, 'handle': handle.debugLabel});
    notifyListeners();
  }

  void updateDrag(Offset pointer) {
    final session = _session;
    final metrics = _metrics;
    if (session == null || metrics == null) return;
    session.pointer = pointer;

    final previousPreview = session.preview;
    session.preview = switch (session.kind) {
      DragKind.move => _movePreview(session, metrics),
      DragKind.resize => _resizePreview(session, metrics),
    };
    session.lastPreview = previousPreview;

    if (session.preview != previousPreview) {
      AmoebaGridDiagnostics.emit(
          AmoebaGridEventKind.previewChanged, 'preview snapped', {
        'card': session.cardId,
        'cells': session.preview.cells.length,
      });
    }

    _resolveSubmissives(session, metrics);
    notifyListeners();
  }

  CardShape _movePreview(DragSession session, GridMetrics metrics) {
    final delta = session.pixelDelta;
    var dc = metrics.snapSteps(delta.dx);
    var dr = metrics.snapSteps(delta.dy);
    final origin = session.originShape;
    // Clamp the translation so the whole shape stays on the grid.
    dc = dc.clamp(-origin.minCol, metrics.columns - 1 - origin.maxCol);
    dr = dr.clamp(-origin.minRow, metrics.rows - 1 - origin.maxRow);
    final previous = session.lastCellDelta;
    if (previous != (dc, dr)) session.lastCellDelta = (dc, dr);
    return origin.translate(dc, dr);
  }

  CardShape _resizePreview(DragSession session, GridMetrics metrics) {
    final handle = session.handle!;
    final delta = session.pixelDelta;
    final (hEdge, vEdge) = handle.axes;

    int stepsAlong(CardinalEdge edge) {
      final outward = edge.outward;
      final along = delta.dx * outward.$1 + delta.dy * outward.$2;
      return metrics.snapSteps(along);
    }

    if (handle.isCorner) {
      return applyCornerResize(session.originShape, handle,
          stepsAlong(hEdge!), stepsAlong(vEdge!), metrics);
    }
    // Sides support the L-gesture: primary axis carves the new section,
    // perpendicular movement grows only that new section.
    final edge = handle.edge!;
    final perpDelta = edge.isHorizontalDrag ? delta.dy : delta.dx;
    return applySideResize(session.originShape, handle.cell, edge,
        stepsAlong(edge), metrics.snapSteps(perpDelta), metrics);
  }

  void _resolveSubmissives(DragSession session, GridMetrics metrics) {
    final previous = Map.of(session.submissives);
    session.submissives.clear();
    final aggressor = session.preview.cells;
    final resolved = <String, SubmissiveState>{};
    final ceded = <CellIndex>{};
    final contacted = <String>{};

    // Cells of every card except [id] and the aggressor — a runner packs AROUND these and never
    // displaces them. Uses already-resolved transient shapes so runners also avoid each other.
    Set<CellIndex> othersOf(String id) {
      final out = <CellIndex>{};
      for (final other in _committed.keys) {
        if (other == id || other == session.cardId) continue;
        out.addAll((resolved[other]?.shape ?? _committed[other]!).cells);
      }
      return out;
    }

    for (final id in _committed.keys) {
      if (id == session.cardId) continue;
      final committed = _committed[id]!;
      if (!committed.cells.any(aggressor.contains)) {
        session.entryEdges.remove(id);
        session.smotherDirs.remove(id);
        continue;
      }
      contacted.add(id);
      final entryEdge = session.entryEdges.putIfAbsent(
          id, () => _entryEdgeFor(committed, session, _approachDirection(session)));

      // Trimmed (partial overlap) / bisected (split — keep the larger side). AC #1, #2.
      final trimmed = trimSubmissive(committed, aggressor, entryEdge);
      if (trimmed != null) {
        resolved[id] =
            SubmissiveState(entryEdge: entryEdge, shape: trimmed, relocated: false);
        session.smotherDirs.remove(id);
        if (previous[id]?.shape != trimmed) {
          AmoebaGridDiagnostics.emit(AmoebaGridEventKind.submissiveTrimmed, 'trimmed',
              {'card': id, 'cells': trimmed.cells.length});
        }
        continue;
      }

      // SMOTHERED -> runner. The retreat direction is captured at the smother FRAME (opposite the
      // aggressor's advance that frame) and held stable, so it tracks the smother, not first contact.
      final retreatDir =
          session.smotherDirs.putIfAbsent(id, () => _advanceDir(session).opposite);
      final blocked = {...aggressor, ...othersOf(id)};
      final runner = runnerShape(committed, blocked, retreatDir, metrics);
      final CardShape shape;
      if (runner != null) {
        shape = runner; // full-size, partial shrink, or an open adjacent 1x1
      } else {
        // No open cell anywhere: drop a 1x1 into the aggressor's footprint (its retreat-facing end)
        // and make the AGGRESSOR cede that cell, so the runner survives and nothing overlaps.
        final (dc, dr) = retreatDir.outward;
        final into = committed.cells.reduce(
            (a, b) => (a.col * dc + a.row * dr) >= (b.col * dc + b.row * dr) ? a : b);
        shape = CardShape({into});
        ceded.add(into);
      }
      resolved[id] =
          SubmissiveState(entryEdge: entryEdge, shape: shape, relocated: true);
      AmoebaGridDiagnostics.emit(AmoebaGridEventKind.submissiveRelocated, 'runner',
          {'card': id, 'dir': retreatDir.name, 'cells': shape.cells.length});
    }

    // The aggressor gives up any cells a cornered 1x1 runner had to take.
    if (ceded.isNotEmpty) {
      final kept = session.preview.cells.where((c) => !ceded.contains(c));
      if (kept.isNotEmpty) {
        final reduced = CardShape(kept);
        session.preview =
            reduced.isConnected ? reduced : reduced.largestComponent;
      }
    }

    session.submissives.addAll(resolved);
    session.entryEdges.removeWhere((id, _) => !contacted.contains(id));
    session.smotherDirs.removeWhere((id, _) => !contacted.contains(id));
    for (final id in previous.keys) {
      if (!session.submissives.containsKey(id)) {
        AmoebaGridDiagnostics.emit(AmoebaGridEventKind.submissiveReverted,
            'no longer overlapped; reverted', {'card': id});
      }
    }
  }

  /// The dominant direction the aggressor ADVANCED this frame — the growth of a resize or the shift
  /// of a move (its preview vs the previous one). Captured at the smother frame to aim the retreat.
  CardinalEdge _advanceDir(DragSession session) {
    (double, double) centroid(Iterable<CellIndex> cells) {
      var sx = 0.0, sy = 0.0, n = 0;
      for (final c in cells) {
        sx += c.col;
        sy += c.row;
        n++;
      }
      return n == 0 ? (0.0, 0.0) : (sx / n, sy / n);
    }

    final added = session.preview.cells.difference(session.lastPreview.cells);
    final (ox, oy) = centroid(session.lastPreview.cells);
    final (nx, ny) =
        added.isNotEmpty ? centroid(added) : centroid(session.preview.cells);
    final dx = nx - ox, dy = ny - oy;
    if (dx == 0 && dy == 0) return _approachDirection(session);
    if (dx.abs() >= dy.abs()) {
      return dx >= 0 ? CardinalEdge.east : CardinalEdge.west;
    }
    return dy >= 0 ? CardinalEdge.south : CardinalEdge.north;
  }

  CardinalEdge _approachDirection(DragSession session) {
    if (session.kind == DragKind.resize) {
      final handle = session.handle!;
      if (!handle.isCorner) return handle.edge!;
      final (hEdge, vEdge) = handle.axes;
      final delta = session.pixelDelta;
      return delta.dx.abs() >= delta.dy.abs() ? hEdge! : vEdge!;
    }
    final delta = session.pixelDelta;
    if (delta.dx.abs() >= delta.dy.abs()) {
      return delta.dx >= 0 ? CardinalEdge.east : CardinalEdge.west;
    }
    return delta.dy >= 0 ? CardinalEdge.south : CardinalEdge.north;
  }

  /// The submissive edge the aggressor came through, decided edge-to-edge:
  /// where the aggressor sat immediately before this contact (its last
  /// preview) relative to the submissive. Falls back to the travel
  /// direction only when the geometry is ambiguous.
  CardinalEdge _entryEdgeFor(
      CardShape submissive, DragSession session, CardinalEdge approach) {
    final prior = session.lastPreview;
    CardinalEdge? horizontal;
    if (prior.maxCol < submissive.minCol) horizontal = CardinalEdge.west;
    if (prior.minCol > submissive.maxCol) horizontal = CardinalEdge.east;
    CardinalEdge? vertical;
    if (prior.maxRow < submissive.minRow) vertical = CardinalEdge.north;
    if (prior.minRow > submissive.maxRow) vertical = CardinalEdge.south;
    if (horizontal != null && vertical != null) {
      // Diagonal approach: the dominant travel axis decides.
      return approach.isHorizontalDrag ? horizontal : vertical;
    }
    return horizontal ?? vertical ?? approach.opposite;
  }

  /// Commits the aggressor's preview and every active submissive's transient
  /// shape, then persists into the active width bucket.
  Future<void> endDrag() async {
    final session = _session;
    final metrics = _metrics;
    if (session == null) return;
    _session = null;
    if (metrics == null) {
      notifyListeners();
      return;
    }

    final changed = <String, CardShape>{session.cardId: session.preview};
    for (final entry in session.submissives.entries) {
      changed[entry.key] = entry.value.shape;
    }
    _committed.addAll(changed);

    AmoebaGridDiagnostics.emit(AmoebaGridEventKind.layoutCommitted,
        'drag committed', {
      'aggressor': session.cardId,
      'submissives': session.submissives.keys.toList(),
    });
    notifyListeners();

    final bucket = config.bucketFor(metrics.viewportSize.width);
    _layoutData = _layoutData.withBucketShapes(bucket, changed);
    await _store.save(_layoutData);
  }

  void cancelDrag() {
    if (_session == null) return;
    AmoebaGridDiagnostics.emit(
        AmoebaGridEventKind.dragCancelled, 'drag cancelled',
        {'card': _session!.cardId});
    _session = null;
    notifyListeners();
  }

  /// Clears every persisted override and returns to programmatic shapes.
  Future<void> resetLayout() async {
    _layoutData = const AmoebaGridLayoutData.empty();
    await _store.save(_layoutData);
    _recomputeCommitted();
  }
}
