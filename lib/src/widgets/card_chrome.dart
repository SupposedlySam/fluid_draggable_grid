import 'package:flutter/material.dart';

import '../engine/grid_metrics.dart';
import '../engine/handles.dart';
import '../foundation/cell.dart';
import '../engine/outline.dart';
import '../engine/outline_cache.dart';

/// Visual styling for the grid chrome. Card *content* styles itself; this
/// covers the painted card surfaces, handles, previews, and backdrop.
@immutable
class FluidGridStyle {
  const FluidGridStyle({
    required this.cardColor,
    required this.cardBorderColor,
    required this.accentColor,
    required this.handleColor,
    required this.handleIconColor,
    required this.backdropDotColor,
    this.cardElevation = 6,
    this.handleIcon = Icons.back_hand,
  });

  /// Dark-first defaults tuned for a bento-style dashboard.
  factory FluidGridStyle.fromTheme(ThemeData theme) {
    final scheme = theme.colorScheme;
    return FluidGridStyle(
      cardColor: scheme.surfaceContainerHigh,
      cardBorderColor: scheme.outlineVariant.withValues(alpha: 0.35),
      accentColor: scheme.primary,
      handleColor: scheme.primary,
      handleIconColor: scheme.onPrimary,
      backdropDotColor: scheme.onSurface.withValues(alpha: 0.10),
    );
  }

  final Color cardColor;
  final Color cardBorderColor;
  final Color accentColor;
  final Color handleColor;
  final Color handleIconColor;
  final Color backdropDotColor;
  final double cardElevation;
  final IconData handleIcon;
}

/// Faint dots at tile intersections so the field reads as a grid without
/// competing with content.
class GridBackdropPainter extends CustomPainter {
  GridBackdropPainter(this.metrics, this.style);

  final GridMetrics metrics;
  final FluidGridStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = style.backdropDotColor;
    final config = metrics.config;
    for (var c = 0; c <= config.columns; c++) {
      for (var r = 0; r <= config.rows; r++) {
        canvas.drawCircle(metrics.tileOrigin(c, r), 1.4, paint);
      }
    }
  }

  @override
  bool shouldRepaint(GridBackdropPainter oldDelegate) =>
      oldDelegate.metrics != metrics || oldDelegate.style != style;
}

/// Paints one card's surface: soft shadow, fill, hairline border, and an
/// optional lift emphasis while the card is the drag aggressor.
class CardChromePainter extends CustomPainter {
  CardChromePainter({
    required this.path,
    required this.style,
    required this.color,
    required this.lift,
  });

  final Path path;
  final FluidGridStyle style;
  final Color color;

  /// 0..1: how "picked up" the card is.
  final double lift;

  @override
  void paint(Canvas canvas, Size size) {
    final elevation = style.cardElevation + lift * 14;
    canvas.drawShadow(
        path, Colors.black.withValues(alpha: 0.6 + lift * 0.2),
        elevation, true);
    canvas.drawPath(path, Paint()..color = color);
    if (lift > 0) {
      canvas.drawPath(
          path,
          Paint()
            ..color = style.accentColor.withValues(alpha: 0.06 * lift));
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Color.lerp(
            style.cardBorderColor, style.accentColor, lift * 0.6)!,
    );
  }

  @override
  bool shouldRepaint(CardChromePainter oldDelegate) =>
      oldDelegate.path != path ||
      oldDelegate.color != color ||
      oldDelegate.lift != lift ||
      oldDelegate.style != style;
}

/// Paints the snapped drop preview while a drag session is live.
class PreviewPainter extends CustomPainter {
  PreviewPainter({required this.path, required this.style});

  final Path path;
  final FluidGridStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
        path, Paint()..color = style.accentColor.withValues(alpha: 0.10));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = style.accentColor.withValues(alpha: 0.75),
    );
  }

  @override
  bool shouldRepaint(PreviewPainter oldDelegate) =>
      oldDelegate.path != path || oldDelegate.style != style;
}

/// Paints the resize affordances of the hovered card: faint hint dots on
/// every handle, and a progressively exposed semicircular grab tab (with a
/// hand icon) on the handle under the pointer. Corners get quarter-circle
/// tabs oriented along the diagonal, sitting inside the outside corner
/// radius.
class HandlesPainter extends CustomPainter {
  HandlesPainter({
    required this.handles,
    required this.hovered,
    required this.reveal,
    required this.style,
    required this.metrics,
  });

  final List<GridHandle> handles;
  final GridHandle? hovered;
  final double reveal;
  final FluidGridStyle style;
  final GridMetrics metrics;

  @override
  void paint(Canvas canvas, Size size) {
    final hintPaint = Paint()
      ..color = style.handleColor.withValues(alpha: 0.28);
    for (final handle in handles) {
      if (identical(handle, hovered)) continue;
      canvas.drawCircle(handle.center, 2.2, hintPaint);
    }
    final active = hovered;
    if (active == null || reveal <= 0) return;

    final radius = (metrics.cellExtent * 0.30).clamp(11.0, 20.0) * reveal;
    final tabPaint = Paint()
      ..color = style.handleColor.withValues(alpha: 0.92 * reveal);

    final (startAngle, sweep) = _arcFor(active);
    canvas.drawArc(Rect.fromCircle(center: active.center, radius: radius),
        startAngle, sweep, true, tabPaint);

    if (reveal > 0.4) {
      final iconSize = radius * 0.9;
      final textPainter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(style.handleIcon.codePoint),
          style: TextStyle(
            fontSize: iconSize,
            fontFamily: style.handleIcon.fontFamily,
            package: style.handleIcon.fontPackage,
            color: style.handleIconColor
                .withValues(alpha: ((reveal - 0.4) / 0.6).clamp(0, 1)),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
          canvas,
          active.center -
              Offset(textPainter.width / 2, textPainter.height / 2));
    }
  }

  /// Semicircles face outward from the card edge; quarter circles bisect
  /// the corner diagonal. Angles are in radians, screen coordinates.
  (double, double) _arcFor(GridHandle handle) {
    const pi = 3.1415926535897932;
    if (!handle.isCorner) {
      return switch (handle.edge!) {
        CardinalEdge.north => (pi, pi),
        CardinalEdge.south => (0, pi),
        CardinalEdge.east => (-pi / 2, pi),
        CardinalEdge.west => (pi / 2, pi),
      };
    }
    return switch (handle.corner!) {
      CornerKind.northWest => (pi, pi / 2),
      CornerKind.northEast => (-pi / 2, pi / 2),
      CornerKind.southEast => (0, pi / 2),
      CornerKind.southWest => (pi / 2, pi / 2),
    };
  }

  @override
  bool shouldRepaint(HandlesPainter oldDelegate) =>
      !identical(oldDelegate.handles, handles) ||
      oldDelegate.hovered != hovered ||
      oldDelegate.reveal != reveal ||
      oldDelegate.style != style;
}

/// One card: morphs organically between cell-quantized shapes and hosts the
/// developer-provided content, clipped to the live outline.
class FluidCardSurface extends StatefulWidget {
  const FluidCardSurface({
    super.key,
    required this.shape,
    required this.metrics,
    required this.style,
    required this.color,
    required this.visualOffset,
    required this.lift,
    required this.child,
    this.morphDuration = const Duration(milliseconds: 220),
  });

  final CardShape shape;
  final GridMetrics metrics;
  final FluidGridStyle style;
  final Color color;

  /// Free-floating pixel offset while this card is being moved.
  final Offset visualOffset;

  /// 0..1 pick-up emphasis.
  final double lift;

  final Widget child;
  final Duration morphDuration;

  @override
  State<FluidCardSurface> createState() => _FluidCardSurfaceState();
}

class _FluidCardSurfaceState extends State<FluidCardSurface>
    with SingleTickerProviderStateMixin {
  late final AnimationController _morph = AnimationController(
    vsync: this,
    duration: widget.morphDuration,
    value: 1,
  );

  late CardShape _target = widget.shape;
  late Path _toPath = _outline(_target);
  Path? _fromPath;
  late Rect _fromBounds = _bounds(_target);
  late Rect _toBounds = _fromBounds;

  Path _outline(CardShape shape) =>
      OutlineCache.instance.outlineFor(shape, widget.metrics).paths;

  Rect _bounds(CardShape shape) => widget.metrics.shapeBounds(shape);

  double get _easedT => Curves.easeOutCubic.transform(_morph.value);

  Path get _currentPath {
    final from = _fromPath;
    final base = (from == null || _morph.isCompleted)
        ? _toPath
        : lerpOutline(from, _toPath, _easedT);
    return widget.visualOffset == Offset.zero
        ? base
        : base.shift(widget.visualOffset);
  }

  Rect get _currentBounds =>
      (Rect.lerp(_fromBounds, _toBounds, _easedT) ?? _toBounds)
          .shift(widget.visualOffset);

  @override
  void didUpdateWidget(FluidCardSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    final metricsChanged = oldWidget.metrics != widget.metrics;
    if (widget.shape != _target || metricsChanged) {
      // Capture the currently rendered geometry (including any pixel offset
      // that is being dropped) so the morph continues from what the user
      // sees, then retarget.
      _fromPath = _currentPath.shift(-widget.visualOffset);
      _fromBounds = _currentBounds.shift(-widget.visualOffset);
      _target = widget.shape;
      _toPath = _outline(_target);
      _toBounds = _bounds(_target);
      if (metricsChanged && oldWidget.metrics.viewportSize !=
          widget.metrics.viewportSize) {
        // Resizes retarget instantly; morphing across metric spaces looks
        // like lag rather than intent.
        _morph.value = 1;
      } else {
        _morph.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _morph.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _morph,
      builder: (context, _) {
        final path = _currentPath;
        final bounds = _currentBounds;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: CardChromePainter(
                    path: path,
                    style: widget.style,
                    color: widget.color,
                    lift: widget.lift,
                  ),
                ),
              ),
            ),
            Positioned.fromRect(
              rect: bounds,
              child: ClipPath(
                clipper: _ShiftedPathClipper(path, bounds.topLeft),
                child: widget.child,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ShiftedPathClipper extends CustomClipper<Path> {
  _ShiftedPathClipper(this.path, this.origin);

  final Path path;
  final Offset origin;

  @override
  Path getClip(Size size) => path.shift(-origin);

  @override
  bool shouldReclip(_ShiftedPathClipper oldClipper) =>
      oldClipper.path != path || oldClipper.origin != origin;
}
