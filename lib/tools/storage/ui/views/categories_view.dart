import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/models/storage_category.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/byte_format.dart';
import '../../../../core/widgets/buttons.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/glass_panel.dart';
import '../../../../core/widgets/hoverable.dart';
import '../../state/storage_controller.dart';
import '../category_ui.dart';
import '../widgets/page_chrome.dart';
import '../widgets/scanning_panel.dart';
import 'explorer_view.dart';

class CategoriesView extends StatelessWidget {
  const CategoriesView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<StorageController>();

    if (c.isScanning) {
      return ScanningPanel(
        progress: c.progress,
        title: 'Analyzing your disk',
        onCancel: c.cancelScan,
      );
    }

    if (!c.hasResults) {
      return EmptyState(
        icon: Icons.donut_large_rounded,
        title: 'See what\'s using your space',
        message:
            'Helm scans every category — apps, media, caches, developer junk and more — and shows you exactly where your storage went.',
        action: HelmButton(
          label: 'Analyze Disk',
          icon: Icons.radar_rounded,
          onPressed: c.startScan,
        ),
      );
    }

    final selected = c.selected;
    if (selected != null && selected.root != null) {
      return ExplorerView(
        key: ValueKey(selected.kind),
        root: selected.root!,
        title: categoryLabel(selected.kind),
        controller: c,
        accent: categoryColor(selected.kind),
        onClose: () => c.select_(null),
      );
    }

    final cats = c.categories;
    final maxSize = cats.isEmpty
        ? 1
        : cats.map((e) => e.sizeBytes).reduce((a, b) => a > b ? a : b);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          Insets.xxl, Insets.xl, Insets.xxl, Insets.xxl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Categories',
                subtitle:
                    '${formatBytes(c.volume.occupiedBytes)} used across ${cats.length} categories',
                actions: [
                  HelmButton(
                    label: 'Re-analyze',
                    kind: HelmButtonKind.ghost,
                    icon: Icons.refresh_rounded,
                    onPressed: c.startScan,
                  ),
                ],
              ),
              const SizedBox(height: Insets.xl),
              for (final cat in cats) ...[
                _CategoryRow(
                  category: cat,
                  fraction: cat.sizeBytes / maxSize,
                  onTap: cat.root != null && cat.root!.children.isNotEmpty
                      ? () => c.select_(cat)
                      : null,
                ),
                const SizedBox(height: Insets.md),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.fraction,
    required this.onTap,
  });

  final StorageCategory category;
  final double fraction;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = categoryColor(category.kind);
    return Hoverable(
      enabled: onTap != null,
      onTap: onTap,
      builder: (context, hovered, _) => GlassPanel(
        color: hovered ? AppColors.glassStrong : AppColors.glass,
        border: hovered ? AppColors.strokeStrong : AppColors.stroke,
        padding: const EdgeInsets.symmetric(
            horizontal: Insets.lg, vertical: Insets.lg),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Icon(categoryIcon(category.kind), color: color, size: 22),
            ),
            const SizedBox(width: Insets.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(categoryLabel(category.kind),
                          style: AppType.bodyStrong),
                      if (category.accessDenied) ...[
                        const SizedBox(width: 6),
                        const Tooltip(
                          message:
                              'Some files were unreadable. Grant Full Disk Access for an exact figure.',
                          child: Icon(Icons.lock_outline_rounded,
                              size: 13, color: AppColors.warning),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: fraction.clamp(0, 1),
                      minHeight: 5,
                      backgroundColor: AppColors.glassStrong,
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    category.kind == CategoryKind.systemData
                        ? 'Everything else macOS accounts for'
                        : '${formatCount(category.itemCount)} items',
                    style: AppType.caption.copyWith(color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Insets.lg),
            Text(formatBytes(category.sizeBytes), style: AppType.title),
            const SizedBox(width: Insets.md),
            if (onTap != null)
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textTertiary)
            else
              const SizedBox(width: 24),
          ],
        ),
      ),
    );
  }
}
