/// A fluid, draggable dashboard grid for Flutter.
///
/// Cards live on a fixed field of square units, can be reshaped strip-by-
/// strip into organic polyomino silhouettes via edge and corner handles,
/// pushed through each other amoeba-style, and their user shaping persists
/// per viewport-width breakpoint.
library;

export 'src/controller.dart' show DragKind, DragSession, FluidGridController;
export 'src/engine/drag_engine.dart' show SubmissiveState;
export 'src/engine/grid_metrics.dart' show GridMetrics;
export 'src/engine/handles.dart' show GridHandle;
export 'src/foundation/cell.dart'
    show CardShape, CardinalEdge, CellIndex, CornerKind;
export 'src/foundation/config.dart' show FluidGridConfig;
export 'src/foundation/diagnostics.dart'
    show FluidGridDiagnostics, FluidGridEvent, FluidGridEventKind;
export 'src/foundation/storage.dart'
    show
        FluidGridLayoutData,
        FluidGridLayoutStore,
        FluidGridMemoryStorage,
        FluidGridStorage;
export 'src/widgets/card_chrome.dart' show FluidGridStyle;
export 'src/widgets/fluid_grid_view.dart' show FluidGridCard, FluidGridView;
