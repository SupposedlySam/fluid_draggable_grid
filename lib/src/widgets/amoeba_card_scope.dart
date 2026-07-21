import 'package:flutter/widgets.dart';

import '../engine/content_geometry.dart';
import 'outline_clip.dart';

/// Publishes a card's shape-aware [AmoebaCardGeometry] to its content.
///
/// `AmoebaGridView` injects one around every card's child automatically, so
/// any descendant — at any depth — can adapt to the polyomino via
/// [AmoebaCardScope.maybeOf]. The Amoeba* content widgets (AmoebaContentArea,
/// AmoebaRegions, AmoebaColumn/AmoebaRow, AmoebaText) all read it; outside a
/// fluid card they degrade gracefully to plain rectangular behavior.
class AmoebaCardScope extends InheritedWidget {
  const AmoebaCardScope({
    super.key,
    required this.geometry,
    required super.child,
  });

  final AmoebaCardGeometry geometry;

  static AmoebaCardGeometry? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AmoebaCardScope>()
      ?.geometry;

  static AmoebaCardGeometry of(BuildContext context) {
    final geometry = maybeOf(context);
    assert(geometry != null,
        'AmoebaCardScope.of called outside a fluid card subtree');
    return geometry!;
  }

  @override
  bool updateShouldNotify(AmoebaCardScope oldWidget) =>
      oldWidget.geometry != geometry;
}

/// Shape-aware [Padding]: pads the child AND republishes the geometry with
/// the padding carved off, so fluid widgets below it keep seeing spans and
/// regions in their own coordinates. Use this instead of a plain Padding
/// between the card and any Amoeba* layout widget.
///
/// The child is also CLIPPED to the silhouette eroded by the smallest
/// padding side — padding that follows the shape the way rectangle padding
/// follows a rectangle, enforced no matter what the child paints. Debug
/// builds can tint that band red via
/// [AmoebaGridDiagnostics.showPaddingOverlay].
class AmoebaPadding extends StatelessWidget {
  const AmoebaPadding({
    super.key,
    required this.padding,
    required this.child,
    this.clipToShape = true,
  });

  final EdgeInsets padding;
  final Widget child;

  /// Opt out of the eroded-outline clip (rarely wanted).
  final bool clipToShape;

  @override
  Widget build(BuildContext context) {
    final geometry = AmoebaCardScope.maybeOf(context);
    final padded = Padding(padding: padding, child: child);
    if (geometry == null) return padded;
    var deflated = geometry.deflate(padding);
    Widget content = child;
    if (clipToShape) {
      final sides = [
        padding.left, padding.top, padding.right, padding.bottom,
      ]..sort();
      final eroded = deflated.erodedPath(sides.first);
      content = ClipPath(clipper: OutlineClipper(eroded), child: content);
      // Publish the clip surface so flow widgets probe the SAME boundary
      // this enforces — probing the raw outline lets a row believe it is
      // clear while the stricter eroded clip shears its glyphs.
      deflated = deflated.withContentClip(eroded, sides.first);
    }
    return Padding(
      padding: padding,
      child: AmoebaCardScope(geometry: deflated, child: content),
    );
  }
}

/// Lays its child in the **largest rectangle fully inside the card shape**
/// — a SafeArea for notches. The child stays rectangular but is never bitten
/// by a concave cutout, no matter how the user reshapes the card.
class AmoebaContentArea extends StatelessWidget {
  const AmoebaContentArea({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.alignment,
  });

  final Widget child;

  /// Extra padding inside the safe rectangle.
  final EdgeInsets padding;

  /// When non-null, the child is aligned loosely inside the safe rect
  /// instead of filling it.
  final AlignmentGeometry? alignment;

  @override
  Widget build(BuildContext context) {
    final geometry = AmoebaCardScope.maybeOf(context);
    if (geometry == null) {
      return Padding(padding: padding, child: child);
    }
    final rect = padding.deflateRect(geometry.largestRect);
    if (rect.isEmpty) return const SizedBox.shrink();
    Widget content = AmoebaCardScope(
      geometry: geometry.cropTo(rect).markWindowed(),
      child: child,
    );
    if (alignment != null) {
      content = Align(alignment: alignment!, child: content);
    }
    return SizedBox.expand(
      child: Stack(
        clipBehavior: Clip.none,
        children: [Positioned.fromRect(rect: rect, child: content)],
      ),
    );
  }
}

/// Explicit placement into the card's maximal-rectangle decomposition:
/// [builder] is invoked once per rectangular sub-region (area-descending —
/// region 0 is the biggest) and may return null to leave a region empty.
/// Reshaping the card changes the region set live.
class AmoebaRegions extends StatelessWidget {
  const AmoebaRegions({super.key, required this.builder});

  final Widget? Function(BuildContext context, AmoebaRegion region) builder;

  @override
  Widget build(BuildContext context) {
    final geometry = AmoebaCardScope.maybeOf(context);
    if (geometry == null) {
      // Outside a fluid card the whole box is one region.
      return LayoutBuilder(builder: (context, constraints) {
        final region = AmoebaRegion(
          index: 0,
          rect: Offset.zero & constraints.biggest,
          cellWidth: 1,
          cellHeight: 1,
        );
        return builder(context, region) ?? const SizedBox.shrink();
      });
    }
    return SizedBox.expand(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final region in geometry.regions)
            if (builder(context, region) case final child?)
              Positioned.fromRect(
                rect: region.rect,
                child: AmoebaCardScope(
                  geometry: geometry.cropTo(region.rect),
                  child: child,
                ),
              ),
        ],
      ),
    );
  }
}
