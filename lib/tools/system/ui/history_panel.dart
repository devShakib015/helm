import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/hoverable.dart';
import '../../../core/widgets/time_chart.dart';
import '../state/stats_history.dart';

/// "History" card shared by the monitor pages: a 1h/6h/24h range picker over
/// a [TimeChart] fed from the app-wide [StatsHistory].
class HistoryPanel extends StatefulWidget {
  const HistoryPanel({
    super.key,
    required this.title,
    required this.color,
    required this.extract,
    this.maxY = 100,
    this.formatValue,
  });

  final String title;
  final Color color;

  /// Pulls this page's series out of a sample (null = skip the point).
  final double? Function(HistPoint p) extract;

  /// Fixed top of the y-axis (100 for percentages); null auto-scales.
  final double? maxY;
  final String Function(double v)? formatValue;

  @override
  State<HistoryPanel> createState() => _HistoryPanelState();
}

class _HistoryPanelState extends State<HistoryPanel> {
  Duration _window = const Duration(hours: 1);

  static const _ranges = [
    (label: '1h', window: Duration(hours: 1)),
    (label: '6h', window: Duration(hours: 6)),
    (label: '24h', window: Duration(hours: 24)),
  ];

  @override
  Widget build(BuildContext context) {
    final history = context.watch<StatsHistory>();
    final points = <TimePoint>[
      for (final p in history.recent(_window))
        if (widget.extract(p) case final v?) TimePoint(p.tMs, v),
    ];

    return GlassPanel(
      padding: const EdgeInsets.all(Insets.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.history_rounded, size: 16, color: widget.color),
              const SizedBox(width: Insets.sm),
              Text(widget.title, style: AppType.headline),
              const Spacer(),
              for (final r in _ranges) ...[
                const SizedBox(width: 4),
                _RangePill(
                  label: r.label,
                  selected: _window == r.window,
                  color: widget.color,
                  onTap: () => setState(() => _window = r.window),
                ),
              ],
            ],
          ),
          const SizedBox(height: Insets.lg),
          TimeChart(
            points: points,
            window: _window,
            color: widget.color,
            maxY: widget.maxY,
            formatValue: widget.formatValue,
          ),
        ],
      ),
    );
  }
}

class _RangePill extends StatelessWidget {
  const _RangePill({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (context, hovered, _) => AnimatedContainer(
        duration: Motion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.20)
              : (hovered ? const Color(0x1FFFFFFF) : Colors.transparent),
          borderRadius: Radii.pill,
          border: Border.all(
            color: selected ? color.withValues(alpha: 0.5) : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: AppType.caption.copyWith(
            color: selected ? color : null,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
