import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'hoverable.dart';

enum HelmButtonKind { primary, ghost, danger }

/// The app's pill button. Gradient for primary, glass for ghost, red for
/// destructive actions. Animates brightness on hover and dims when disabled or
/// busy.
class HelmButton extends StatelessWidget {
  const HelmButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.kind = HelmButtonKind.primary,
    this.busy = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final HelmButtonKind kind;
  final bool busy;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Hoverable(
      enabled: enabled,
      onTap: onPressed,
      builder: (context, hovered, pressed) {
        final scale = pressed ? 0.97 : 1.0;
        return AnimatedScale(
          scale: scale,
          duration: Motion.fast,
          child: AnimatedOpacity(
            opacity: enabled ? 1 : 0.45,
            duration: Motion.fast,
            child: Container(
              height: 38,
              width: expand ? double.infinity : null,
              padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
              decoration: _decoration(hovered),
              child: Row(
                mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (busy)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  else if (icon != null)
                    Icon(icon, size: 16, color: _fg),
                  if (busy || icon != null) const SizedBox(width: 8),
                  Text(label,
                      style: AppType.bodyStrong.copyWith(color: _fg)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Color get _fg => switch (kind) {
        HelmButtonKind.primary => Colors.white,
        HelmButtonKind.danger => Colors.white,
        HelmButtonKind.ghost => AppColors.textPrimary,
      };

  BoxDecoration _decoration(bool hovered) {
    switch (kind) {
      case HelmButtonKind.primary:
        return BoxDecoration(
          gradient: AppColors.accentGradient,
          borderRadius: Radii.pill,
          boxShadow: [
            BoxShadow(
              color: AppColors.accent.withValues(alpha: hovered ? 0.5 : 0.32),
              blurRadius: hovered ? 22 : 14,
              spreadRadius: -4,
            ),
          ],
        );
      case HelmButtonKind.danger:
        return BoxDecoration(
          color: hovered ? const Color(0xFFFF6B6B) : AppColors.danger,
          borderRadius: Radii.pill,
          boxShadow: [
            BoxShadow(
              color: AppColors.danger.withValues(alpha: hovered ? 0.45 : 0.28),
              blurRadius: hovered ? 20 : 12,
              spreadRadius: -4,
            ),
          ],
        );
      case HelmButtonKind.ghost:
        return BoxDecoration(
          color: hovered ? AppColors.glassHover : AppColors.glassStrong,
          borderRadius: Radii.pill,
          border: Border.all(color: AppColors.strokeStrong),
        );
    }
  }
}

/// Square glassy icon button used for row actions (reveal, open, …).
class IconSquareButton extends StatelessWidget {
  const IconSquareButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
    this.size = 30,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final button = Hoverable(
      onTap: onPressed,
      builder: (context, hovered, pressed) => AnimatedContainer(
        duration: Motion.fast,
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: hovered ? AppColors.glassHover : AppColors.glass,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(
              color: hovered ? AppColors.strokeStrong : AppColors.stroke),
        ),
        child: Icon(icon,
            size: 15, color: color ?? AppColors.textSecondary),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}
