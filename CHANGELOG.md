## 0.1.0

Initial release.

- `FluidGridView` — fixed columns x rows field of square units, pannable in
  both axes (spreadsheet-style) with edge auto-scroll while dragging.
- Polyomino card shaping: per-strip side handles, standard-rules corner
  handles, 50% snap previews, inside/outside corner radii.
- Aggressor/submissive drag-through: other cards cede their first-aggressed
  edge amoeba-style, revert when cleared, commit on drop, and relocate when
  they'd drop below 1x1.
- Mobile-first persisted layout overrides per viewport-width breakpoint via
  a pluggable `FluidGridStorage`.
- Debug-only instrumentation stream (`FluidGridDiagnostics`).
