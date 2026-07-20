import 'dart:math' as math;

import 'package:amoeba_grid/amoeba_grid.dart';
import 'package:flutter/material.dart';

/// Adaptive card scaffold: full layout when there's room, compact icon+title
/// when the user squeezes the card down, so reshaping never overflows.
class CardScaffold extends StatelessWidget {
  const CardScaffold({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 96;
        final header = Row(
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            if (trailing != null && !compact) trailing!,
          ],
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          child: compact
              ? Align(alignment: Alignment.centerLeft, child: header)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    header,
                    const SizedBox(height: 10),
                    Expanded(child: ClipRect(child: child)),
                  ],
                ),
        );
      },
    );
  }
}

class RevenueCard extends StatelessWidget {
  const RevenueCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CardScaffold(
      icon: Icons.trending_up,
      title: 'REVENUE',
      trailing: _DeltaChip(delta: '+12.4%', color: theme.colorScheme.primary),
      child: LayoutBuilder(builder: (context, constraints) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '\$48,290',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            Text('vs \$42,960 last month',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
            if (constraints.maxHeight > 130) ...[
              const Spacer(),
              SizedBox(
                height: math.min(56, constraints.maxHeight - 76),
                width: double.infinity,
                child: CustomPaint(
                  painter: BarSparklinePainter(
                    values: const [.35, .5, .42, .61, .55, .72, .66, .84, .9],
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ],
        );
      }),
    );
  }
}

class ActivityCard extends StatelessWidget {
  const ActivityCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CardScaffold(
      icon: Icons.monitor_heart_outlined,
      title: 'ACTIVITY',
      child: CustomPaint(
        size: Size.infinite,
        painter: LineChartPainter(
          values: const [.2, .45, .3, .65, .5, .8, .6, .9, .75, .95],
          color: theme.colorScheme.tertiary,
        ),
      ),
    );
  }
}

class WeatherCard extends StatelessWidget {
  const WeatherCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CardScaffold(
      icon: Icons.cloud_outlined,
      title: 'CUPERTINO',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('72°',
                style: theme.textTheme.displayMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
          Text('Partly cloudy · H 78° L 61°',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// Tasks flow through the card's shape with [AmoebaColumn]: rows narrow to
/// the band they land in, so carving a notch into the card reflows the list
/// around it instead of clipping it.
class TasksCard extends StatefulWidget {
  const TasksCard({super.key});

  @override
  State<TasksCard> createState() => _TasksCardState();
}

class _TasksCardState extends State<TasksCard> {
  final List<(String, bool)> _tasks = [
    ('Review grid PR', true),
    ('Ship 0.1.0 to pub.dev', false),
    ('Design corner handles', true),
    ('Amoeba morph polish', false),
    ('Persistence buckets QA', false),
    ('AmoebaText line breaks', false),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AmoebaPadding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: AmoebaColumn(
        spacing: 2,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_outline,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('TASKS',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: 0.4,
                    )),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final (index, (label, done)) in _tasks.indexed)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () =>
                  setState(() => _tasks[index] = (label, !done)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      done
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: done
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          decoration:
                              done ? TextDecoration.lineThrough : null,
                          color: done
                              ? theme.colorScheme.onSurfaceVariant
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// [AmoebaText] demo: prose wraps band by band around whatever notches you
/// carve into the card — Flutter's answer to CSS `shape-outside`.
class NotesCard extends StatelessWidget {
  const NotesCard({super.key});

  static const _prose =
      'Amoeba cards are not rectangles. Drag a side handle and only that '
      'strip moves; pull the corner and the whole edge follows. This '
      'paragraph is laid out line by line against the free span of every '
      'band in the shape, so carve a notch into this card and watch the '
      'words flow around it like water finding its level. Drop previews '
      'snap at half-cell crossings, gaps stay honest, and everything you '
      'shape here is remembered per viewport width.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AmoebaPadding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: AmoebaText(
        _prose,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.35,
        ),
        lineSpacing: 2,
      ),
    );
  }
}

/// [AmoebaRegions] demo: the shape's maximal-rectangle decomposition is
/// rendered live — reshape the card and watch the regions re-partition.
class RegionsCard extends StatelessWidget {
  const RegionsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AmoebaPadding(
      padding: const EdgeInsets.all(10),
      child: AmoebaRegions(
        builder: (context, region) {
          final tint = Color.lerp(
              theme.colorScheme.primary,
              theme.colorScheme.tertiary,
              (region.index * 0.28) % 1)!;
          return Padding(
            padding: const EdgeInsets.all(3),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: tint.withValues(alpha: 0.45)),
              ),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(
                      region.isLargest
                          ? 'REGION ${region.index}\n'
                              '${region.cellWidth}x${region.cellHeight} · largest'
                          : 'R${region.index} · '
                              '${region.cellWidth}x${region.cellHeight}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: tint, letterSpacing: 0.6),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class NowPlayingCard extends StatelessWidget {
  const NowPlayingCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CardScaffold(
      icon: Icons.graphic_eq,
      title: 'NOW PLAYING',
      child: LayoutBuilder(builder: (context, constraints) {
        return Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.tertiary,
                  ],
                ),
              ),
              child: const Icon(Icons.music_note, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Weightless',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  Text('Marconi Union',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                  if (constraints.maxHeight > 96) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: 0.37,
                      minHeight: 3,
                      borderRadius: BorderRadius.circular(2),
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      }),
    );
  }
}

class StorageCard extends StatelessWidget {
  const StorageCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CardScaffold(
      icon: Icons.donut_large_outlined,
      title: 'STORAGE',
      child: Row(
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: CustomPaint(
              painter: GaugePainter(
                value: 0.68,
                color: theme.colorScheme.primary,
                trackColor: theme.colorScheme.surfaceContainerHighest,
              ),
              child: Center(
                child: Text('68%',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LegendRow(
                    color: theme.colorScheme.primary,
                    label: 'Media',
                    value: '412 GB'),
                _LegendRow(
                    color: theme.colorScheme.tertiary,
                    label: 'Documents',
                    value: '88 GB'),
                _LegendRow(
                    color: theme.colorScheme.outline,
                    label: 'Free',
                    value: '236 GB'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TeamCard extends StatelessWidget {
  const TeamCard({super.key});

  static const _members = ['JW', 'AS', 'MK', 'RB', 'TL', 'CP'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CardScaffold(
      icon: Icons.people_outline,
      title: 'TEAM',
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            // Facepile overlap: every avatar after the first sits in a
            // narrower box aligned right, so it overhangs leftward over
            // its predecessor — nothing leaks past the row's left edge.
            for (final (index, initials) in _members.indexed)
              Align(
                widthFactor: index == 0 ? 1.0 : 0.72,
                alignment: Alignment.centerRight,
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: Color.lerp(
                      theme.colorScheme.primary,
                      theme.colorScheme.tertiary,
                      index / (_members.length - 1))!,
                  child: Text(initials,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: Colors.white)),
                ),
              ),
            const SizedBox(width: 16),
            Text('6 online',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _DeltaChip extends StatelessWidget {
  const _DeltaChip({required this.delta, required this.color});

  final String delta;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(delta,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: color, fontWeight: FontWeight.w700)),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow(
      {required this.color, required this.label, required this.value});

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
              width: 8,
              height: 8,
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall),
          ),
          Text(value,
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class BarSparklinePainter extends CustomPainter {
  BarSparklinePainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = size.width / (values.length * 1.6);
    final step = size.width / values.length;
    for (final (index, value) in values.indexed) {
      final paint = Paint()
        ..color = color.withValues(
            alpha: index == values.length - 1 ? 1.0 : 0.35);
      final barHeight = size.height * value;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(index * step + (step - barWidth) / 2,
              size.height - barHeight, barWidth, barHeight),
          Radius.circular(barWidth / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(BarSparklinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}

class LineChartPainter extends CustomPainter {
  LineChartPainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final points = [
      for (final (index, value) in values.indexed)
        Offset(size.width * index / (values.length - 1),
            size.height * (1 - value)),
    ];
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final controlX = (prev.dx + curr.dx) / 2;
      line.cubicTo(controlX, prev.dy, controlX, curr.dy, curr.dx, curr.dy);
    }

    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.30), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(LineChartPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}

class GaugePainter extends CustomPainter {
  GaugePainter(
      {required this.value, required this.color, required this.trackColor});

  final double value;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 5;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, stroke..color = trackColor);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * value,
      false,
      stroke..color = color,
    );
  }

  @override
  bool shouldRepaint(GaugePainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor;
}
