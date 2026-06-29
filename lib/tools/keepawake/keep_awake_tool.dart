import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/hoverable.dart';
import '../../core/widgets/page_header.dart';
import 'keep_awake_controller.dart';

/// Keep Awake: a caffeine-style switch that prevents display and system sleep,
/// either indefinitely or for a chosen duration.
class KeepAwakeTool extends StatelessWidget {
  const KeepAwakeTool({super.key});

  static const Color _accent = Color(0xFFF59E0B);

  @override
  Widget build(BuildContext context) {
    final c = context.watch<KeepAwakeController>();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          Insets.xxl, Insets.xl, Insets.xxl, Insets.xxl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PageHeader(
                title: 'Keep Awake',
                subtitle: 'Prevent your Mac from sleeping',
              ),
              const SizedBox(height: Insets.xl),
              _Hero(controller: c, accent: _accent),
              const SizedBox(height: Insets.lg),
              _DurationSection(controller: c, accent: _accent),
              const SizedBox(height: Insets.lg),
              const _AboutCard(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.controller, required this.accent});

  final KeepAwakeController controller;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final active = controller.active;
    final color = active ? accent : AppColors.textTertiary;
    return GlassPanel(
      padding: const EdgeInsets.all(Insets.xl),
      glow: active ? accent.withValues(alpha: 0.12) : null,
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.16),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Icon(Icons.local_cafe_rounded, size: 34, color: color),
          ),
          const SizedBox(width: Insets.xl),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(active ? 'Staying awake' : 'Normal sleep',
                    style: AppType.title),
                const SizedBox(height: 4),
                Text(_subtitle(controller), style: AppType.secondary),
              ],
            ),
          ),
          const SizedBox(width: Insets.lg),
          _ToggleButton(
            active: active,
            accent: accent,
            onTap: () => active
                ? controller.deactivate()
                : controller.activate(),
          ),
        ],
      ),
    );
  }

  String _subtitle(KeepAwakeController c) {
    if (!c.active) return 'Your Mac will sleep on its usual schedule';
    final remaining = c.remaining;
    if (c.duration == null) return 'Indefinitely — until you turn it off';
    return 'For ${_fmt(c.duration!)} · ${_fmt(remaining ?? Duration.zero)} left';
  }
}

/// Duration presets — tapping one activates Keep Awake for that span.
class _DurationSection extends StatelessWidget {
  const _DurationSection({required this.controller, required this.accent});

  final KeepAwakeController controller;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(Insets.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: Insets.md),
            child: Text('DURATION', style: AppType.micro),
          ),
          Wrap(
            spacing: Insets.sm,
            runSpacing: Insets.sm,
            children: [
              for (final d in kAwakeDurations)
                _DurationChip(
                  label: d.label,
                  selected: controller.active &&
                      controller.duration == d.duration,
                  accent: accent,
                  onTap: () => controller.activate(duration: d.duration),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DurationChip extends StatelessWidget {
  const _DurationChip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (context, hovered, _) {
        final bg = selected
            ? accent.withValues(alpha: 0.18)
            : (hovered ? AppColors.glassHover : AppColors.glass);
        final border = selected
            ? accent.withValues(alpha: 0.55)
            : (hovered ? AppColors.strokeStrong : AppColors.stroke);
        final fg = selected ? accent : AppColors.textSecondary;
        return AnimatedContainer(
          duration: Motion.fast,
          padding: const EdgeInsets.symmetric(
              horizontal: Insets.lg, vertical: Insets.sm),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: Radii.pill,
            border: Border.all(color: border),
          ),
          child: Text(
            label,
            style: AppType.caption.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      },
    );
  }
}

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({
    required this.active,
    required this.accent,
    required this.onTap,
  });

  final bool active;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.danger : accent;
    return Hoverable(
      onTap: onTap,
      builder: (context, hovered, _) => AnimatedContainer(
        duration: Motion.fast,
        padding: const EdgeInsets.symmetric(
            horizontal: Insets.lg, vertical: Insets.md),
        decoration: BoxDecoration(
          color: color.withValues(alpha: hovered ? 0.30 : 0.20),
          borderRadius: Radii.pill,
          border: Border.all(color: color.withValues(alpha: 0.55)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(active ? Icons.stop_rounded : Icons.bolt_rounded,
                size: 16, color: color),
            const SizedBox(width: Insets.sm),
            Text(active ? 'Turn Off' : 'Keep Awake',
                style: AppType.bodyStrong.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(Insets.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 18, color: AppColors.textTertiary),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Text(
              'While active, your display and Mac won’t sleep and the screen '
              'saver won’t start. You can also toggle this from the menu-bar '
              'icon. It turns off automatically when Helm quits.',
              style: AppType.caption.copyWith(color: AppColors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

String _fmt(Duration d) {
  if (d.inHours > 0) {
    final m = d.inMinutes % 60;
    return m == 0 ? '${d.inHours}h' : '${d.inHours}h ${m}m';
  }
  if (d.inMinutes > 0) return '${d.inMinutes}m';
  return '${d.inSeconds}s';
}
