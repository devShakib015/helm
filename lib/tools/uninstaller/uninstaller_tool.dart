import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
import 'models/installed_app.dart';
import 'state/uninstaller_controller.dart';

/// Accent for the Uninstaller tool — a warm rose, distinct from the global blue.
const Color _kAccent = Color(0xFFFB7185);

/// Master–detail uninstaller: a scrollable list of installed apps on the left,
/// the selected app's bundle plus its scattered leftovers on the right.
class UninstallerTool extends StatelessWidget {
  const UninstallerTool({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<UninstallerController>();

    if (c.loadingApps) {
      return const Center(
        child: CircularProgressIndicator(color: _kAccent),
      );
    }

    return Padding(
      padding:
          const EdgeInsets.fromLTRB(Insets.xxl, Insets.xl, Insets.xxl, Insets.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 340, child: _AppList(controller: c)),
          const SizedBox(width: Insets.xl),
          Expanded(child: _DetailPane(controller: c)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Left column: the list of apps.
// ---------------------------------------------------------------------------

class _AppList extends StatelessWidget {
  const _AppList({required this.controller});
  final UninstallerController controller;

  @override
  Widget build(BuildContext context) {
    final apps = controller.apps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: Insets.xs, bottom: Insets.md),
          child: Row(
            children: [
              Text('Applications', style: AppType.title),
              const SizedBox(width: Insets.sm),
              Text(formatCount(apps.length),
                  style: AppType.caption.copyWith(color: AppColors.textTertiary)),
            ],
          ),
        ),
        Expanded(
          child: apps.isEmpty
              ? EmptyState(
                  icon: Icons.apps_rounded,
                  accent: _kAccent,
                  title: 'No apps found',
                  message:
                      'Helm didn\'t find any applications in /Applications or your user Applications folder.',
                )
              : ListView.separated(
                  itemCount: apps.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Insets.sm),
                  itemBuilder: (context, i) {
                    final app = apps[i];
                    return _AppRow(
                      app: app,
                      selected: controller.selected?.path == app.path,
                      onTap: () => controller.selectApp(app),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({
    required this.app,
    required this.selected,
    required this.onTap,
  });

  final InstalledApp app;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (context, hovered, _) => AnimatedContainer(
        duration: Motion.fast,
        padding: const EdgeInsets.symmetric(
            horizontal: Insets.md, vertical: Insets.sm),
        decoration: BoxDecoration(
          color: selected
              ? _kAccent.withValues(alpha: 0.12)
              : (hovered ? AppColors.glass : Colors.transparent),
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(
            color: selected
                ? _kAccent.withValues(alpha: 0.4)
                : (hovered ? AppColors.stroke : Colors.transparent),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _kAccent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: const Icon(Icons.apps_rounded, color: _kAccent, size: 18),
            ),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Text(
                app.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.bodyStrong,
              ),
            ),
            const SizedBox(width: Insets.sm),
            Text(formatBytes(app.sizeBytes),
                style: AppType.mono.copyWith(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Right column: the selected app's detail and uninstall sheet.
// ---------------------------------------------------------------------------

class _DetailPane extends StatefulWidget {
  const _DetailPane({required this.controller});
  final UninstallerController controller;

  @override
  State<_DetailPane> createState() => _DetailPaneState();
}

class _DetailPaneState extends State<_DetailPane> {
  Future<void> _uninstall(UninstallerController c, InstalledApp app) async {
    final paths = <String>[
      if (c.appSelectedForRemoval) app.path,
      for (final l in c.leftovers)
        if (l.selected) l.path,
    ];
    if (paths.isEmpty) return;

    final ok = await showHelmConfirm(
      context,
      title: 'Uninstall ${app.name}?',
      message:
          '${paths.length} items (${formatBytes(c.selectedBytes)}) will be moved to the Trash. You can restore them from the Trash if you change your mind.',
      confirmLabel: 'Uninstall',
      danger: true,
      icon: Icons.auto_delete_rounded,
    );
    if (!ok || !mounted) return;

    final res = await c.uninstall(paths);
    if (!mounted) return;

    final n = res.trashed.length;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(res.failed.isEmpty
          ? 'Moved $n items to Trash'
          : 'Moved $n items to Trash · ${res.failed.length} skipped'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final app = c.selected;

    if (app == null) {
      return const EmptyState(
        icon: Icons.auto_delete_rounded,
        accent: _kAccent,
        title: 'Select an app to uninstall',
        message:
            'Pick an application on the left to see its size and every support file, cache and preference it leaves behind.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DetailHeader(app: app, controller: c),
        const SizedBox(height: Insets.lg),
        Expanded(
          child: c.loadingLeftovers
              ? const Center(child: CircularProgressIndicator(color: _kAccent))
              : _ItemList(controller: c, app: app),
        ),
        const SizedBox(height: Insets.lg),
        _Footer(
          controller: c,
          busy: c.uninstalling,
          onUninstall: () => _uninstall(c, app),
        ),
      ],
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.app, required this.controller});
  final InstalledApp app;
  final UninstallerController controller;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(Insets.lg),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _kAccent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: const Icon(Icons.apps_rounded, color: _kAccent, size: 26),
          ),
          const SizedBox(width: Insets.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(app.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.title),
                const SizedBox(height: 2),
                Text(
                  app.bundleId.isEmpty ? app.path : app.bundleId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.caption.copyWith(color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(width: Insets.lg),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatBytes(controller.totalBytes),
                  style: AppType.title.copyWith(color: _kAccent)),
              Text('total',
                  style: AppType.micro.copyWith(color: AppColors.textTertiary)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ItemList extends StatelessWidget {
  const _ItemList({required this.controller, required this.app});
  final UninstallerController controller;
  final InstalledApp app;

  @override
  Widget build(BuildContext context) {
    final leftovers = controller.leftovers;
    return GlassPanel(
      padding: const EdgeInsets.all(Insets.sm),
      child: ListView(
        children: [
          // The app bundle itself, always shown first, accent-highlighted.
          _Row(
            checked: controller.appSelectedForRemoval,
            accent: _kAccent,
            name: '${app.name}.app',
            category: 'Application',
            sizeBytes: app.sizeBytes,
            onToggle: () =>
                controller.toggleApp(!controller.appSelectedForRemoval),
            emphasised: true,
          ),
          if (leftovers.isNotEmpty) ...[
            const Divider(height: 1, color: AppColors.stroke),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Insets.sm, Insets.md, Insets.sm, Insets.sm),
              child: Text(
                '${formatCount(leftovers.length)} leftover items · ${formatBytes(controller.leftoversBytes)}',
                style: AppType.micro.copyWith(color: AppColors.textTertiary),
              ),
            ),
            ...leftovers.map((l) => _Row(
                  checked: l.selected,
                  accent: _kAccent,
                  name: l.name,
                  category: l.category,
                  sizeBytes: l.sizeBytes,
                  onToggle: () => controller.toggleLeftover(l),
                )),
          ] else
            Padding(
              padding: const EdgeInsets.all(Insets.lg),
              child: Text(
                'No leftover files found for this app.',
                style: AppType.secondary.copyWith(color: AppColors.textTertiary),
              ),
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.checked,
    required this.accent,
    required this.name,
    required this.category,
    required this.sizeBytes,
    required this.onToggle,
    this.emphasised = false,
  });

  final bool checked;
  final Color accent;
  final String name;
  final String category;
  final int sizeBytes;
  final VoidCallback onToggle;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onToggle,
      builder: (context, hovered, _) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: Insets.sm, vertical: 7),
        decoration: BoxDecoration(
          color: emphasised
              ? accent.withValues(alpha: 0.07)
              : (hovered ? AppColors.glass : Colors.transparent),
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: Row(
          children: [
            const SizedBox(width: 2),
            HelmCheckbox(
                value: checked, accent: accent, onChanged: (_) => onToggle()),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: emphasised ? AppType.bodyStrong : AppType.body,
              ),
            ),
            const SizedBox(width: Insets.md),
            _CategoryChip(label: category, accent: accent),
            const SizedBox(width: Insets.md),
            SizedBox(
              width: 72,
              child: Text(
                formatBytes(sizeBytes),
                textAlign: TextAlign.right,
                style: AppType.mono.copyWith(color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(width: Insets.sm),
          ],
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label, required this.accent});
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: Radii.pill,
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: AppType.micro
            .copyWith(color: accent, letterSpacing: 0.3),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.controller,
    required this.busy,
    required this.onUninstall,
  });

  final UninstallerController controller;
  final bool busy;
  final VoidCallback onUninstall;

  @override
  Widget build(BuildContext context) {
    final app = controller.selected;
    final count = controller.selectedCount;
    final hasSelection = count > 0;
    return GlassPanel(
      padding: const EdgeInsets.symmetric(
          horizontal: Insets.lg, vertical: Insets.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasSelection
                      ? '${formatCount(count)} items selected'
                      : 'Nothing selected',
                  style: AppType.bodyStrong,
                ),
                Text(
                  formatBytes(controller.selectedBytes),
                  style: AppType.caption.copyWith(color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
          HelmButton(
            label: 'Uninstall ${app?.name ?? ''}'.trim(),
            icon: Icons.delete_outline_rounded,
            kind: HelmButtonKind.danger,
            busy: busy,
            onPressed: hasSelection && !busy ? onUninstall : null,
          ),
        ],
      ),
    );
  }
}
