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
  });

  /// The fixed height of every row.
  final double itemExtent;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ScrollController? controller;

  /// Inset applied to each row inside its shape span (so text clears the outline).
  final EdgeInsets rowPadding;

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

      final rows = <Widget>[];
      for (var i = 0; i < widget.itemCount; i++) {
        final top = i * widget.itemExtent;
        final screenTop = top - offset;
        if (screenTop > viewportHeight || screenTop + widget.itemExtent < 0) continue; // cull
        // Query at the row's centre so it transitions smoothly across a band edge as it scrolls.
        final (spanLeft, spanWidth) = spanAt(screenTop + widget.itemExtent / 2);
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
