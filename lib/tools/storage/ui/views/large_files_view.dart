import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/byte_format.dart';
import '../../../../core/widgets/buttons.dart';
import '../../../../core/widgets/confirm.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/glass_panel.dart';
import '../../state/large_files_controller.dart';
import '../../state/scan_state.dart';
import '../../state/storage_controller.dart';
import '../widgets/page_chrome.dart';
import '../widgets/scanning_panel.dart';
import '../widgets/selectable_file_row.dart';
import '../widgets/selection_bar.dart';

class LargeFilesView extends StatefulWidget {
  const LargeFilesView({super.key});

  @override
  State<LargeFilesView> createState() => _LargeFilesViewState();
}

class _LargeFilesViewState extends State<LargeFilesView> {
  bool _busy = false;

  Future<void> _delete(LargeFilesController c) async {
    final ok = await showHelmConfirm(
      context,
      title: 'Move ${c.selectedCount} files to Trash?',
      message:
          'That frees ${formatBytes(c.selectedBytes)}. The files go to your Trash, so you can restore them if you change your mind.',
      confirmLabel: 'Move to Trash',
      danger: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final res = await c.deleteSelected();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Moved ${res.removedCount} files to Trash.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<LargeFilesController>();

    if (c.isScanning) {
      return ScanningPanel(
        progress: c.progress,
        title: 'Scanning for large files',
        accent: const Color(0xFF38BDF8),
        onCancel: c.cancel,
      );
    }

    if (c.state == ScanState.idle) {
      return EmptyState(
        icon: Icons.inventory_2_rounded,
        accent: const Color(0xFF38BDF8),
        title: 'Track down space hogs',
        message:
            'Find your biggest files — videos, archives, disk images, datasets — and the ones you haven\'t touched in months.',
        action: HelmButton(
          label: 'Find Large Files',
          icon: Icons.radar_rounded,
          onPressed: () => c.scan(),
        ),
      );
    }

    final files = c.files;

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
                title: 'Large & Old',
                subtitle:
                    '${c.totalFound} files ≥ ${formatBytes(c.minBytes)} · showing ${files.length}',
                actions: [
                  HelmButton(
                    label: 'Rescan',
                    kind: HelmButtonKind.ghost,
                    icon: Icons.refresh_rounded,
                    onPressed: () => c.scan(),
                  ),
                ],
              ),
              const SizedBox(height: Insets.lg),
              _Toolbar(controller: c),
              const SizedBox(height: Insets.md),
              Expanded(
                child: files.isEmpty
                    ? Center(
                        child: Text('No files match these filters.',
                            style: AppType.secondary),
                      )
                    : GlassPanel(
                        padding: const EdgeInsets.all(Insets.sm),
                        child: ListView.builder(
                          itemCount: files.length,
                          itemBuilder: (context, i) {
                            final f = files[i];
                            return SelectableFileRow(
                              entry: f,
                              accent: const Color(0xFF38BDF8),
                              selected: c.isSelected(f.path),
                              onToggle: () => c.toggle(f.path),
                              onReveal: () => context
                                  .read<StorageController>()
                                  .revealInFinder(f.path),
                            );
                          },
                        ),
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

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.controller});
  final LargeFilesController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _DropPill<int>(
          icon: Icons.straighten_rounded,
          label: 'Min ${formatBytes(controller.minBytes)}',
          value: controller.minBytes,
          items: const {
            50 * 1000 * 1000: '50 MB',
            100 * 1000 * 1000: '100 MB',
            500 * 1000 * 1000: '500 MB',
            1000 * 1000 * 1000: '1 GB',
          },
          onSelected: (v) => controller.scan(minBytes: v),
        ),
        const SizedBox(width: Insets.md),
        _DropPill<AgeFilter>(
          icon: Icons.schedule_rounded,
          label: controller.ageFilter.label,
          value: controller.ageFilter,
          items: {for (final a in AgeFilter.values) a: a.label},
          onSelected: controller.setAgeFilter,
        ),
        const SizedBox(width: Insets.md),
        _DropPill<FileSort>(
          icon: Icons.sort_rounded,
          label: switch (controller.sort) {
            FileSort.sizeDesc => 'Largest first',
            FileSort.dateAsc => 'Oldest first',
            FileSort.nameAsc => 'Name',
          },
          value: controller.sort,
          items: const {
            FileSort.sizeDesc: 'Largest first',
            FileSort.dateAsc: 'Oldest first',
            FileSort.nameAsc: 'Name',
          },
          onSelected: controller.setSort,
        ),
        const Spacer(),
        HelmButton(
          label: 'Select All',
          kind: HelmButtonKind.ghost,
          onPressed: controller.selectVisible,
        ),
      ],
    );
  }
}

class _DropPill<T> extends StatelessWidget {
  const _DropPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.items,
    required this.onSelected,
  });

  final IconData icon;
  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      onSelected: onSelected,
      initialValue: value,
      color: const Color(0xF21A2030),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        side: const BorderSide(color: AppColors.stroke),
      ),
      position: PopupMenuPosition.under,
      itemBuilder: (context) => [
        for (final entry in items.entries)
          PopupMenuItem<T>(
            value: entry.key,
            height: 36,
            child: Text(entry.value, style: AppType.body),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Insets.md, vertical: Insets.sm),
        decoration: BoxDecoration(
          color: AppColors.glassStrong,
          borderRadius: Radii.pill,
          border: Border.all(color: AppColors.stroke),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(label, style: AppType.caption.copyWith(color: AppColors.textPrimary)),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down_rounded,
                size: 16, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}
