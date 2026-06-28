import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons.dart';
import '../../../../core/widgets/glass_panel.dart';
import '../../../../core/widgets/hoverable.dart';

/// Consistent page title block with optional trailing actions.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppType.display),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: AppType.secondary),
              ],
            ],
          ),
        ),
        for (final a in actions) ...[const SizedBox(width: Insets.md), a],
      ],
    );
  }
}

/// Small labelled metric tile.
class StatChip extends StatelessWidget {
  const StatChip({
    super.key,
    required this.label,
    required this.value,
    this.color = AppColors.textPrimary,
    this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.symmetric(
          horizontal: Insets.lg, vertical: Insets.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: color),
                const SizedBox(width: 5),
              ],
              Text(label.toUpperCase(), style: AppType.micro),
            ],
          ),
          const SizedBox(height: Insets.sm),
          Text(value,
              style: AppType.title.copyWith(
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
        ],
      ),
    );
  }
}

/// Coloured dot + label + value, for chart legends.
class LegendRow extends StatelessWidget {
  const LegendRow({
    super.key,
    required this.color,
    required this.label,
    required this.value,
    this.emphasized = false,
    this.onTap,
  });

  final Color color;
  final String label;
  final String value;
  final bool emphasized;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Widget content(bool hovered) => Container(
          padding: const EdgeInsets.symmetric(
              horizontal: Insets.sm, vertical: 6),
          decoration: BoxDecoration(
            color: hovered ? AppColors.glass : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: [
                    BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6),
                  ],
                ),
              ),
              const SizedBox(width: Insets.md),
              Expanded(
                child: Text(label,
                    style: emphasized ? AppType.bodyStrong : AppType.body),
              ),
              Text(value, style: AppType.mono),
              if (onTap != null)
                AnimatedOpacity(
                  duration: Motion.fast,
                  opacity: hovered ? 1 : 0,
                  child: const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(Icons.chevron_right_rounded,
                        size: 15, color: AppColors.textTertiary),
                  ),
                ),
            ],
          ),
        );
    if (onTap == null) return content(false);
    return Hoverable(
      onTap: onTap,
      builder: (context, hovered, _) => content(hovered),
    );
  }
}

/// Inline notice strip (Full Disk Access prompt, stale results, etc.).
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.accent,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.onDismiss,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color accent;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      color: accent.withValues(alpha: 0.08),
      border: accent.withValues(alpha: 0.28),
      padding: const EdgeInsets.symmetric(
          horizontal: Insets.lg, vertical: Insets.md),
      child: Row(
        children: [
          Icon(icon, color: accent, size: 20),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppType.bodyStrong),
                const SizedBox(height: 1),
                Text(message, style: AppType.caption),
              ],
            ),
          ),
          if (secondaryLabel != null && onSecondary != null) ...[
            const SizedBox(width: Insets.md),
            HelmButton(
                label: secondaryLabel!,
                kind: HelmButtonKind.ghost,
                onPressed: onSecondary),
          ],
          if (primaryLabel != null && onPrimary != null) ...[
            const SizedBox(width: Insets.md),
            HelmButton(label: primaryLabel!, onPressed: onPrimary),
          ],
          if (onDismiss != null) ...[
            const SizedBox(width: Insets.sm),
            IconSquareButton(
                icon: Icons.close_rounded, onPressed: onDismiss!, tooltip: 'Dismiss'),
          ],
        ],
      ),
    );
  }
}
