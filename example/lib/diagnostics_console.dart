import 'dart:async';

import 'package:amoeba_grid/amoeba_grid.dart';
import 'package:flutter/material.dart';

/// Floating event feed showing the grid's instrumentation stream live.
class DiagnosticsConsole extends StatefulWidget {
  const DiagnosticsConsole({super.key});

  @override
  State<DiagnosticsConsole> createState() => _DiagnosticsConsoleState();
}

class _DiagnosticsConsoleState extends State<DiagnosticsConsole> {
  static const int _maxLines = 10;
  final List<AmoebaGridEvent> _events = [];
  StreamSubscription<AmoebaGridEvent>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = AmoebaGridDiagnostics.events.listen((event) {
      setState(() {
        _events.add(event);
        if (_events.length > _maxLines) _events.removeAt(0);
      });
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IgnorePointer(
      child: Container(
        width: 460,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('AMOEBA GRID DIAGNOSTICS',
                style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    letterSpacing: 1.2)),
            const SizedBox(height: 6),
            if (_events.isEmpty)
              Text('waiting for events…',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.white38)),
            for (final event in _events)
              Text(
                '${event.kind.name}  ${event.message}'
                '${event.data.isEmpty ? '' : '  ${event.data}'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white70,
                  fontFamily: 'Menlo',
                  fontSize: 11,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
