import 'package:flutter/material.dart';

import '../../../../core/models/file_entry.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/byte_format.dart';
import '../../../../core/widgets/buttons.dart';
import '../../../../core/widgets/helm_checkbox.dart';
import '../../../../core/widgets/hoverable.dart';
import '../category_ui.dart';

/// A single file row with selection, type glyph, path, size, age, and a
/// reveal-in-Finder action. Shared by the large-files and duplicates views.
class SelectableFileRow extends StatelessWidget {
  const SelectableFileRow({
    super.key,
    required this.entry,
    required this.selected,
    required this.onToggle,
    required this.onReveal,
    this.subtitle,
    this.accent = AppColors.accent,
  });

  final FileEntry entry;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onReveal;
  final String? subtitle;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final glyph = fileGlyph(entry.name);
    return Hoverable(
      onTap: onToggle,
      builder: (context, hovered, pressed) => AnimatedContainer(
        duration: Motion.fast,
        padding: const EdgeInsets.symmetric(
            horizontal: Insets.md, vertical: Insets.sm),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.10)
              : (hovered ? AppColors.glass : Colors.transparent),
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(
            color: selected ? accent.withValues(alpha: 0.35) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            HelmCheckbox(value: selected, onChanged: (_) => onToggle(), accent: accent),
            const SizedBox(width: Insets.md),
            Icon(glyph.icon, size: 20, color: glyph.color),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.body),
                  const SizedBox(height: 2),
                  Text(
                    subtitle ?? entry.directory,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.caption.copyWith(color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Insets.md),
            Text(formatAge(entry.modified), style: AppType.caption),
            const SizedBox(width: Insets.lg),
            SizedBox(
              width: 76,
              child: Text(
                formatBytes(entry.sizeBytes),
                textAlign: TextAlign.right,
                style: AppType.mono,
              ),
            ),
            const SizedBox(width: Insets.md),
            AnimatedOpacity(
              duration: Motion.fast,
              opacity: hovered ? 1 : 0.0,
              child: IconSquareButton(
                icon: Icons.folder_open_rounded,
                tooltip: 'Reveal in Finder',
                onPressed: onReveal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
