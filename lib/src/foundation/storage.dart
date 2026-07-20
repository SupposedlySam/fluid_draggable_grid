import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'cell.dart';
import 'config.dart';
import 'diagnostics.dart';

/// Where the grid persists user card shaping between sessions.
///
/// The package stays plugin-free: implement this with whatever your app
/// already uses (`shared_preferences`, a file, a server). The demo app ships
/// a `shared_preferences` implementation.
abstract interface class FluidGridStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

/// In-memory storage; layouts survive rebuilds but not app restarts.
/// Useful as a default and in tests.
class FluidGridMemoryStorage implements FluidGridStorage {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}

/// Persisted user layout overrides, keyed mobile-first by the viewport-width
/// breakpoint that was active when the user edited.
///
/// Resolution for a card at viewport width `w`: walk the breakpoints from the
/// bucket for `w` downward and return the first override found; otherwise the
/// card's programmatic initial shape applies. This means shaping done on a
/// narrow window carries up to wider windows until the user overrides it
/// there too — mobile-first, like CSS breakpoints.
@immutable
class FluidGridLayoutData {
  const FluidGridLayoutData(this.overrides);

  const FluidGridLayoutData.empty() : overrides = const {};

  /// breakpoint -> cardId -> shape
  final Map<double, Map<String, CardShape>> overrides;

  static const int _version = 1;

  CardShape? resolve(String cardId, double viewportWidth,
      FluidGridConfig config) {
    for (final b in config.breakpoints.reversed) {
      if (b > viewportWidth) continue;
      final shape = overrides[b]?[cardId];
      if (shape != null) return shape;
    }
    return null;
  }

  /// Returns a copy with [shapes] written into [bucket].
  FluidGridLayoutData withBucketShapes(
      double bucket, Map<String, CardShape> shapes) {
    final next = {
      for (final e in overrides.entries) e.key: Map.of(e.value),
    };
    (next[bucket] ??= {}).addAll(shapes);
    return FluidGridLayoutData(next);
  }

  String encode() => jsonEncode({
        'version': _version,
        'overrides': {
          for (final e in overrides.entries)
            e.key.toString(): {
              for (final card in e.value.entries)
                card.key: card.value.toJson(),
            },
        },
      });

  static FluidGridLayoutData decode(String json) {
    final root = jsonDecode(json) as Map<String, dynamic>;
    final rawOverrides = root['overrides'] as Map<String, dynamic>? ?? {};
    return FluidGridLayoutData({
      for (final e in rawOverrides.entries)
        double.parse(e.key): {
          for (final card in (e.value as Map<String, dynamic>).entries)
            card.key: CardShape.fromJson(card.value as List<dynamic>),
        },
    });
  }
}

/// Load/save helper shared by the controller.
class FluidGridLayoutStore {
  FluidGridLayoutStore(this.storage, {this.storageKey = defaultKey});

  static const String defaultKey = 'fluid_draggable_grid.layout.v1';

  final FluidGridStorage storage;
  final String storageKey;

  Future<FluidGridLayoutData> load() async {
    try {
      final raw = await storage.read(storageKey);
      if (raw == null) return const FluidGridLayoutData.empty();
      final data = FluidGridLayoutData.decode(raw);
      FluidGridDiagnostics.emit(FluidGridEventKind.layoutLoaded,
          'loaded persisted layout', {'buckets': data.overrides.keys.toList()});
      return data;
    } catch (error) {
      FluidGridDiagnostics.emit(FluidGridEventKind.layoutLoaded,
          'failed to load layout, starting fresh', {'error': '$error'});
      return const FluidGridLayoutData.empty();
    }
  }

  Future<void> save(FluidGridLayoutData data) async {
    await storage.write(storageKey, data.encode());
    FluidGridDiagnostics.emit(FluidGridEventKind.layoutSaved, 'layout saved',
        {'buckets': data.overrides.keys.toList()});
  }
}
