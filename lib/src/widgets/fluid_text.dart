import 'package:flutter/widgets.dart';

import '../engine/content_geometry.dart';
import 'fluid_card_scope.dart';

/// Text that wraps around the card's notches — Flutter has no CSS
/// `shape-outside`, but fluid shapes are cell-quantized, so lines are laid
/// out band by band: each line gets the free horizontal span at its own
/// height, including split spans on either side of an interior notch.
///
/// Trade-offs versus [Text]: no selection, greedy word wrapping, single
/// style. Outside a fluid card it behaves like ordinary wrapped text.
class FluidText extends LeafRenderObjectWidget {
  const FluidText(this.text, {super.key, this.style, this.lineSpacing = 0});

  final String text;
  final TextStyle? style;

  /// Extra pixels between lines on top of the font's line height.
  final double lineSpacing;

  TextStyle _effectiveStyle(BuildContext context) {
    final base = DefaultTextStyle.of(context).style;
    return style == null ? base : base.merge(style);
  }

  @override
  RenderFluidText createRenderObject(BuildContext context) => RenderFluidText(
        text: text,
        style: _effectiveStyle(context),
        lineSpacing: lineSpacing,
        geometry: FluidCardScope.maybeOf(context),
        textDirection: Directionality.of(context),
      );

  @override
  void updateRenderObject(BuildContext context, RenderFluidText renderObject) {
    renderObject
      ..text = text
      ..style = _effectiveStyle(context)
      ..lineSpacing = lineSpacing
      ..geometry = FluidCardScope.maybeOf(context)
      ..textDirection = Directionality.of(context);
  }
}

class _Line {
  _Line(this.painter, this.offset);

  final TextPainter painter;
  final Offset offset;
}

class RenderFluidText extends RenderBox {
  RenderFluidText({
    required this._text,
    required this._style,
    required this._lineSpacing,
    required this._geometry,
    required this._textDirection,
  });

  String _text;
  set text(String value) {
    if (value == _text) return;
    _text = value;
    markNeedsLayout();
  }

  TextStyle _style;
  set style(TextStyle value) {
    if (value == _style) return;
    _style = value;
    markNeedsLayout();
  }

  double _lineSpacing;
  set lineSpacing(double value) {
    if (value == _lineSpacing) return;
    _lineSpacing = value;
    markNeedsLayout();
  }

  FluidCardGeometry? _geometry;
  set geometry(FluidCardGeometry? value) {
    if (value == _geometry) return;
    _geometry = value;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  final List<_Line> _lines = [];

  void _clearLines() {
    for (final line in _lines) {
      line.painter.dispose();
    }
    _lines.clear();
  }

  TextPainter _painterFor(String content) => TextPainter(
        text: TextSpan(text: content, style: _style),
        textDirection: _textDirection,
        maxLines: 1,
        ellipsis: '…',
      );

  @override
  void performLayout() {
    size = constraints.biggest;
    _clearLines();

    final probe = _painterFor('Ay')..layout();
    final lineHeight = probe.height + _lineSpacing;
    probe.dispose();

    final bands = _geometry?.rowBands ??
        [
          FluidBand(
              start: 0, end: size.height, spans: [Offset.zero & size]),
        ];

    final words = _text
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    var wordIndex = 0;

    for (final band in bands) {
      if (wordIndex >= words.length) break;
      var lineTop = band.start;
      while (lineTop + lineHeight <= band.end &&
          wordIndex < words.length) {
        for (final span in band.spans) {
          if (wordIndex >= words.length) break;
          // Outline-aware padding can trim spans of one band unevenly;
          // only fill lines that fit inside this span vertically.
          if (lineTop < span.top || lineTop + lineHeight > span.bottom) {
            continue;
          }
          final line =
              _fillLine(words, wordIndex, span.width);
          if (line == null) continue; // span too narrow for the next word
          wordIndex = line.$2;
          final painter = _painterFor(line.$1)
            ..layout(maxWidth: span.width);
          _lines.add(_Line(painter, Offset(span.left, lineTop)));
        }
        lineTop += lineHeight;
      }
    }
  }

  /// Greedily packs words into [maxWidth] starting at [from]. Returns the
  /// line content and the next word index, or null when not even one word
  /// fits (a single over-wide word is force-placed to guarantee progress
  /// when this span is the line's first).
  (String, int)? _fillLine(List<String> words, int from, double maxWidth) {
    var line = '';
    var index = from;
    while (index < words.length) {
      final candidate = line.isEmpty ? words[index] : '$line ${words[index]}';
      final painter = _painterFor(candidate)..layout();
      final fits = painter.width <= maxWidth;
      painter.dispose();
      if (!fits) break;
      line = candidate;
      index++;
    }
    if (line.isEmpty) {
      // Nothing fits. Force the word only if we'd otherwise stall forever
      // (i.e. the span could never take it); the painter ellipsizes it.
      final probe = _painterFor(words[from])..layout();
      final hopeless = probe.width > maxWidth && maxWidth > 40;
      probe.dispose();
      if (!hopeless) return null;
      return (words[from], from + 1);
    }
    return (line, index);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final line in _lines) {
      line.painter.paint(context.canvas, offset + line.offset);
    }
  }

  @override
  void detach() {
    _clearLines();
    super.detach();
  }

  @override
  void dispose() {
    _clearLines();
    super.dispose();
  }
}
