import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../controller.dart';
import '../engine/grid_metrics.dart';
import '../engine/handles.dart';
import '../engine/outline_cache.dart';
import '../foundation/cell.dart';
import '../foundation/diagnostics.dart';
import 'card_chrome.dart';

/// One dashboard card: programmatic identity, initial footprint, content.
/// User shaping (persisted per width bucket) overrides [initialShape].
@immutable
class FluidGridCard {
  const FluidGridCard({
    required this.id,
    required this.initialShape,
    required this.child,
    this.color,
  });

  final String id;
  final CardShape initialShape;
  final Widget child;

  /// Optional surface tint; defaults to the style's card color.
  final Color? color;
}

/// A pannable field of fixed columns x rows where cards can be moved,
/// resized strip-by-strip into polyomino silhouettes, and pushed through
/// each other amoeba-style. See the package README for the interaction
/// model.
class FluidGridView extends StatefulWidget {
  const FluidGridView({
    super.key,
    required this.controller,
    required this.cards,
    this.style,
  });

  final FluidGridController controller;
  final List<FluidGridCard> cards;
  final FluidGridStyle? style;

  @override
  State<FluidGridView> createState() => _FluidGridViewState();
}

class _FluidGridViewState extends State<FluidGridView>
    with TickerProviderStateMixin {
  final ScrollController _horizontal = ScrollController();
  final ScrollController _vertical = ScrollController();

  late final AnimationController _handleReveal = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 160));

  GridHandle? _hoveredHandle;
  String? _hoveredCardId;
  List<GridHandle> _hoverHandles = const [];

  Ticker? _autoScroller;
  Offset? _dragViewportPoint;

  static const double _autoScrollMargin = 56;
  static const double _autoScrollMaxSpeed = 14;

  @override
  void initState() {
    super.initState();
    widget.controller.registerCards(_initialShapes());
    widget.controller.load();
    widget.controller.addListener(_onControllerChanged);
  }

  Map<String, CardShape> _initialShapes() =>
      {for (final card in widget.cards) card.id: card.initialShape};

  @override
  void didUpdateWidget(FluidGridView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
    widget.controller.registerCards(_initialShapes());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _autoScroller?.dispose();
    _handleReveal.dispose();
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  void _onControllerChanged() => setState(() {});

  // --- Hover ---------------------------------------------------------------

  void _onHover(PointerHoverEvent event, GridMetrics metrics) {
    if (widget.controller.isDragging) return;
    final point = event.localPosition;

    final interaction = _interactionAt(point, metrics);
    final cardId = interaction?.$1;
    final hit = interaction?.$2;
    final List<GridHandle> handles;
    if (cardId == null) {
      handles = const [];
    } else {
      final shape = widget.controller.effectiveShape(cardId);
      handles =
          shape == null ? const [] : handlesFor(cardId, shape, metrics);
    }

    if (cardId != _hoveredCardId || hit != _hoveredHandle) {
      if (hit != null && hit != _hoveredHandle) {
        FluidGridDiagnostics.emit(FluidGridEventKind.handleHoverEnter,
            'handle hover', {'handle': hit.debugLabel});
        _handleReveal.forward(from: _hoveredHandle == null ? 0 : 0.4);
      } else if (hit == null && _hoveredHandle != null) {
        FluidGridDiagnostics.emit(FluidGridEventKind.handleHoverExit,
            'handle hover exit', {'handle': _hoveredHandle!.debugLabel});
        _handleReveal.reverse();
      }
      setState(() {
        _hoveredCardId = cardId;
        _hoverHandles = handles;
        _hoveredHandle = hit;
      });
    }
  }

  void _clearHover() {
    if (_hoveredCardId == null && _hoveredHandle == null) return;
    _handleReveal.reverse();
    setState(() {
      _hoveredCardId = null;
      _hoveredHandle = null;
      _hoverHandles = const [];
    });
  }

  /// Cards for hit testing, topmost first.
  Iterable<FluidGridCard> _orderedCards() => widget.cards.reversed;

  // --- Drag ----------------------------------------------------------------

  /// The card/handle grabbed at pointer-down, captured when the recognizer
  /// joins the arena. The gesture may only be *accepted* after the pointer
  /// has already traveled (past slop — or much farther on a fast flick), so
  /// hit-testing again at onStart would miss the card the user grabbed.
  (Offset downPosition, String cardId, GridHandle? handle)? _pendingGrab;

  bool _capturePanDown(Offset point, GridMetrics metrics) {
    final interaction = _interactionAt(point, metrics);
    FluidGridDiagnostics.emit(FluidGridEventKind.pointerDown, 'pointer down', {
      'at': '(${point.dx.toStringAsFixed(0)},${point.dy.toStringAsFixed(0)})',
      'hit': interaction == null
          ? 'none'
          : interaction.$2 == null
              ? 'body:${interaction.$1}'
              : 'handle:${interaction.$2!.debugLabel}',
    });
    if (interaction == null) {
      _pendingGrab = null;
      return false;
    }
    _pendingGrab = (point, interaction.$1, interaction.$2);
    return true;
  }

  (String cardId, GridHandle? handle)? _interactionAt(
      Offset point, GridMetrics metrics) {
    return interactionAt(
      point,
      [
        for (final card in _orderedCards())
          if (widget.controller.effectiveShape(card.id) case final shape?)
            (card.id, shape),
      ],
      metrics,
    );
  }

  void _onPanStart(DragStartDetails details, GridMetrics metrics) {
    final grab = _pendingGrab;
    _pendingGrab = null;
    if (grab == null) {
      FluidGridDiagnostics.emit(FluidGridEventKind.gestureRejected,
          'pan accepted but no pending grab');
      return;
    }
    final (downPosition, cardId, handle) = grab;
    if (handle != null) {
      widget.controller.startResize(handle, downPosition);
    } else {
      widget.controller.startMove(cardId, downPosition);
    }
    // Catch up with whatever distance was covered before acceptance.
    if (details.localPosition != downPosition) {
      widget.controller.updateDrag(details.localPosition);
    }
    _dragViewportPoint = _toViewportSpace(details.localPosition);
    _startAutoScroller();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!widget.controller.isDragging) return;
    widget.controller.updateDrag(details.localPosition);
    _dragViewportPoint = _toViewportSpace(details.localPosition);
  }

  void _onPanEnd() {
    _stopAutoScroller();
    widget.controller.endDrag();
  }

  void _onPanCancel() {
    _stopAutoScroller();
    widget.controller.cancelDrag();
  }

  Offset _scrollOffset() => Offset(
        _horizontal.hasClients ? _horizontal.offset : 0,
        _vertical.hasClients ? _vertical.offset : 0,
      );

  Offset _toViewportSpace(Offset contentPoint) =>
      contentPoint - _scrollOffset();

  void _startAutoScroller() {
    _autoScroller?.dispose();
    _autoScroller = createTicker(_autoScrollTick)..start();
  }

  void _stopAutoScroller() {
    _autoScroller?.dispose();
    _autoScroller = null;
    _dragViewportPoint = null;
  }

  /// Dragging against a viewport edge pans the grid underneath the pointer
  /// and re-feeds the drag with the shifted content-space point.
  void _autoScrollTick(Duration elapsed) {
    final viewportPoint = _dragViewportPoint;
    final metrics = widget.controller.metrics;
    if (viewportPoint == null || metrics == null) return;

    double speedFor(double distanceIntoMargin) =>
        distanceIntoMargin <= 0
            ? 0
            : _autoScrollMaxSpeed *
                (distanceIntoMargin / _autoScrollMargin).clamp(0, 1);

    final viewport = metrics.viewportSize;
    var dx = 0.0;
    var dy = 0.0;
    dx -= speedFor(_autoScrollMargin - viewportPoint.dx);
    dx += speedFor(viewportPoint.dx - (viewport.width - _autoScrollMargin));
    dy -= speedFor(_autoScrollMargin - viewportPoint.dy);
    dy += speedFor(viewportPoint.dy - (viewport.height - _autoScrollMargin));
    if (dx == 0 && dy == 0) return;

    if (_horizontal.hasClients && dx != 0) {
      final position = _horizontal.position;
      position.jumpTo((position.pixels + dx)
          .clamp(position.minScrollExtent, position.maxScrollExtent));
    }
    if (_vertical.hasClients && dy != 0) {
      final position = _vertical.position;
      position.jumpTo((position.pixels + dy)
          .clamp(position.minScrollExtent, position.maxScrollExtent));
    }
    FluidGridDiagnostics.emit(FluidGridEventKind.edgeAutoScroll,
        'edge auto-scroll', {'dx': dx, 'dy': dy});
    widget.controller.updateDrag(viewportPoint + _scrollOffset());
  }

  // --- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final style =
        widget.style ?? FluidGridStyle.fromTheme(Theme.of(context));
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = GridMetrics.resolve(
          widget.controller.config,
          constraints.biggest,
          minColumns: widget.controller.occupiedColumns,
          minRows: widget.controller.occupiedRows,
        );
        // Defer: updateMetrics notifies listeners and we are mid-build.
        if (widget.controller.metrics != metrics) {
          WidgetsBinding.instance.addPostFrameCallback(
              (_) => widget.controller.updateMetrics(metrics));
        }
        return Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event.logicalKey == LogicalKeyboardKey.escape &&
                widget.controller.isDragging) {
              _stopAutoScroller();
              widget.controller.cancelDrag();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: TwoDimensionalScrollable(
            horizontalDetails: ScrollableDetails.horizontal(
                controller: _horizontal),
            verticalDetails:
                ScrollableDetails.vertical(controller: _vertical),
            diagonalDragBehavior: DiagonalDragBehavior.free,
            viewportBuilder: (context, verticalOffset, horizontalOffset) {
              return _PannedCanvas(
                horizontalOffset: horizontalOffset,
                verticalOffset: verticalOffset,
                contentSize: metrics.contentSize,
                child: _buildCanvas(metrics, style),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildCanvas(GridMetrics metrics, FluidGridStyle style) {
    final controller = widget.controller;
    final session = controller.session;

    final cards = <Widget>[];
    FluidGridCard? aggressorCard;
    for (final card in widget.cards) {
      if (session?.cardId == card.id) {
        aggressorCard = card;
        continue;
      }
      cards.add(_buildCard(card, metrics, style, session));
    }
    // Aggressor renders topmost.
    if (aggressorCard != null) {
      cards.add(_buildCard(aggressorCard, metrics, style, session));
    }

    final previewPath = session == null
        ? null
        : OutlineCache.instance
            .outlineFor(session.preview, metrics)
            .paths;

    return MouseRegion(
      cursor: controller.isDragging || _hoveredHandle != null
          ? SystemMouseCursors.grabbing
          : _hoveredCardId != null
              ? SystemMouseCursors.move
              : MouseCursor.defer,
      onHover: (event) => _onHover(event, metrics),
      onExit: (_) => _clearHover(),
      child: RawGestureDetector(
        behavior: HitTestBehavior.translucent,
        gestures: {
          _CardPanRecognizer:
              GestureRecognizerFactoryWithHandlers<_CardPanRecognizer>(
            () => _CardPanRecognizer(
                shouldAccept: (point) => _capturePanDown(point, metrics)),
            (recognizer) {
              recognizer.onStart = (details) => _onPanStart(details, metrics);
              recognizer.onUpdate = _onPanUpdate;
              recognizer.onEnd = (_) => _onPanEnd();
              recognizer.onCancel = _onPanCancel;
            },
          ),
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: GridBackdropPainter(metrics, style),
              ),
            ),
            ...cards,
            // Above the cards: a shrink preview lies entirely within the
            // aggressor's current footprint and would be invisible below.
            if (previewPath != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter:
                        PreviewPainter(path: previewPath, style: style),
                  ),
                ),
              ),
            if (_hoverHandles.isNotEmpty && !controller.isDragging)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _handleReveal,
                    builder: (context, _) => CustomPaint(
                      painter: HandlesPainter(
                        handles: _hoverHandles,
                        hovered: _hoveredHandle,
                        reveal: Curves.easeOutBack
                            .transform(_handleReveal.value),
                        style: style,
                        metrics: metrics,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(FluidGridCard card, GridMetrics metrics,
      FluidGridStyle style, DragSession? session) {
    final isAggressor = session != null && session.cardId == card.id;
    final isMoving = isAggressor && session.kind == DragKind.move;

    // While moving, the card free-floats at its origin shape + pixel offset
    // and the snapped preview is painted separately. While resizing, the
    // card holds its origin shape until release. Submissives show their
    // transient (deferred) shapes.
    final shape = isAggressor
        ? session.originShape
        : widget.controller.effectiveShape(card.id);
    if (shape == null) return const SizedBox.shrink();

    return Positioned.fill(
      key: ValueKey(card.id),
      child: FluidCardSurface(
        shape: shape,
        metrics: metrics,
        style: style,
        color: card.color ?? style.cardColor,
        visualOffset: isMoving ? session.pixelDelta : Offset.zero,
        lift: isAggressor ? 1 : 0,
        child: card.child,
      ),
    );
  }
}

/// Accepts the gesture only when the pointer goes down on a card or handle,
/// so background drags fall through to the scrollable for panning.
class _CardPanRecognizer extends PanGestureRecognizer {
  _CardPanRecognizer({required this.shouldAccept});

  final bool Function(Offset localPosition) shouldAccept;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (!shouldAccept(event.localPosition)) return;
    super.addAllowedPointer(event);
  }

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {
    // Trackpad two-finger pans always belong to the scrollable. Without
    // this, PanGestureRecognizer claims them through a path that bypasses
    // the pointer-down filter and the gesture dies over cards.
  }

  @override
  void acceptGesture(int pointer) {
    FluidGridDiagnostics.emit(
        FluidGridEventKind.gestureAccepted, 'card pan won the arena');
    super.acceptGesture(pointer);
  }

  @override
  void rejectGesture(int pointer) {
    FluidGridDiagnostics.emit(FluidGridEventKind.gestureRejected,
        'card pan lost the arena (another recognizer took the drag)');
    super.rejectGesture(pointer);
  }
}

/// A minimal two-axis viewport: lays out one child at the full content size
/// and paints it shifted by the scroll offsets.
class _PannedCanvas extends SingleChildRenderObjectWidget {
  const _PannedCanvas({
    required this.horizontalOffset,
    required this.verticalOffset,
    required this.contentSize,
    required super.child,
  });

  final ViewportOffset horizontalOffset;
  final ViewportOffset verticalOffset;
  final Size contentSize;

  @override
  _RenderPannedCanvas createRenderObject(BuildContext context) =>
      _RenderPannedCanvas(horizontalOffset, verticalOffset, contentSize);

  @override
  void updateRenderObject(
      BuildContext context, _RenderPannedCanvas renderObject) {
    renderObject
      ..horizontalOffset = horizontalOffset
      ..verticalOffset = verticalOffset
      ..contentSize = contentSize;
  }
}

class _RenderPannedCanvas extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  _RenderPannedCanvas(
      this._horizontalOffset, this._verticalOffset, this._contentSize);

  ViewportOffset _horizontalOffset;
  ViewportOffset get horizontalOffset => _horizontalOffset;
  set horizontalOffset(ViewportOffset value) {
    if (identical(value, _horizontalOffset)) return;
    if (attached) _horizontalOffset.removeListener(markNeedsPaint);
    _horizontalOffset = value;
    if (attached) _horizontalOffset.addListener(markNeedsPaint);
    markNeedsLayout();
  }

  ViewportOffset _verticalOffset;
  ViewportOffset get verticalOffset => _verticalOffset;
  set verticalOffset(ViewportOffset value) {
    if (identical(value, _verticalOffset)) return;
    if (attached) _verticalOffset.removeListener(markNeedsPaint);
    _verticalOffset = value;
    if (attached) _verticalOffset.addListener(markNeedsPaint);
    markNeedsLayout();
  }

  Size _contentSize;
  Size get contentSize => _contentSize;
  set contentSize(Size value) {
    if (value == _contentSize) return;
    _contentSize = value;
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _horizontalOffset.addListener(markNeedsPaint);
    _verticalOffset.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _horizontalOffset.removeListener(markNeedsPaint);
    _verticalOffset.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void performLayout() {
    size = constraints.biggest;
    child?.layout(BoxConstraints.tight(_contentSize));
    _horizontalOffset
      ..applyViewportDimension(size.width)
      ..applyContentDimensions(
          0, (contentSize.width - size.width).clamp(0, double.infinity));
    _verticalOffset
      ..applyViewportDimension(size.height)
      ..applyContentDimensions(
          0, (contentSize.height - size.height).clamp(0, double.infinity));
  }

  Offset get _paintShift =>
      Offset(-_horizontalOffset.pixels, -_verticalOffset.pixels);

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    context.pushClipRect(needsCompositing, offset, Offset.zero & size,
        (context, offset) {
      context.paintChild(child, offset + _paintShift);
    });
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    return result.addWithPaintOffset(
      offset: _paintShift,
      position: position,
      hitTest: (result, transformed) =>
          child.hitTest(result, position: transformed),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(_paintShift.dx, _paintShift.dy, 0, 1);
  }
}
