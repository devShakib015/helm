import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/shell.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/byte_format.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/confirm.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/helm_checkbox.dart';
import '../../core/widgets/hoverable.dart';
import '../../core/widgets/page_header.dart';
import 'models/trace_group.dart';
import 'state/privacy_controller.dart';

/// Root view of the Privacy tool. Lists the traces macOS leaves behind grouped
/// into clearable cards, with a floating footer to Trash the selection and
/// header shortcuts to flush the DNS cache and open Privacy settings.
class PrivacyTool extends StatefulWidget {
  const PrivacyTool({super.key});

  /// Tool accent — purple.
  static const Color accent = Color(0xFF7B61FF);

  @override
  State<PrivacyTool> createState() => _PrivacyToolState();
}

class _PrivacyToolState extends State<PrivacyTool> {
  final Set<String> _expanded = {};
  bool _busy = false;

  Future<void> _clearTraces(PrivacyController c) async {
    final ok = await showHelmConfirm(
      context,
      title: 'Clear ${formatBytes(c.selectedBytes)} of traces?',
      message:
          '${c.selectedCount} items will be moved to the Trash. You can restore them from the Trash if you need them back.',
      confirmLabel: 'Clear Traces',
      danger: true,
      icon: Icons.privacy_tip_rounded,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final res = await c.clearSelected();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(res.failed == 0
          ? 'Cleared ${res.trashed} traces.'
          : 'Cleared ${res.trashed} · ${res.failed} skipped (need Full Disk Access).'),
    ));
  }

  Future<void> _flushDns() async {
    final ok = await showHelmConfirm(
      context,
      title: 'Flush DNS cache?',
      message:
          'This clears macOS\'s cached DNS lookups so name resolution starts fresh. Helm will ask for your password.',
      confirmLabel: 'Flush DNS',
      icon: Icons.dns_rounded,
    );
    if (!ok || !mounted) return;
    final success = await Shell.runAsAdmin(
      'dscacheutil -flushcache; killall -HUP mDNSResponder',
      prompt: 'Helm needs permission to flush the DNS cache',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(success ? 'DNS cache flushed.' : 'Could not flush the DNS cache.'),
    ));
  }

  Future<void> _openPrivacySettings() async {
    await Shell.run('open', [
      'x-apple.systempreferences:com.apple.preference.security?Privacy',
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PrivacyController>();

    if (c.scanning) {
      return const Center(child: CircularProgressIndicator(color: PrivacyTool.accent));
    }

    if (!c.hasResults) {
      return EmptyState(
        icon: Icons.verified_user_rounded,
        accent: PrivacyTool.accent,
        title: 'No traces found',
        message:
            'Helm couldn\'t find any privacy traces to clear right now. You\'re tidy.',
        action: HelmButton(
          label: 'Rescan',
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
                title: 'Privacy',
                subtitle:
                    '${formatBytes(c.totalBytes)} of traces across ${c.groups.length} sources',
                actions: [
                  HelmButton(
                    label: 'Flush DNS',
                    kind: HelmButtonKind.ghost,
                    icon: Icons.dns_rounded,
                    onPressed: _flushDns,
                  ),
                  HelmButton(
                    label: 'Privacy Settings',
                    kind: HelmButtonKind.ghost,
                    icon: Icons.shield_outlined,
                    onPressed: _openPrivacySettings,
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
                      expanded: _expanded.contains(group.title),
                      controller: c,
                      onToggleExpand: () => setState(() {
                        if (!_expanded.remove(group.title)) {
                          _expanded.add(group.title);
                        }
                      }),
                    );
                  },
                ),
              ),
              const SizedBox(height: Insets.md),
              _Footer(
                count: c.selectedCount,
                bytes: c.selectedBytes,
                busy: _busy,
                onClear: c.clearSelection,
                onAction:
                    c.selectedCount == 0 || _busy ? null : () => _clearTraces(c),
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

  final TraceGroup group;
  final bool expanded;
  final PrivacyController controller;
  final VoidCallback onToggleExpand;

  @override
  Widget build(BuildContext context) {
    final color = group.color;
    final items = [...group.items]
      ..sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));

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
                  child: Icon(group.icon, color: color, size: 20),
                ),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              group.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.bodyStrong,
                            ),
                          ),
                          if (group.caution) ...[
                            const SizedBox(width: Insets.sm),
                            const _SensitivePill(),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        group.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.caption
                            .copyWith(color: AppColors.textTertiary),
                      ),
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
            ...items.map((item) => _ItemRow(
                  item: item,
                  color: color,
                  onToggle: () => controller.toggleItem(item),
                )),
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

  final TraceItem item;
  final Color color;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onToggle,
      builder: (context, hovered, _) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: Insets.sm, vertical: 7),
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
                  Text(item.path,
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

class _SensitivePill extends StatelessWidget {
  const _SensitivePill();

  @override
  Widget build(BuildContext context) {
    const color = AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: Radii.pill,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        'Sensitive',
        style: AppType.micro.copyWith(color: color, letterSpacing: 0.3),
      ),
    );
  }
}

/// Floating action footer: shows the running selection total and the danger
/// "Clear Traces" button.
class _Footer extends StatelessWidget {
  const _Footer({
    required this.count,
    required this.bytes,
    required this.busy,
    required this.onClear,
    required this.onAction,
  });

  final int count;
  final int bytes;
  final bool busy;
  final VoidCallback onClear;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final hasSelection = count > 0;
    return GlassPanel(
      blur: true,
      color: AppColors.glassStrong,
      border: AppColors.strokeStrong,
      padding: const EdgeInsets.symmetric(
          horizontal: Insets.lg, vertical: Insets.md),
      child: Row(
        children: [
          Icon(
            hasSelection
                ? Icons.delete_sweep_rounded
                : Icons.privacy_tip_outlined,
            size: 18,
            color: hasSelection ? PrivacyTool.accent : AppColors.textTertiary,
          ),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Text(
              hasSelection
                  ? '$count selected · ${formatBytes(bytes)} to clear'
                  : 'Select traces to clear',
              style: AppType.bodyStrong.copyWith(
                color: hasSelection
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
          ),
          if (hasSelection) ...[
            HelmButton(
              label: 'Clear',
              kind: HelmButtonKind.ghost,
              onPressed: onClear,
            ),
            const SizedBox(width: Insets.md),
          ],
          HelmButton(
            label: 'Clear Traces',
            icon: Icons.delete_outline_rounded,
            kind: HelmButtonKind.danger,
            busy: busy,
            onPressed: onAction,
          ),
        ],
      ),
    );
  }
}
