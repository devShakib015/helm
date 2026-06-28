import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/models/cleanable_group.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/byte_format.dart';
import '../../../../core/widgets/buttons.dart';
import '../../../../core/widgets/confirm.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/glass_panel.dart';
import '../../../../core/widgets/helm_checkbox.dart';
import '../../../../core/widgets/hoverable.dart';
import '../../state/cleaner_controller.dart';
import '../../state/scan_state.dart';
import '../category_ui.dart';
import '../widgets/page_chrome.dart';
import '../widgets/scanning_panel.dart';
import '../widgets/selection_bar.dart';

class CleanerView extends StatefulWidget {
  const CleanerView({super.key});

  @override
  State<CleanerView> createState() => _CleanerViewState();
}

class _CleanerViewState extends State<CleanerView> {
  final Set<CleanupKind> _expanded = {};
  bool _busy = false;

  Future<void> _clean(CleanerController c) async {
    final ok = await showHelmConfirm(
      context,
      title: 'Clean up ${formatBytes(c.selectedBytes)}?',
      message:
          '${c.selectedCount} items will be moved to the Trash (the Trash group is emptied permanently). You can restore anything else from the Trash if needed.',
      confirmLabel: 'Clean Up',
      danger: true,
      icon: Icons.cleaning_services_rounded,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final res = await c.cleanSelected();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(res.failed.isEmpty
          ? 'Cleaned up ${res.removedCount} items.'
          : 'Removed ${res.removedCount} items · ${res.failed.length} skipped (need Full Disk Access).'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<CleanerController>();

    if (c.isScanning) {
      return ScanningPanel(
        progress: c.progress,
        title: 'Hunting for junk',
        accent: AppColors.warning,
        onCancel: c.cancel,
      );
    }

    if (c.state == ScanState.idle) {
      return EmptyState(
        icon: Icons.cleaning_services_rounded,
        accent: AppColors.warning,
        title: 'Reclaim space from junk',
        message:
            'Find and clear caches, logs, leftover developer files, browser data, old downloads and more — safely, with everything sent to the Trash.',
        action: HelmButton(
          label: 'Scan for Junk',
          icon: Icons.radar_rounded,
          onPressed: c.scan,
        ),
      );
    }

    if (!c.hasResults) {
      return EmptyState(
        icon: Icons.check_circle_rounded,
        accent: AppColors.success,
        title: 'All clean',
        message: 'Helm didn\'t find any reclaimable junk. Nice and tidy.',
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
                title: 'System Junk',
                subtitle:
                    '${formatBytes(c.totalBytes)} reclaimable across ${c.groups.length} categories',
                actions: [
                  HelmButton(
                    label: 'Select Safe',
                    kind: HelmButtonKind.ghost,
                    icon: Icons.verified_rounded,
                    onPressed: c.selectAllSafe,
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
                  itemCount: c.groups.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Insets.md),
                  itemBuilder: (context, i) {
                    final group = c.groups[i];
                    return _GroupCard(
                      group: group,
                      expanded: _expanded.contains(group.kind),
                      controller: c,
                      onToggleExpand: () => setState(() {
                        if (!_expanded.remove(group.kind)) {
                          _expanded.add(group.kind);
                        }
                      }),
                    );
                  },
                ),
              ),
              SelectionBar(
                count: c.selectedCount,
                bytes: c.selectedBytes,
                actionLabel: 'Clean Up',
                busy: _busy,
                onClear: c.clearSelection,
                onAction: _busy ? null : () => _clean(c),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.expanded,
    required this.controller,
    required this.onToggleExpand,
  });

  final CleanableGroup group;
  final bool expanded;
  final CleanerController controller;
  final VoidCallback onToggleExpand;

  @override
  Widget build(BuildContext context) {
    final color = cleanupColor(group.kind);
    final items = [...group.items]
      ..sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    final shown = items.take(60).toList();

    return GlassPanel(
      padding: const EdgeInsets.all(Insets.sm),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(Insets.sm),
            child: Row(
              children: [
                HelmCheckbox(
                  value: group.allSelected
                      ? true
                      : (group.noneSelected ? false : null),
                  accent: color,
                  onChanged: (v) => controller.setGroup(group, v),
                ),
                const SizedBox(width: Insets.md),
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                  child: Icon(cleanupIcon(group.kind), color: color, size: 20),
                ),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(group.title, style: AppType.bodyStrong),
                          const SizedBox(width: Insets.sm),
                          _RiskBadge(risk: group.risk),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(group.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.caption
                              .copyWith(color: AppColors.textTertiary)),
                    ],
                  ),
                ),
                const SizedBox(width: Insets.md),
                Text(formatBytes(group.totalBytes), style: AppType.title),
                const SizedBox(width: Insets.sm),
                Hoverable(
                  onTap: onToggleExpand,
                  builder: (context, hovered, _) => AnimatedRotation(
                    turns: expanded ? 0.25 : 0,
                    duration: Motion.fast,
                    child: Icon(Icons.chevron_right_rounded,
                        color: hovered
                            ? AppColors.textPrimary
                            : AppColors.textTertiary),
                  ),
                ),
              ],
            ),
          ),
          if (expanded) ...[
            const Divider(height: 1, color: AppColors.stroke),
            ...shown.map((item) => _ItemRow(
                  item: item,
                  color: color,
                  onToggle: () => controller.toggleItem(item),
                )),
            if (items.length > shown.length)
              Padding(
                padding: const EdgeInsets.all(Insets.sm),
                child: Text('+ ${items.length - shown.length} more items',
                    style: AppType.caption),
              ),
          ],
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.color,
    required this.onToggle,
  });

  final CleanableItem item;
  final Color color;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onToggle,
      builder: (context, hovered, _) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Insets.sm, vertical: 7),
        decoration: BoxDecoration(
          color: hovered ? AppColors.glass : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: Row(
          children: [
            const SizedBox(width: 2),
            HelmCheckbox(
                value: item.selected, accent: color, onChanged: (_) => onToggle()),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.body),
                  if (item.detail != null)
                    Text(item.detail!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.caption
                            .copyWith(color: AppColors.textTertiary)),
                ],
              ),
            ),
            const SizedBox(width: Insets.md),
            Text(formatBytes(item.sizeBytes), style: AppType.mono),
            const SizedBox(width: Insets.sm),
          ],
        ),
      ),
    );
  }
}

class _RiskBadge extends StatelessWidget {
  const _RiskBadge({required this.risk});
  final CleanupRisk risk;

  @override
  Widget build(BuildContext context) {
    final safe = risk == CleanupRisk.safe;
    final color = safe ? AppColors.success : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: Radii.pill,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        safe ? 'Safe' : 'Review',
        style: AppType.micro.copyWith(color: color, letterSpacing: 0.3),
      ),
    );
  }
}
