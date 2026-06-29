import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/menu_metric.dart';
import '../../../core/models/system_stats.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/ring_gauge.dart';
import '../../network/widgets/sparkline.dart';
import '../state/stats_controller.dart';

/// Live processor monitor: a hero ring gauge of total CPU usage beside a usage
/// sparkline, a per-logical-core breakdown, and a small stat row. Reads the
/// app-wide [StatsController], which self-polls — this page stays stateless.
class CpuTool extends StatelessWidget {
  const CpuTool({super.key});

  @override
  Widget build(BuildContext context) {
    final accent = metricInfo(MenuMetric.cpu).color;
    final c = context.watch<StatsController>();

    if (!c.loaded) {
      return Center(child: CircularProgressIndicator(color: accent));
    }

    final stats = c.stats;

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
                title: 'Processor',
                subtitle: 'Live CPU usage',
              ),
              const SizedBox(height: Insets.xl),
              _HeroPanel(
                cpu: stats.cpu,
                history: c.cpuHistory,
                accent: accent,
              ),
              const SizedBox(height: Insets.lg),
              _CoresPanel(perCore: stats.cpuPerCore, accent: accent),
              const SizedBox(height: Insets.lg),
              _StatRow(stats: stats, accent: accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// The hero glass panel: a ring gauge of total usage on the left, and a
/// width-filling usage sparkline on the right.
class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.cpu,
    required this.history,
    required this.accent,
  });

  final double cpu;
  final List<double> history;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.symmetric(
          horizontal: Insets.xl, vertical: Insets.xl),
      glow: accent.withValues(alpha: 0.10),
      child: Row(
        children: [
          RingGauge(
            value: (cpu / 100).clamp(0.0, 1.0),
            size: 168,
            thickness: 14,
            color: accent,
            center: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${cpu.round()}%',
                  style: AppType.display.copyWith(
                    fontSize: 40,
                    color: AppColors.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text('usage', style: AppType.caption),
              ],
            ),
          ),
          const SizedBox(width: Insets.xl),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('History', style: AppType.micro),
                const SizedBox(height: Insets.sm),
                SizedBox(
                  height: 80,
                  child: Sparkline(
                    samples: history,
                    color: accent,
                    height: 80,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Per-logical-core usage bars, one row per core.
class _CoresPanel extends StatelessWidget {
  const _CoresPanel({required this.perCore, required this.accent});

  final List<double> perCore;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(Insets.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.developer_board_rounded, size: 16, color: accent),
              const SizedBox(width: Insets.sm),
              Text('Cores', style: AppType.headline),
            ],
          ),
          const SizedBox(height: Insets.md),
          if (perCore.isEmpty)
            Text(
              'Per-core usage is not available on this Mac.',
              style: AppType.caption.copyWith(color: AppColors.textTertiary),
            )
          else
            for (var i = 0; i < perCore.length; i++) ...[
              if (i > 0) const SizedBox(height: Insets.md),
              _CoreRow(index: i, value: perCore[i], accent: accent),
            ],
        ],
      ),
    );
  }
}

class _CoreRow extends StatelessWidget {
  const _CoreRow({
    required this.index,
    required this.value,
    required this.accent,
  });

  final int index;
  final double value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Text('Core ${index + 1}', style: AppType.caption),
        ),
        const SizedBox(width: Insets.md),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.sm),
            child: LinearProgressIndicator(
              value: (value / 100).clamp(0.0, 1.0),
              minHeight: 6,
              color: accent,
              backgroundColor: AppColors.glassStrong,
            ),
          ),
        ),
        const SizedBox(width: Insets.md),
        SizedBox(
          width: 40,
          child: Text(
            '${value.round()}%',
            textAlign: TextAlign.right,
            style: AppType.mono.copyWith(color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// Bottom summary row: total usage and logical core count.
class _StatRow extends StatelessWidget {
  const _StatRow({required this.stats, required this.accent});

  final SystemStats stats;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: StatTile(
              label: 'Total Usage',
              value: '${stats.cpu.round()}%',
              icon: Icons.speed_rounded,
              color: accent,
            ),
          ),
          const SizedBox(width: Insets.md),
          Expanded(
            child: StatTile(
              label: 'Logical Cores',
              value: '${stats.cpuPerCore.length}',
              icon: Icons.developer_board_rounded,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
