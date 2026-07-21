/// A fluid, draggable dashboard grid for Flutter.
///
/// Cards live on a fixed field of square units, can be reshaped strip-by-
/// strip into organic polyomino silhouettes via edge and corner handles,
/// pushed through each other amoeba-style, and their user shaping persists
/// per viewport-width breakpoint.
library;

export 'src/controller.dart' show DragKind, DragSession, AmoebaGridController;
export 'src/engine/content_geometry.dart'
    show AmoebaBand, AmoebaCardGeometry, AmoebaRegion;
export 'src/engine/drag_engine.dart' show SubmissiveState;
export 'src/engine/grid_metrics.dart' show GridMetrics;
export 'src/engine/handles.dart' show GridHandle;
export 'src/foundation/cell.dart'
    show CardShape, CardinalEdge, CellIndex, CornerKind;
export 'src/foundation/config.dart' show AmoebaGridConfig;
export 'src/foundation/diagnostics.dart'
    show AmoebaGridDiagnostics, AmoebaGridEvent, AmoebaGridEventKind;
export 'src/foundation/storage.dart'
    show
        AmoebaGridLayoutData,
        AmoebaGridLayoutStore,
        AmoebaGridMemoryStorage,
        AmoebaGridStorage;
export 'src/widgets/card_chrome.dart' show AmoebaGridStyle;
export 'src/widgets/amoeba_card_scope.dart'
    show AmoebaCardScope, AmoebaContentArea, AmoebaPadding, AmoebaRegions;
export 'src/widgets/amoeba_flow.dart'
    show AmoebaColumn, AmoebaFlow, AmoebaFlowAlignment, AmoebaRow;
export 'src/widgets/amoeba_grid_view.dart' show AmoebaGridCard, AmoebaGridView;
export 'src/widgets/amoeba_list_view.dart' show AmoebaListView;
export 'src/widgets/amoeba_text.dart' show AmoebaText;
