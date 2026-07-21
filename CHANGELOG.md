## Unreleased

- **Fix**: every corner radius flattened to a chamfer while a drag morph was
  animating, popping back to a round arc on settle. `lerpOutline` resampled
  both outlines to 96 evenly-spaced points and reconnected them as a straight
  polyline, leaving ~2 samples on a whole corner arc. The morph now scales
  its sample count with the perimeter and reconnects samples with midpoint
  quadratics — straight runs stay straight, corners stay round.

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
