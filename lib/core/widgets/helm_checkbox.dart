import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'hoverable.dart';

/// A compact custom checkbox. `value == null` renders the indeterminate dash —
/// used for group rows where only some children are selected.
class HelmCheckbox extends StatelessWidget {
  const HelmCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.accent = AppColors.accent,
    this.size = 18,
  });

  final bool? value;
  final ValueChanged<bool>? onChanged;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    final checked = value ?? false;
    final indeterminate = value == null;
    final active = checked || indeterminate;
    return Hoverable(
      enabled: onChanged != null,
      onTap: () => onChanged?.call(!(value ?? false)),
      builder: (context, hovered, pressed) => AnimatedContainer(
        duration: Motion.fast,
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: active
              ? LinearGradient(colors: [accent, accent.withValues(alpha: 0.82)])
              : null,
          color: active ? null : AppColors.glassStrong,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active
                ? accent
                : (hovered ? AppColors.strokeStrong : AppColors.stroke),
            width: 1.4,
          ),
        ),
        child: indeterminate
            ? const Icon(Icons.remove_rounded, size: 13, color: Colors.white)
            : (checked
                ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
                : null),
      ),
    );
  }
}
