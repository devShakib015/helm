import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/byte_format.dart';
import '../../../../core/widgets/buttons.dart';
import '../../../../core/widgets/glass_panel.dart';

/// Floating bar that slides up when the user has selected items to remove.
class SelectionBar extends StatelessWidget {
  const SelectionBar({
    super.key,
    required this.count,
    required this.bytes,
    required this.actionLabel,
    required this.onAction,
    required this.onClear,
    this.busy = false,
  });

  final int count;
  final int bytes;
  final String actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onClear;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final visible = count > 0;
    return AnimatedSlide(
      duration: Motion.medium,
      curve: Motion.emphasized,
      offset: visible ? Offset.zero : const Offset(0, 1.4),
      child: AnimatedOpacity(
        duration: Motion.medium,
        opacity: visible ? 1 : 0,
        child: Padding(
          padding: const EdgeInsets.only(top: Insets.md),
          child: GlassPanel(
            color: const Color(0xF21A2030),
            border: AppColors.strokeStrong,
            padding: const EdgeInsets.symmetric(
                horizontal: Insets.lg, vertical: Insets.md),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.dangerSoft,
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: const Icon(Icons.delete_outline_rounded,
                      size: 18, color: AppColors.danger),
                ),
                const SizedBox(width: Insets.md),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$count selected', style: AppType.bodyStrong),
                    Text('${formatBytes(bytes)} to free up',
                        style: AppType.caption),
                  ],
                ),
                const Spacer(),
                if (onClear != null)
                  Padding(
                    padding: const EdgeInsets.only(right: Insets.md),
                    child: HelmButton(
                      label: 'Clear',
                      kind: HelmButtonKind.ghost,
                      onPressed: busy ? null : onClear,
                    ),
                  ),
                HelmButton(
                  label: actionLabel,
                  kind: HelmButtonKind.danger,
                  icon: Icons.delete_rounded,
                  busy: busy,
                  onPressed: onAction,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
