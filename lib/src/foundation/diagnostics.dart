import 'dart:async';

import 'package:flutter/foundation.dart';

/// Categories of instrumentation events emitted by the grid.
enum FluidGridEventKind {
  metricsResolved,
  handleHoverEnter,
  handleHoverExit,
  pointerDown,
  gestureAccepted,
  gestureRejected,
  dragStart,
  dragUpdate,
  previewChanged,
  submissiveTrimmed,
  submissiveRelocated,
  submissiveReverted,
  dragCancelled,
  layoutCommitted,
  layoutLoaded,
  layoutSaved,
  edgeAutoScroll,
}

/// One structured instrumentation event.
@immutable
class FluidGridEvent {
  const FluidGridEvent(this.kind, this.message, {this.data = const {}});

  final FluidGridEventKind kind;
  final String message;
  final Map<String, Object?> data;

  @override
  String toString() =>
      '[$kind] $message${data.isEmpty ? '' : ' $data'}';
}

/// Debug-only instrumentation for every detail of what the grid is doing.
///
/// Events only flow when [enabled] is true AND the app is running in debug
/// mode ([kDebugMode]); in release builds emission is a no-op regardless of
/// the flag, so instrumentation can be left wired up in production code.
///
/// ```dart
/// FluidGridDiagnostics.enabled = true;
/// FluidGridDiagnostics.events.listen(print);
/// // or simply:
/// FluidGridDiagnostics.attachDebugPrintLogger();
/// ```
abstract final class FluidGridDiagnostics {
  /// Master switch. Only honored in debug mode.
  static bool enabled = false;

  static bool get isActive => kDebugMode && enabled;

  static final StreamController<FluidGridEvent> _controller =
      StreamController<FluidGridEvent>.broadcast();

  /// Broadcast stream of grid events (empty unless [isActive]).
  static Stream<FluidGridEvent> get events => _controller.stream;

  static StreamSubscription<FluidGridEvent>? _printSubscription;

  /// Pipes every event through [debugPrint] with a `[fluid_grid]` prefix.
  static void attachDebugPrintLogger() {
    _printSubscription ??=
        events.listen((e) => debugPrint('[fluid_grid] $e'));
  }

  static void detachDebugPrintLogger() {
    _printSubscription?.cancel();
    _printSubscription = null;
  }

  /// Emits an event. Cheap no-op when inactive; callers on hot paths should
  /// still prefer checking [isActive] before building expensive `data` maps.
  static void emit(
    FluidGridEventKind kind,
    String message, [
    Map<String, Object?> data = const {},
  ]) {
    if (!isActive) return;
    _controller.add(FluidGridEvent(kind, message, data: data));
  }
}
