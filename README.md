# fluid_draggable_grid

A fluid, draggable dashboard grid for Flutter. Cards live on a fixed field of
square units, reshape **strip-by-strip into organic polyomino silhouettes**,
push through each other **amoeba-style**, and remember the user's shaping per
viewport breakpoint.

Built for bento-style dashboards: dark-mode friendly, gap-respecting, and
rendered with `CustomPainter` outlines (proper inside/outside corner radii on
non-rectangular shapes).

## Highlights

- **Fixed grid, fluid cells** — you configure `columns x rows`; the square
  cell extent flexes between `minCellExtent` and `maxCellExtent` to fill the
  viewport. When it can't fit, the field pans in both axes
  (spreadsheet-style, powered by `TwoDimensionalScrollable`).
- **Cards are not just rectangles** — every open cell edge exposes a
  semicircular grab handle (progressively revealed hand icon on hover);
  dragging one extends or retracts *just that row/column strip*. Corners use
  standard both-axes rules with quarter-circle affordances tucked inside the
  outside corner radius.
- **50% snap previews** — dragging past the midpoint of the next column/row
  (gap midpoints included) snaps a preview outline; releasing commits it.
- **Aggressor / submissive collisions** — drag a card through another and the
  other card's edge defers like an amoeba: it cedes cells from the first
  aggressed edge, reverts the moment you pass beyond it (transient values),
  and records its ceded shape as its own if you drop while overlapping. A
  card that would shrink below 1x1 jumps to the opposite side instead.
- **Gaps always respected** — identical horizontal/vertical gutters between
  islands, including self-adjacent diagonal pinches.
- **Persistence with breakpoints** — user shaping is stored against the
  viewport-width breakpoint it was made at and resolved mobile-first, so a
  narrow window and a wide window can hold different layouts. Storage is a
  two-method interface; bring `shared_preferences`, a file, or a server.
- **Deep instrumentation, debug-only** — every hover, snap, trim, relocation,
  commit, and persistence event streams from `FluidGridDiagnostics`, gated
  behind a flag that is inert in release builds.

## Usage

```dart
final controller = FluidGridController(
  config: const FluidGridConfig(
    columns: 8,
    rows: 12,
    minCellExtent: 68,
    maxCellExtent: 128,
    gap: 12,
    insideCornerRadius: 12,
    outsideCornerRadius: 24,
  ),
  storage: MyPrefsStorage(), // optional; defaults to in-memory
);

FluidGridView(
  controller: controller,
  cards: [
    FluidGridCard(
      id: 'revenue',
      initialShape: CardShape.rect(0, 0, 3, 2), // user shaping overrides this
      child: const RevenueCard(),
    ),
    // ...
  ],
);
```

Persistence is two methods:

```dart
class MyPrefsStorage implements FluidGridStorage {
  @override
  Future<String?> read(String key) async => ...;
  @override
  Future<void> write(String key, String value) async => ...;
}
```

Instrumentation:

```dart
if (kDebugMode) {
  FluidGridDiagnostics.enabled = true;           // inert in release builds
  FluidGridDiagnostics.events.listen(onEvent);   // structured event stream
  // or FluidGridDiagnostics.attachDebugPrintLogger();
}
```

## Interaction model

| Gesture | Result |
| --- | --- |
| Drag card body | Move the whole card; snapped preview at 50% crossings |
| Drag side handle | Extend/retract that single row/column strip |
| Drag corner handle | Standard corner resize: both full edge segments |
| Drag near viewport edge | Auto-pans the field under the drag |
| Background drag / trackpad scroll | Pan the whole field in both axes |
| <kbd>Esc</kbd> during a drag | Cancel and revert everything |

## Example

`example/` contains a bento-style dashboard (macOS + web) with live config
sliders (gap, radii, cell extents), a diagnostics console overlay, and
`shared_preferences` persistence. Run it with:

```sh
cd example && flutter run -d macos
```

## Status

Early release. The API surface (`FluidGridConfig`, `FluidGridController`,
`FluidGridCard`, `FluidGridStorage`, `FluidGridDiagnostics`) is small on
purpose; feedback welcome.
