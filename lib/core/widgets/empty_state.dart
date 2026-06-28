import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Centered icon + message used for "nothing scanned yet" and "all clear"
/// states.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.accent = AppColors.accent,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Color accent;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: 0.22),
                  accent.withValues(alpha: 0.06),
                ],
              ),
              border: Border.all(color: accent.withValues(alpha: 0.25)),
            ),
            child: Icon(icon, size: 34, color: accent),
          ),
          const SizedBox(height: Insets.lg),
          Text(title, style: AppType.headline),
          if (message != null) ...[
            const SizedBox(height: Insets.sm),
            SizedBox(
              width: 360,
              child: Text(
                message!,
                textAlign: TextAlign.center,
                style: AppType.secondary,
              ),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: Insets.xl),
            action!,
          ],
        ],
      ),
    );
  }
}
