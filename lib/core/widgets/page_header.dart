import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'glass_panel.dart';

/// Shared page title block (title + subtitle + trailing actions). Used by every
/// tool so headers are consistent across the app.
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

/// A labelled metric tile: small caption label, large tabular value, optional
/// sub-line and leading accent icon. Reused across the dashboards.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.sub,
    this.icon,
    this.color = AppColors.textPrimary,
  });

  final String label;
  final String value;
  final String? sub;
  final IconData? icon;
  final Color color;

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
          Text(
            value,
            style: AppType.title.copyWith(
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(sub!, style: AppType.caption.copyWith(color: AppColors.textTertiary)),
          ],
        ],
      ),
    );
  }
}
