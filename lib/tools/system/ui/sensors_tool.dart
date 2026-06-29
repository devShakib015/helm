import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/menu_metric.dart';
import '../../../core/models/system_stats.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/ring_gauge.dart';
import '../state/stats_controller.dart';

/// Live thermal dashboard: temperatures and fan speed read from the SMC. Apple
/// Silicon currently exposes these only through low-level SMC access that Helm
/// doesn't ship yet, so [SystemStats.tempCpu] / `.tempGpu` / `.fan` are usually
/// null — this page degrades to a friendly explainer in that case and lights up
/// automatically once real values start arriving. The [StatsController] polls
/// on its own, so this root stays stateless.
class SensorsTool extends StatelessWidget {
  const SensorsTool({super.key});

  /// Sensors accent (amber) — shared with the menu-bar temperature metric.
  static final Color _accent = metricInfo(MenuMetric.temp).color;

  @override
  Widget build(BuildContext context) {
    final stats = context.watch<StatsController>().stats;
    final hasAny =
        stats.tempCpu != null || stats.tempGpu != null || stats.fan != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          Insets.xxl, Insets.xl, Insets.xxl, Insets.xxl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PageHeader(
                title: 'Sensors',
                subtitle: 'Temperatures & fans',
              ),
              const SizedBox(height: Insets.xl),
              if (!hasAny)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Insets.xxl),
                  child: EmptyState(
                    icon: Icons.thermostat_rounded,
                    accent: _accent,
                    title: 'Sensor data unavailable',
                    message:
                        'Helm needs low-level SMC access to read temperatures '
                        'and fan speeds on Apple Silicon. This is coming in an '
                        'update.',
                  ),
                )
              else
                _SensorGrid(stats: stats, accent: _accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lays out one card per available sensor. Temperatures render as ring gauges
/// (with a colour that warms as the reading climbs); the fan renders as a stat
/// tile. Only non-null sensors appear.
class _SensorGrid extends StatelessWidget {
  const _SensorGrid({required this.stats, required this.accent});

  final SystemStats stats;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      if (stats.tempCpu != null)
        _TempCard(
          label: 'CPU Temp',
          icon: Icons.developer_board_rounded,
          celsius: stats.tempCpu!,
          accent: accent,
        ),
      if (stats.tempGpu != null)
        _TempCard(
          label: 'GPU Temp',
          icon: Icons.auto_awesome_motion_rounded,
          celsius: stats.tempGpu!,
          accent: accent,
        ),
      if (stats.fan != null)
        _FanCard(rpm: stats.fan!, accent: accent),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Up to three cards side by side; wrap to fewer columns when cramped.
        final cols = constraints.maxWidth >= 760
            ? cards.length.clamp(1, 3)
            : (constraints.maxWidth >= 480 ? cards.length.clamp(1, 2) : 1);
        const gap = Insets.lg;
        final tileWidth =
            (constraints.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          alignment: WrapAlignment.center,
          children: [
            for (final card in cards)
              SizedBox(width: tileWidth, child: card),
          ],
        );
      },
    );
  }
}

/// A temperature reading shown as a ring gauge over a 0–100 °C scale.
class _TempCard extends StatelessWidget {
  const _TempCard({
    required this.label,
    required this.icon,
    required this.celsius,
    required this.accent,
  });

  final String label;
  final IconData icon;
  final double celsius;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final color = _tempColor(celsius, accent);
    return GlassPanel(
      padding: const EdgeInsets.symmetric(
          horizontal: Insets.lg, vertical: Insets.xl),
      glow: color.withValues(alpha: 0.10),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 5),
              Text(label.toUpperCase(), style: AppType.micro),
            ],
          ),
          const SizedBox(height: Insets.lg),
          RingGauge(
            value: (celsius / 100).clamp(0.0, 1.0),
            size: 160,
            thickness: 14,
            color: color,
            center: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${celsius.round()}°',
                  style: AppType.display.copyWith(
                    fontSize: 40,
                    color: AppColors.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text('Celsius', style: AppType.caption),
              ],
            ),
          ),
          const SizedBox(height: Insets.lg),
          Text(
            _tempLabel(celsius),
            style: AppType.caption.copyWith(color: color),
          ),
        ],
      ),
    );
  }

  Color _tempColor(double c, Color accent) {
    if (c >= 90) return AppColors.danger;
    if (c >= 75) return AppColors.warning;
    if (c >= 55) return accent;
    return AppColors.success;
  }

  String _tempLabel(double c) {
    if (c >= 90) return 'Critical';
    if (c >= 75) return 'Hot';
    if (c >= 55) return 'Warm';
    return 'Cool';
  }
}

/// The fan speed, shown as a compact stat tile.
class _FanCard extends StatelessWidget {
  const _FanCard({required this.rpm, required this.accent});

  final double rpm;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: StatTile(
        label: 'Fan',
        value: '${rpm.round()} rpm',
        sub: rpm <= 0 ? 'Idle' : 'Cooling',
        icon: Icons.air_rounded,
        color: accent,
      ),
    );
  }
}
