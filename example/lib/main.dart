import 'package:fluid_draggable_grid/fluid_draggable_grid.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'dashboard_cards.dart';
import 'diagnostics_console.dart';
import 'prefs_storage.dart';

void main() {
  if (kDebugMode) {
    FluidGridDiagnostics.enabled = true;
    FluidGridDiagnostics.attachDebugPrintLogger();
  }
  runApp(const DemoApp());
}

/// Mouse-drag panning included: the grid background pans spreadsheet-style
/// with any pointer device, while cards and handles claim their own drags.
class _DesktopScrollBehavior extends MaterialScrollBehavior {
  const _DesktopScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => PointerDeviceKind.values.toSet();
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fluid Draggable Grid',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const _DesktopScrollBehavior(),
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C6CF6),
          brightness: Brightness.dark,
          surface: const Color(0xFF101318),
        ),
        scaffoldBackgroundColor: const Color(0xFF0B0D11),
        useMaterial3: true,
      ),
      home: const DashboardPage(),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  FluidGridConfig _config = const FluidGridConfig(
    columns: 8,
    rows: 12,
    minCellExtent: 68,
    maxCellExtent: 128,
    gap: 12,
    insideCornerRadius: 12,
    outsideCornerRadius: 24,
  );

  late FluidGridController _controller = _makeController();
  bool _showConsole = kDebugMode;
  bool _showConfig = false;

  FluidGridController _makeController() => FluidGridController(
        config: _config,
        storage: SharedPrefsGridStorage(),
      );

  void _updateConfig(FluidGridConfig config) {
    setState(() {
      _config = config;
      _controller.dispose();
      _controller = _makeController();
    });
  }

  List<FluidGridCard> _cards(BuildContext context) => [
        FluidGridCard(
          id: 'revenue',
          initialShape: CardShape.rect(0, 0, 3, 2),
          child: const RevenueCard(),
        ),
        FluidGridCard(
          id: 'activity',
          initialShape: CardShape.rect(3, 0, 3, 2),
          child: const ActivityCard(),
        ),
        FluidGridCard(
          id: 'weather',
          initialShape: CardShape.rect(6, 0, 2, 2),
          child: const WeatherCard(),
        ),
        FluidGridCard(
          id: 'tasks',
          initialShape: CardShape.rect(0, 2, 2, 3),
          child: const TasksCard(),
        ),
        FluidGridCard(
          id: 'nowPlaying',
          initialShape: CardShape.rect(2, 2, 3, 2),
          child: const NowPlayingCard(),
        ),
        FluidGridCard(
          id: 'storage',
          initialShape: CardShape.rect(5, 2, 3, 2),
          child: const StorageCard(),
        ),
        FluidGridCard(
          id: 'team',
          initialShape: CardShape.rect(2, 4, 4, 1),
          child: const TeamCard(),
        ),
      ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Fluid Draggable Grid'),
        actions: [
          IconButton(
            tooltip: 'Reset layout to initial shapes',
            icon: const Icon(Icons.restart_alt),
            onPressed: () => _controller.resetLayout(),
          ),
          if (kDebugMode)
            IconButton(
              tooltip: 'Toggle diagnostics console',
              icon: Icon(_showConsole
                  ? Icons.terminal
                  : Icons.terminal_outlined),
              onPressed: () =>
                  setState(() => _showConsole = !_showConsole),
            ),
          IconButton(
            tooltip: 'Grid configuration',
            icon: const Icon(Icons.tune),
            onPressed: () => setState(() => _showConfig = !_showConfig),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: FluidGridView(
              key: ValueKey(_config),
              controller: _controller,
              cards: _cards(context),
            ),
          ),
          if (_showConfig)
            Positioned(
              top: 12,
              right: 12,
              child: _ConfigPanel(
                config: _config,
                onChanged: _updateConfig,
                onClose: () => setState(() => _showConfig = false),
              ),
            ),
          if (_showConsole && kDebugMode)
            const Positioned(
              left: 12,
              bottom: 12,
              child: DiagnosticsConsole(),
            ),
        ],
      ),
    );
  }
}

/// Live-tunable grid setup: gap and radii apply on the fly (the controller
/// is rebuilt; persisted layouts survive because storage is keyed
/// independently of the config).
class _ConfigPanel extends StatelessWidget {
  const _ConfigPanel({
    required this.config,
    required this.onChanged,
    required this.onClose,
  });

  final FluidGridConfig config;
  final ValueChanged<FluidGridConfig> onChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 300,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh
            .withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow: const [
          BoxShadow(
              color: Colors.black54, blurRadius: 24, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('GRID CONFIG',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(letterSpacing: 1.2)),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18),
                onPressed: onClose,
              ),
            ],
          ),
          _slider(context, 'Gap', config.gap, 4, 28,
              (v) => onChanged(config.copyWith(gap: v))),
          _slider(
              context,
              'Outside corner radius',
              config.outsideCornerRadius,
              0,
              40,
              (v) => onChanged(config.copyWith(outsideCornerRadius: v))),
          _slider(
              context,
              'Inside corner radius',
              config.insideCornerRadius,
              0,
              24,
              (v) => onChanged(config.copyWith(insideCornerRadius: v))),
          _slider(context, 'Min cell', config.minCellExtent, 48, 96,
              (v) => onChanged(config.copyWith(minCellExtent: v))),
          _slider(context, 'Max cell', config.maxCellExtent, 96, 200,
              (v) => onChanged(config.copyWith(maxCellExtent: v))),
        ],
      ),
    );
  }

  Widget _slider(BuildContext context, String label, double value,
      double min, double max, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label · ${value.round()}',
            style: Theme.of(context).textTheme.bodySmall),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
