import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/hoverable.dart';
import '../../core/widgets/page_header.dart';
import 'quick_actions_controller.dart';

/// Quick Actions: power-user toggles and one-shot maintenance commands.
class QuickActionsTool extends StatelessWidget {
  const QuickActionsTool({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<QuickActionsController>();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          Insets.xxl, Insets.xl, Insets.xxl, Insets.xxl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Quick Actions',
                subtitle: 'Tweaks & maintenance',
                actions: [
                  Hoverable(
                    onTap: c.refresh,
                    builder: (context, hovered, _) => Icon(
                      Icons.refresh_rounded,
                      size: 20,
                      color: hovered
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Insets.xl),
              const _SectionLabel('TOGGLES'),
              const SizedBox(height: Insets.md),
              _ToggleGrid(c: c),
              const SizedBox(height: Insets.xl),
              const _SectionLabel('MAINTENANCE'),
              const SizedBox(height: Insets.md),
              _ActionGrid(c: c),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text, style: AppType.micro);
}

class _ToggleGrid extends StatelessWidget {
  const _ToggleGrid({required this.c});
  final QuickActionsController c;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      _ToggleCard(
        icon: Icons.visibility_rounded,
        accent: const Color(0xFF5AC8FA),
        title: 'Show hidden files',
        description: 'Reveal dotfiles in Finder',
        value: c.hiddenFiles,
        onChanged: c.setHiddenFiles,
      ),
      _ToggleCard(
        icon: Icons.desktop_mac_rounded,
        accent: const Color(0xFFA78BFA),
        title: 'Desktop icons',
        description: 'Show items on the Desktop',
        value: c.desktopIcons,
        onChanged: c.setDesktopIcons,
      ),
      _ToggleCard(
        icon: Icons.dock_rounded,
        accent: const Color(0xFF34D399),
        title: 'Auto-hide Dock',
        description: 'Hide the Dock until hovered',
        value: c.dockAutohide,
        onChanged: c.setDockAutohide,
      ),
      _ToggleCard(
        icon: Icons.dark_mode_rounded,
        accent: const Color(0xFFFBBF24),
        title: 'Dark mode',
        description: 'System appearance',
        value: c.darkMode,
        onChanged: c.setDarkMode,
      ),
    ];
    return _Grid(minTileWidth: 320, tiles: tiles);
  }
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({required this.c});
  final QuickActionsController c;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      _ActionCard(
        icon: Icons.refresh_rounded,
        accent: const Color(0xFF5AC8FA),
        title: 'Restart Finder',
        run: c.restartFinder,
        done: 'Finder restarted',
      ),
      _ActionCard(
        icon: Icons.dock_rounded,
        accent: const Color(0xFF34D399),
        title: 'Restart Dock',
        run: c.restartDock,
        done: 'Dock restarted',
      ),
      _ActionCard(
        icon: Icons.menu_rounded,
        accent: const Color(0xFFA78BFA),
        title: 'Restart Menu Bar',
        run: c.restartMenuBar,
        done: 'Menu bar restarted',
      ),
      _ActionCard(
        icon: Icons.bedtime_rounded,
        accent: const Color(0xFF818CF8),
        title: 'Sleep Display',
        run: c.sleepDisplay,
        done: 'Display sleeping',
      ),
      _ActionCard(
        icon: Icons.delete_sweep_rounded,
        accent: AppColors.danger,
        title: 'Empty Trash',
        confirm: (
          title: 'Empty Trash?',
          message:
              'This permanently deletes everything in your Trash. This can’t '
              'be undone.',
          confirmLabel: 'Empty Trash',
        ),
        run: c.emptyTrash,
        done: 'Trash emptied',
      ),
    ];
    return _Grid(minTileWidth: 220, tiles: tiles);
  }
}

/// Responsive equal-width grid built on Wrap (safe inside a scroll view).
class _Grid extends StatelessWidget {
  const _Grid({required this.minTileWidth, required this.tiles});
  final double minTileWidth;
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = Insets.md;
        final cols =
            (constraints.maxWidth / (minTileWidth + gap)).floor().clamp(1, 4);
        final tileWidth = (constraints.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final t in tiles) SizedBox(width: tileWidth, child: t),
          ],
        );
      },
    );
  }
}

class _ToggleCard extends StatelessWidget {
  const _ToggleCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.symmetric(
          horizontal: Insets.lg, vertical: Insets.md),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: Icon(icon, size: 18, color: accent),
          ),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: AppType.body),
                const SizedBox(height: 2),
                Text(description,
                    style:
                        AppType.caption.copyWith(color: AppColors.textTertiary)),
              ],
            ),
          ),
          const SizedBox(width: Insets.sm),
          Switch(
            value: value,
            onChanged: onChanged,
            // ignore: deprecated_member_use
            activeColor: accent,
            activeTrackColor: accent.withValues(alpha: 0.45),
            inactiveThumbColor: AppColors.textSecondary,
            inactiveTrackColor: AppColors.glassStrong,
            trackOutlineColor:
                WidgetStateProperty.all(AppColors.stroke.withValues(alpha: 0.6)),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

typedef _Confirm = ({String title, String message, String confirmLabel});

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.run,
    required this.done,
    this.confirm,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final Future<bool> Function() run;
  final String done;
  final _Confirm? confirm;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: () => _tap(context),
      builder: (context, hovered, _) => AnimatedContainer(
        duration: Motion.fast,
        padding: const EdgeInsets.symmetric(
            horizontal: Insets.lg, vertical: Insets.lg),
        decoration: BoxDecoration(
          color: hovered ? AppColors.glassHover : AppColors.glass,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(
            color: hovered
                ? accent.withValues(alpha: 0.5)
                : AppColors.stroke,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: Icon(icon, size: 18, color: accent),
            ),
            const SizedBox(width: Insets.md),
            Expanded(child: Text(title, style: AppType.body)),
            Icon(Icons.chevron_right_rounded,
                size: 18,
                color:
                    hovered ? AppColors.textSecondary : AppColors.textTertiary),
          ],
        ),
      ),
    );
  }

  Future<void> _tap(BuildContext context) async {
    if (confirm != null) {
      final ok = await _showConfirm(context, confirm!, accent);
      if (ok != true) return;
    }
    final success = await run();
    if (context.mounted) {
      _toast(context, success ? done : 'Couldn’t complete “$title”');
    }
  }
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message, style: AppType.body),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.glassStrong,
        duration: const Duration(milliseconds: 1600),
      ),
    );
}

Future<bool?> _showConfirm(
    BuildContext context, _Confirm c, Color accent) {
  return showDialog<bool>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      child: GlassPanel(
        blur: true,
        color: const Color(0xF21A1F2B),
        padding: const EdgeInsets.all(Insets.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.title, style: AppType.headline),
              const SizedBox(height: Insets.sm),
              Text(c.message, style: AppType.secondary),
              const SizedBox(height: Insets.xl),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Hoverable(
                    onTap: () => Navigator.of(context).pop(false),
                    builder: (context, hovered, _) => Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Insets.lg, vertical: Insets.sm),
                      child: Text('Cancel',
                          style: AppType.bodyStrong.copyWith(
                              color: hovered
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary)),
                    ),
                  ),
                  const SizedBox(width: Insets.sm),
                  Hoverable(
                    onTap: () => Navigator.of(context).pop(true),
                    builder: (context, hovered, _) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Insets.lg, vertical: Insets.sm),
                      decoration: BoxDecoration(
                        color: AppColors.danger
                            .withValues(alpha: hovered ? 0.3 : 0.2),
                        borderRadius: Radii.pill,
                        border: Border.all(
                            color: AppColors.danger.withValues(alpha: 0.55)),
                      ),
                      child: Text(c.confirmLabel,
                          style: AppType.bodyStrong
                              .copyWith(color: AppColors.danger)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
