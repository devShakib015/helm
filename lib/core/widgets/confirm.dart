import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'buttons.dart';
import 'glass_panel.dart';

/// A glassy modal confirmation. Returns true if the user confirms.
Future<bool> showHelmConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  IconData icon = Icons.help_outline_rounded,
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (context) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: GlassPanel(
          blur: true,
          color: const Color(0xF21A2030),
          border: AppColors.strokeStrong,
          padding: const EdgeInsets.all(Insets.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: (danger ? AppColors.danger : AppColors.accent)
                          .withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                    child: Icon(icon,
                        color: danger ? AppColors.danger : AppColors.accent,
                        size: 22),
                  ),
                  const SizedBox(width: Insets.md),
                  Expanded(child: Text(title, style: AppType.headline)),
                ],
              ),
              const SizedBox(height: Insets.lg),
              Text(message, style: AppType.secondary),
              const SizedBox(height: Insets.xl),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  HelmButton(
                    label: cancelLabel,
                    kind: HelmButtonKind.ghost,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  const SizedBox(width: Insets.md),
                  HelmButton(
                    label: confirmLabel,
                    kind: danger ? HelmButtonKind.danger : HelmButtonKind.primary,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return result ?? false;
}
