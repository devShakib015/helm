import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/models/duplicate_set.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/byte_format.dart';
import '../../../../core/widgets/buttons.dart';
import '../../../../core/widgets/confirm.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/glass_panel.dart';
import '../../state/duplicates_controller.dart';
import '../../state/scan_state.dart';
import '../../state/storage_controller.dart';
import '../category_ui.dart';
import '../widgets/page_chrome.dart';
import '../widgets/scanning_panel.dart';
import '../widgets/selectable_file_row.dart';
import '../widgets/selection_bar.dart';

class DuplicatesView extends StatefulWidget {
  const DuplicatesView({super.key});

  @override
  State<DuplicatesView> createState() => _DuplicatesViewState();
}

class _DuplicatesViewState extends State<DuplicatesView> {
  bool _busy = false;
  static const _accent = Color(0xFFC084FC);

  Future<void> _delete(DuplicatesController c) async {
    final ok = await showHelmConfirm(
      context,
      title: 'Remove ${c.selectedCount} duplicate copies?',
      message:
          'That frees ${formatBytes(c.selectedBytes)}. Helm always keeps at least one copy of every file, and removed copies go to the Trash.',
      confirmLabel: 'Move to Trash',
      danger: true,
      icon: Icons.content_copy_rounded,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final res = await c.deleteSelected();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Moved ${res.removedCount} duplicate copies to Trash.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<DuplicatesController>();

    if (c.isScanning) {
      return ScanningPanel(
        progress: c.progress,
        title: 'Comparing files',
        accent: _accent,
        onCancel: c.cancel,
      );
    }

    if (c.state == ScanState.idle) {
      return EmptyState(
        icon: Icons.content_copy_rounded,
        accent: _accent,
        title: 'Find duplicate files',
        message:
            'Helm compares files byte-for-byte to find true duplicates, then helps you keep one and reclaim the rest.',
        action: HelmButton(
          label: 'Find Duplicates',
          icon: Icons.radar_rounded,
          onPressed: c.scan,
        ),
      );
    }

    if (!c.hasResults) {
      return EmptyState(
        icon: Icons.verified_rounded,
        accent: AppColors.success,
        title: 'No duplicates found',
        message: 'Every file in your home folder is one of a kind.',
        action: HelmButton(
          label: 'Scan Again',
          kind: HelmButtonKind.ghost,
          icon: Icons.refresh_rounded,
          onPressed: c.scan,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Insets.xxl, Insets.xl, Insets.xxl, Insets.xl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Duplicates',
                subtitle:
                    '${c.totalSets} duplicate sets · ${formatBytes(c.totalReclaimable)} reclaimable',
                actions: [
                  HelmButton(
                    label: 'Auto-select',
                    kind: HelmButtonKind.ghost,
                    icon: Icons.auto_awesome_rounded,
                    onPressed: c.autoSelect,
                  ),
                  HelmButton(
                    label: 'Rescan',
                    kind: HelmButtonKind.ghost,
                    icon: Icons.refresh_rounded,
                    onPressed: c.scan,
                  ),
                ],
              ),
              const SizedBox(height: Insets.xl),
              Expanded(
                child: ListView.separated(
                  itemCount: c.sets.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Insets.md),
                  itemBuilder: (context, i) =>
                      _DuplicateCard(set: c.sets[i], controller: c, accent: _accent),
                ),
              ),
              SelectionBar(
                count: c.selectedCount,
                bytes: c.selectedBytes,
                actionLabel: 'Move to Trash',
                busy: _busy,
                onClear: c.clearSelection,
                onAction: _busy ? null : () => _delete(c),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DuplicateCard extends StatelessWidget {
  const _DuplicateCard({
    required this.set,
    required this.controller,
    required this.accent,
  });

  final DuplicateSet set;
  final DuplicatesController controller;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final glyph = fileGlyph(set.files.first.name);
    return GlassPanel(
      padding: const EdgeInsets.all(Insets.sm),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(Insets.sm),
            child: Row(
              children: [
                Icon(glyph.icon, size: 20, color: glyph.color),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: Text(
                    set.files.first.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.bodyStrong,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: Radii.pill,
                  ),
                  child: Text('${set.copies} copies · ${formatBytes(set.sizeBytes)} each',
                      style: AppType.micro
                          .copyWith(color: accent, letterSpacing: 0.2)),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.stroke),
          for (final f in set.files)
            SelectableFileRow(
              entry: f,
              accent: accent,
              subtitle: f.directory,
              selected: controller.isSelected(f.path),
              onToggle: () => controller.toggle(f.path),
              onReveal: () =>
                  context.read<StorageController>().revealInFinder(f.path),
            ),
        ],
      ),
    );
  }
}
