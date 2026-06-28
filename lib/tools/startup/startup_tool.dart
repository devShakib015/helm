import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/confirm.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/glass_panel.dart';
import 'models/startup_item.dart';
import 'state/startup_controller.dart';

/// Accent for the Startup tool — warm amber, matching the "launches at startup"
/// theme.
const Color _kStartupAccent = Color(0xFFFBBF24);

/// Lists everything macOS launches automatically (login items, user
/// LaunchAgents, and the read-only system agents/daemons) and lets the user
/// remove the entries Helm can safely modify.
class StartupTool extends StatefulWidget {
  const StartupTool({super.key});

  @override
  State<StartupTool> createState() => _StartupToolState();
}

class _StartupToolState extends State<StartupTool> {
  StartupItem? _removing;

  Future<void> _remove(StartupController c, StartupItem item) async {
    final isLogin = item.kind == StartupKind.loginItem;
    final ok = await showHelmConfirm(
      context,
      title: 'Remove "${item.name}" from startup?',
      message: isLogin
          ? 'This deletes the login item so it no longer launches when you sign in. You can add it back later from the app itself.'
          : 'Helm will unload this agent and move its configuration file to the Trash, so it won\'t run at your next login. You can restore it from the Trash if needed.',
      confirmLabel: 'Remove',
      danger: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!ok || !mounted) return;

    setState(() => _removing = item);
    final success = await c.remove(item);
    if (!mounted) return;
    setState(() => _removing = null);

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(success
          ? 'Removed "${item.name}" from startup.'
          : 'Couldn\'t remove "${item.name}". It may need administrator access.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<StartupController>();

    if (c.loading) {
      return const Center(
        child: CircularProgressIndicator(color: _kStartupAccent),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          Insets.xxl, Insets.xl, Insets.xxl, Insets.xxl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(c),
              const SizedBox(height: Insets.xl),
              if (c.totalCount == 0)
                const Padding(
                  padding: EdgeInsets.only(top: Insets.xxl),
                  child: EmptyState(
                    icon: Icons.rocket_launch_rounded,
                    accent: _kStartupAccent,
                    title: 'Nothing runs at startup',
                    message:
                        'Helm found no login items, agents or daemons configured to launch automatically. Your sign-in is nice and lean.',
                  ),
                )
              else ...[
                if (c.loginItems.isNotEmpty) ...[
                  _Section(
                    label: 'Login Items',
                    items: c.loginItems,
                    removing: _removing,
                    onRemove: (item) => _remove(c, item),
                  ),
                  const SizedBox(height: Insets.lg),
                ],
                if (c.userAgents.isNotEmpty) ...[
                  _Section(
                    label: 'User Agents',
                    items: c.userAgents,
                    removing: _removing,
                    onRemove: (item) => _remove(c, item),
                  ),
                  const SizedBox(height: Insets.lg),
                ],
                if (c.systemItems.isNotEmpty)
                  _Section(
                    label: 'System (read-only)',
                    items: c.systemItems,
                    removing: _removing,
                    onRemove: (item) => _remove(c, item),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(StartupController c) {
    final count = c.totalCount;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Startup', style: AppType.display),
              const SizedBox(height: 2),
              Text(
                '$count ${count == 1 ? 'item runs' : 'items run'} at startup',
                style: AppType.secondary,
              ),
            ],
          ),
        ),
        const SizedBox(width: Insets.md),
        HelmButton(
          label: 'Refresh',
          kind: HelmButtonKind.ghost,
          icon: Icons.refresh_rounded,
          onPressed: c.refresh,
        ),
      ],
    );
  }
}

/// One grouped section (Login Items / User Agents / System) rendered as a
/// labelled GlassPanel of rows.
class _Section extends StatelessWidget {
  const _Section({
    required this.label,
    required this.items,
    required this.removing,
    required this.onRemove,
  });

  final String label;
  final List<StartupItem> items;
  final StartupItem? removing;
  final ValueChanged<StartupItem> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
              left: Insets.xs, bottom: Insets.sm),
          child: Text(label.toUpperCase(), style: AppType.micro),
        ),
        GlassPanel(
          padding: const EdgeInsets.all(Insets.sm),
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0)
                  const Divider(height: 1, color: AppColors.stroke),
                _Row(
                  item: items[i],
                  busy: identical(removing, items[i]),
                  onRemove: () => onRemove(items[i]),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A single startup entry: glyph, name + caption, and a trailing Remove button
/// (modifiable rows) or a lock icon (read-only rows).
class _Row extends StatelessWidget {
  const _Row({
    required this.item,
    required this.busy,
    required this.onRemove,
  });

  final StartupItem item;
  final bool busy;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final caption = _caption(item);

    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: Insets.sm, vertical: Insets.sm),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _kStartupAccent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Icon(_glyph(item.kind),
                color: _kStartupAccent, size: 20),
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
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.bodyStrong,
                      ),
                    ),
                    if (!item.enabled) ...[
                      const SizedBox(width: Insets.sm),
                      const _DisabledBadge(),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      AppType.caption.copyWith(color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(width: Insets.md),
          if (item.canModify)
            busy
                ? const SizedBox(
                    width: 30,
                    height: 30,
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.danger),
                    ),
                  )
                : IconSquareButton(
                    icon: Icons.delete_outline_rounded,
                    tooltip: 'Remove from startup',
                    color: AppColors.danger,
                    onPressed: onRemove,
                  )
          else
            const Tooltip(
              message: 'Needs administrator access',
              child: Icon(Icons.lock_outline_rounded,
                  size: 17, color: AppColors.textTertiary),
            ),
        ],
      ),
    );
  }

  String _caption(StartupItem item) {
    final type = switch (item.kind) {
      StartupKind.loginItem => 'Login item',
      StartupKind.userAgent => 'User agent',
      StartupKind.systemAgent => 'System agent',
      StartupKind.systemDaemon => 'System daemon',
    };
    if (item.path.isEmpty) return type;
    return '$type · ${item.path}';
  }

  IconData _glyph(StartupKind kind) => switch (kind) {
        StartupKind.loginItem => Icons.apps_rounded,
        StartupKind.userAgent => Icons.account_circle_outlined,
        StartupKind.systemAgent => Icons.settings_suggest_outlined,
        StartupKind.systemDaemon => Icons.dns_outlined,
      };
}

/// Small pill marking an agent whose `Disabled` key is set.
class _DisabledBadge extends StatelessWidget {
  const _DisabledBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.textTertiary.withValues(alpha: 0.16),
        borderRadius: Radii.pill,
        border: Border.all(
            color: AppColors.textTertiary.withValues(alpha: 0.3)),
      ),
      child: Text(
        'Disabled',
        style: AppType.micro.copyWith(
            color: AppColors.textSecondary, letterSpacing: 0.3),
      ),
    );
  }
}
