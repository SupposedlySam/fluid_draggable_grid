import '../foundation/cell.dart';
import 'grid_metrics.dart';
import 'outline.dart';

/// Memoizes traced outlines: shapes are re-requested every frame during
/// morphs and hover repaints, and tracing is pure in (shape, metrics).
class OutlineCache {
  OutlineCache._();

  static final OutlineCache instance = OutlineCache._();

  static const int _capacity = 128;

  final Map<(CardShape, GridMetrics), CardOutline> _cache = {};

  CardOutline outlineFor(CardShape shape, GridMetrics metrics) {
    final key = (shape, metrics);
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit; // re-insert for LRU recency
      return hit;
    }
    final outline = CardOutline.trace(shape, metrics);
    if (_cache.length >= _capacity) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = outline;
    return outline;
  }
}
