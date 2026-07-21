import 'package:flutter/widgets.dart';

import 'amoeba_card_scope.dart';

/// A vertically-scrolling, fixed-extent list whose rows RE-FLOW to the card's shape AS THEY SCROLL.
///
/// Unlike [AmoebaColumn] — a one-shot layout — this re-queries the shape on every scroll frame, so a
/// row narrows when it scrolls up into a notch and sweeps out to the full width where the card is
/// solid. Rows are a fixed [itemExtent]: a shape-dependent width would otherwise feed back into a
/// row's height (text re-wrapping), which can't be resolved in one layout pass.
///
/// Outside a fluid card (no [AmoebaCardScope]) it degrades to a plain fixed-extent scrolling list.
///
/// Placement matters: this widget must see the card's FULL shape to re-flow. Do not nest it inside
/// [AmoebaContentArea] — that crops the published geometry to the largest notch-free rectangle, so
/// every span reads full-width and rows stop tracking notches. Inset it with [AmoebaPadding]
/// (outline-aware, keeps geometry true) instead of a plain [Padding] (which silently misaligns the
/// span coordinates).
class AmoebaListView extends StatefulWidget {
  const AmoebaListView({
    super.key,
    required this.itemExtent,
    required this.itemCount,
    required this.itemBuilder,
    this.controller,
    this.rowPadding = EdgeInsets.zero,
    this.edgeClearance,
  });

  /// The fixed height of every row.
  final double itemExtent;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ScrollController? controller;

  /// Inset applied to each row inside its shape span (so text clears the outline).
  final EdgeInsets rowPadding;

  /// Vertical breathing room against horizontal shape edges: a row within
  /// this distance of a notch/step edge adopts the NARROWER neighboring
  /// span instead of rendering flush against (or under) the edge.
  ///
  /// Null (the default) derives it from the grid geometry: bands end at
  /// tile boundaries, but the visible outline pokes `gap / 2` past them
  /// and the notch's rounded shoulder eats `insideCornerRadius` more — a
  /// fixed few pixels of clearance gets swallowed before a row visually
  /// clears the edge at all.
  final double? edgeClearance;

  @override
  State<AmoebaListView> createState() => _AmoebaListViewState();
}

class _AmoebaListViewState extends State<AmoebaListView> {
  ScrollController? _own;
  ScrollController get _controller => widget.controller ?? (_own ??= ScrollController());

  @override
  void initState() {
    super.initState();
    _controller.addListener(_reflow);
  }

  // Every scroll tick: re-query each visible row's span at its NEW position.
  void _reflow() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(AmoebaListView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      (old.controller ?? _own)?.removeListener(_reflow);
      _controller.addListener(_reflow);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_reflow);
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final geometry = AmoebaCardScope.maybeOf(context);
    final offset = _controller.hasClients ? _controller.offset : 0.0;

    return LayoutBuilder(builder: (context, constraints) {
      final viewportWidth = constraints.maxWidth;
      final viewportHeight = constraints.maxHeight;
      final contentHeight = widget.itemCount * widget.itemExtent;

      final config = geometry?.metrics.config;
      final clearance = widget.edgeClearance ??
          (config == null
              ? 6.0
              : config.gap / 2 + config.insideCornerRadius);

      // The free horizontal run (left, width) at a viewport-local Y, from the shape's row bands.
      (double, double) spanAt(double y) {
        final bands = geometry?.rowBands;
        if (bands == null || bands.isEmpty) return (0, viewportWidth);
        var band = bands.last; // y at/after the last band
        for (final b in bands) {
          if (y < b.end) {
            band = b;
            break;
          }
        }
        var widest = band.spans.first;
        for (final s in band.spans) {
          if (s.width > widest.width) widest = s;
        }
        return (widest.left, widest.width);
      }

      // The run a row occupying [top, bottom] can use: the INTERSECTION of
      // the spans of every band the row (plus edge clearance) overlaps.
      // Sampling only the row's center let a row whose top or bottom few
      // pixels crossed a notch/step edge render full-width, flush against
      // the horizontal edge — no vertical breathing room. Intersecting
      // narrows exactly the rows that touch an edge; if the bands' spans
      // are horizontally disjoint (extreme shapes), fall back to the
      // center sample rather than collapsing to nothing.
      (double, double) spanForRange(double top, double bottom) {
        final bands = geometry?.rowBands;
        if (bands == null || bands.isEmpty) return (0, viewportWidth);
        double? lo, hi;
        for (final band in bands) {
          if (band.end <= top || band.start >= bottom) continue;
          // Within this band, prefer the span that best overlaps the
          // running window (widest when the window is still unbounded).
          Rect? best;
          var bestOverlap = double.negativeInfinity;
          for (final span in band.spans) {
            final overlap = lo == null
                ? span.width
                : (span.right < hi! ? span.right : hi) -
                    (span.left > lo ? span.left : lo);
            if (overlap > bestOverlap) {
              bestOverlap = overlap;
              best = span;
            }
          }
          if (best == null) continue;
          final newLo = lo == null || best.left > lo ? best.left : lo;
          final newHi = hi == null || best.right < hi ? best.right : hi;
          if (newHi - newLo <= 0) {
            return spanAt((top + bottom) / 2);
          }
          lo = newLo;
          hi = newHi;
        }
        // No band overlaps the row at all: it lies wholly outside the
        // shape (e.g. slots past the silhouette's bottom in a box taller
        // than the shape) — it must not render, not borrow a distant span.
        if (lo == null || hi == null) return (0, 0);
        return (lo, hi - lo);
      }

      // Bands are straight-edged, but the outline's corner ARCS cut deeper
      // than any edge inset — a row whose slot lands beside a rounded
      // corner would poke into the curve. Probe the row's corners against
      // the outline path and walk each end inward until it clears.
      final path = geometry?.path;
      final maxArc = config == null
          ? 0.0
          : (config.insideCornerRadius > config.outsideCornerRadius
                  ? config.insideCornerRadius
                  : config.outsideCornerRadius) +
              4;
      (double, double) clearArcs(
          double left, double width, double top, double bottom) {
        if (path == null || width <= 0) return (left, width);
        var lo = left;
        var hi = left + width;
        const step = 4.0;
        var budget = maxArc;
        while (budget > 0 &&
            hi - lo > 0 &&
            (!path.contains(Offset(lo, top)) ||
                !path.contains(Offset(lo, bottom)))) {
          lo += step;
          budget -= step;
        }
        budget = maxArc;
        while (budget > 0 &&
            hi - lo > 0 &&
            (!path.contains(Offset(hi, top)) ||
                !path.contains(Offset(hi, bottom)))) {
          hi -= step;
          budget -= step;
        }
        return (lo, (hi - lo).clamp(0.0, double.infinity));
      }

      final rows = <Widget>[];
      for (var i = 0; i < widget.itemCount; i++) {
        final top = i * widget.itemExtent;
        final screenTop = top - offset;
        if (screenTop > viewportHeight || screenTop + widget.itemExtent < 0) continue; // cull
        final (rawLeft, rawWidth) = spanForRange(
            screenTop - clearance, screenTop + widget.itemExtent + clearance);
        final (spanLeft, spanWidth) = clearArcs(rawLeft, rawWidth,
            screenTop.clamp(0.0, viewportHeight),
            (screenTop + widget.itemExtent).clamp(0.0, viewportHeight));
        final left = spanLeft + widget.rowPadding.left;
        final width = (spanWidth - widget.rowPadding.horizontal).clamp(0.0, double.infinity);
        rows.add(Positioned(
          top: top + widget.rowPadding.top,
          left: left,
          width: width,
          height: (widget.itemExtent - widget.rowPadding.vertical).clamp(0.0, double.infinity),
          child: widget.itemBuilder(context, i),
        ));
      }

      return SingleChildScrollView(
        controller: _controller,
        child: SizedBox(
          height: contentHeight < viewportHeight ? viewportHeight : contentHeight,
          child: Stack(clipBehavior: Clip.none, children: rows),
        ),
      );
    });
  }
}
