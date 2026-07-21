## 0.3.0

- **New — `AmoebaGridConfig.bodyDragActivation`** (`BodyDragActivation`):
  controls how a drag on a card *body* begins.
  - `immediate` (default, unchanged behavior): a pan anywhere on the body
    moves the card — even through hit-opaque content.
  - `longPress`: a body move starts only after a ~350ms hold (then movement),
    feeding the same drag-engine path pans use. The card stops competing in
    the pan arena, so taps, drag-scrolls, and other gestures inside card
    content win instantly. On activation the card raises its lift cue as the
    pick-up signal. Edge/corner **handles keep immediate drag** in both modes —
    they are chrome, not content.

## 0.2.0

- **New — `AmoebaShell`**: shape-aware header/body card scaffold. The header pins
  inside the highest solid span that can fit it (never a notch, never a
  too-narrow arm); the body receives the full remaining shape below it, so flow
  widgets keep re-flowing through notches. Exists because the obvious
  compositions both fail — see its dartdoc.

- **Shape-following padding**: `CardOutline.trace(extraInset:)` erodes the
  outline uniformly (convex radii shrink, concave grow);
  `AmoebaCardGeometry.erodedPath(inset)` exposes it. **`AmoebaPadding` now
  clips its child to the eroded silhouette by default** (`clipToShape: false`
  to opt out) — padding hugs the edge the way rectangle padding hugs a
  rectangle, enforced no matter what the child paints. Content can no longer
  leak onto the page background through empty bounding-box regions.

- **`AmoebaListView` flow correctness**:
  - rows adopt the narrower span when they touch (or come within a
    geometry-derived clearance of) a horizontal notch/step edge, instead of
    rendering flush against it;
  - rows probe the outline's corner arcs and walk inward to clear them;
  - rows probe the SAME eroded surface `AmoebaPadding` clips to
    (`contentClip`), so the clip can never shear glyphs the layout thought
    were safe;
  - slots wholly outside the shape collapse instead of borrowing a distant
    span;
  - **flush sides**: a zero inset on any side (any combination) makes content
    run straight to that edge past the corner arcs — the rounded outline
    trims the corner pixels, like an edge-to-edge list in a rounded
    container. Non-zero insets keep the arc-probe behavior.

- **Fix — drag-morph chamfering**: `lerpOutline` resampled outlines into a
  coarse polyline, flattening every corner arc to a chamfer mid-morph.
  Samples now scale with perimeter and reconnect via midpoint quadratics —
  corners stay round while dragging.

- **Developer experience**:
  - `AmoebaGridDiagnostics.showPaddingOverlay` (+ `paddingOverlayInset`)
    paints every card's padding band translucent red in debug builds;
  - an `AmoebaListView` nested inside `AmoebaContentArea` (windowed,
    notch-free scope) warns in debug that rows will never re-flow;
  - a box/geometry width mismatch (plain `Padding` between the card and a
    flow widget) warns about broken span alignment.

- **Fix — pressing a card grabbed the WRONG card after a resize/re-layout.** `RawGestureDetector`
  constructs its recognizer once and only re-runs the *initializer* on rebuild, so the `GridMetrics`
  closed over in the recognizer's constructor (the pointer-down hit test) froze at first-build
  values while paint used fresh metrics. After the cell extent re-resolved — a window resize, or a
  drag/rearrange that changed the occupied bounds — hit-testing and painting used different cell
  sizes and a press grabbed a card offset from the pointer (worse the further it was scrolled). The
  hit test now reads the controller's live metrics. Regression test:
  `test/scroll_resize_hittest_test.dart`.

- **Fix — side-handle inward L-gesture.** Pulling a side handle IN and then perpendicular used to
  drop the perpendicular drag entirely (it fell through to a plain strip retract), so "pull in,
  then down" only ever carved a single row. The inward gesture now mirrors the outward one and
  removes the full notch block, deepening it along the perpendicular axis.

- **Fix — submissive resolution reworked to the runner model.** When an aggressor overlaps a card
  it now: cedes the overlap (**trimmed**); keeps the LARGER side when **bisected**; and when fully
  **smothered** becomes a **runner** that retreats OPPOSITE the aggressor's advance *at the smother
  frame* (not first contact) and takes **full space at its original size**, **shrinks to fit** a
  partial gap, or drops to a **1x1** (an open adjacent cell, or into the aggressor, which cedes that
  cell). A runner never displaces another card and is never killed. This replaces the previous
  chained "retreater-becomes-aggressor" behaviour, which could ping-pong two cards until one was
  flung across the grid, and could drop the smaller half of a bisect or vanish a cornered card.
  Covered by `test/submissive_ac_test.dart` and `test/resize_gesture_test.dart`.

## 0.1.0

- **New — `AmoebaListView`**: a fixed-extent, vertically-scrolling list whose rows RE-FLOW to
  the card's polyomino shape as they scroll — a row narrows when it scrolls up into a notch and
  sweeps to the full width where the card is solid. Re-queried every scroll frame, not laid out
  once; degrades to a plain list outside a fluid card.

- **Fix**: disposing an `AmoebaGridView` before any handle had been hovered
  threw *"Looking up a deactivated widget's ancestor is unsafe"*. The
  `_handleReveal` `AnimationController` was a lazy `late final`, so a view
  torn down without a hover lazily constructed it *inside* `dispose()`, where
  `createTicker`'s ancestor lookup runs on a deactivated element. It is now
  created in `initState`. Regression test added (`test/dispose_test.dart`).

## 0.0.1

Initial release.

- **AmoebaGridView** — a field of square units (config counts are minimums;
  the grid grows to fill wider viewports), pannable in both axes with edge
  auto-scroll while dragging.
- **Polyomino card shaping** — whole-edge side handles resize one strip at a
  time, with L-shaped gestures growing only the newly carved section;
  convex *and* concave corner handles follow standard both-axes rules.
  Previews snap at 50% cell crossings; inside/outside corner radii apply to
  every silhouette.
- **Amoeba collisions** — drag a card into another and the neighbor cedes
  its aggressed edge live, reverts when you pass beyond it, commits its
  ceded shape on drop, and relocates when it would shrink below 1x1.
- **Hit testing designed for fingers and pointers** — containment-first
  ownership, gutter midline splits between adjacent cards, sticky hover
  reveals (what you see is what you grab), exhaustively boundary-tested.
- **Shape-aware content** — AmoebaCardScope publishes per-card geometry;
  AmoebaContentArea (largest-rect safe area), AmoebaRegions
  (maximal-rectangle decomposition), AmoebaColumn/Row/Flow (band-based
  flow), AmoebaText (wraps around notches), AmoebaPadding (outline-aware:
  interior card edges respect padding too).
- **Persistence** — user shaping stored per viewport-width breakpoint,
  resolved mobile-first, through a two-method storage interface.
- **Instrumentation** — AmoebaGridDiagnostics streams every hover, snap,
  trim, relocation, and commit; debug-only, inert in release builds.
