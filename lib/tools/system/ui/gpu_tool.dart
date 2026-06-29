import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/menu_metric.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/ring_gauge.dart';
import '../../network/widgets/sparkline.dart';
import '../state/stats_controller.dart';

/// Live GPU utilization dashboard: a hero ring gauge with the current device
/// activity percentage, a full-width sparkline of recent history, and a short
/// explanatory note. The [StatsController] self-samples on a timer, so this
/// root stays stateless.
class GpuTool extends StatelessWidget {
  const GpuTool({super.key});

  @override
  Widget build(BuildContext context) {
    final accent = metricInfo(MenuMetric.gpu).color;
    final c = context.watch<StatsController>();

    if (!c.loaded) {
      return Center(
        child: CircularProgressIndicator(color: accent),
      );
    }

    final gpu = c.stats.gpu;

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
                title: 'Graphics',
                subtitle: 'Live GPU utilization',
              ),
              const SizedBox(height: Insets.xl),
              _GpuHeroPanel(gpu: gpu, history: c.gpuHistory, accent: accent),
              const SizedBox(height: Insets.lg),
              _GpuNote(accent: accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// The hero panel: a ring gauge of current utilization with a full-width
/// history sparkline beneath it.
class _GpuHeroPanel extends StatelessWidget {
  const _GpuHeroPanel({
    required this.gpu,
    required this.history,
    required this.accent,
  });

  final double gpu;
  final List<double> history;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.symmetric(
          horizontal: Insets.xl, vertical: Insets.xl),
      glow: accent.withValues(alpha: 0.10),
      child: Column(
        children: [
          RingGauge(
            value: (gpu / 100).clamp(0.0, 1.0),
            size: 188,
            thickness: 16,
            color: accent,
            center: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${gpu.round()}%',
                  style: AppType.display.copyWith(
                    fontSize: 44,
                    color: AppColors.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'utilization',
                  style: AppType.caption.copyWith(color: accent),
                ),
              ],
            ),
          ),
          const SizedBox(height: Insets.xl),
          Sparkline(samples: history, color: accent, height: 80),
        ],
      ),
    );
  }
}

/// A short explanatory note about what GPU utilization means.
class _GpuNote extends StatelessWidget {
  const _GpuNote({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(Insets.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: Icon(Icons.auto_awesome_motion_rounded,
                size: 17, color: accent),
          ),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('About this metric', style: AppType.bodyStrong),
                const SizedBox(height: 2),
                Text(
                  'GPU utilization is the integrated Apple GPU\'s device '
                  'activity.',
                  style:
                      AppType.caption.copyWith(color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
