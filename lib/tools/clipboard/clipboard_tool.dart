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
import '../../core/widgets/hoverable.dart';
import '../../core/widgets/page_header.dart';
import 'clipboard_controller.dart';

/// Maccy-style clipboard history: a search field over a scrolling list of past
/// copies. Tap a row to copy it back to the pasteboard; pin favourites so they
/// survive trimming; delete anything you'd rather forget.
class ClipboardTool extends StatefulWidget {
  const ClipboardTool({super.key});

  @override
  State<ClipboardTool> createState() => _ClipboardToolState();
}

class _ClipboardToolState extends State<ClipboardTool> {
  static const Color _accent = Color(0xFF34D8C8);

  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _clearAll(ClipboardController c) async {
    final ok = await showHelmConfirm(
      context,
      title: 'Clear clipboard history?',
      message:
          'This removes every unpinned item from your clipboard history. Pinned items are kept.',
      confirmLabel: 'Clear',
      danger: true,
      icon: Icons.delete_sweep_rounded,
    );
    if (!ok) return;
    c.clearAll();
  }

  Future<void> _copy(ClipboardController c, ClipItem item) async {
    await c.copy(item);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ClipboardController>();

    if (!c.loaded) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Insets.xxl, Insets.xl, Insets.xxl, Insets.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            title: 'Clipboard',
            subtitle: '${c.count} items in history',
            actions: [
              HelmButton(
                label: 'Clear',
                kind: HelmButtonKind.ghost,
                icon: Icons.delete_sweep_rounded,
                onPressed: () => _clearAll(c),
              ),
            ],
          ),
          const SizedBox(height: Insets.xl),
          GlassPanel(
            padding: const EdgeInsets.symmetric(
                horizontal: Insets.lg, vertical: Insets.xs),
            child: Row(
              children: [
                const Icon(Icons.search_rounded,
                    size: 18, color: AppColors.textTertiary),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: TextField(
                    controller: _search,
                    onChanged: c.setQuery,
                    cursorColor: _accent,
                    style: AppType.body,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      hintText: 'Search clipboard…',
                      hintStyle: AppType.body
                          .copyWith(color: AppColors.textTertiary),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Insets.lg),
          Expanded(
            child: c.items.isEmpty
                ? EmptyState(
                    icon: Icons.content_paste_rounded,
                    accent: _accent,
                    title: c.count == 0
                        ? 'Clipboard history is empty'
                        : 'No matches',
                    message: 'Copy something and it shows up here.',
                  )
                : ListView.separated(
                    itemCount: c.items.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: Insets.sm),
                    itemBuilder: (context, i) {
                      final item = c.items[i];
                      return _ClipRow(
                        item: item,
                        accent: _accent,
                        onTap: () => _copy(c, item),
                        onTogglePin: () => c.togglePin(item),
                        onDelete: () => c.delete(item),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ClipRow extends StatelessWidget {
  const _ClipRow({
    required this.item,
    required this.accent,
    required this.onTap,
    required this.onTogglePin,
    required this.onDelete,
  });

  final ClipItem item;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback onTogglePin;
  final VoidCallback onDelete;

  /// Collapses runs of whitespace/newlines into single spaces so multi-line
  /// snippets preview as a clean one-liner.
  String get _preview =>
      item.text.replaceAll(RegExp(r'\s+'), ' ').trim();

  @override
  Widget build(BuildContext context) {
    final caption =
        '${item.chars} chars · ${formatAge(DateTime.fromMillisecondsSinceEpoch(item.createdMs))}';

    return Hoverable(
      onTap: onTap,
      builder: (context, hovered, _) => AnimatedContainer(
        duration: Motion.fast,
        padding: const EdgeInsets.symmetric(
            horizontal: Insets.md, vertical: Insets.md),
        decoration: BoxDecoration(
          color: hovered ? AppColors.glassHover : AppColors.glass,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(
              color: hovered ? AppColors.strokeStrong : AppColors.stroke),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: (item.pinned ? accent : AppColors.textTertiary)
                    .withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: Icon(
                item.pinned
                    ? Icons.push_pin_rounded
                    : Icons.content_paste_rounded,
                size: 16,
                color: item.pinned ? accent : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.body,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    caption,
                    style: AppType.caption
                        .copyWith(color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Insets.md),
            if (hovered) ...[
              IconSquareButton(
                icon: Icons.push_pin_rounded,
                tooltip: item.pinned ? 'Unpin' : 'Pin',
                color: item.pinned ? accent : null,
                onPressed: onTogglePin,
              ),
              const SizedBox(width: Insets.sm),
              IconSquareButton(
                icon: Icons.close_rounded,
                tooltip: 'Delete',
                color: AppColors.danger,
                onPressed: onDelete,
              ),
            ] else if (item.pinned)
              Icon(Icons.push_pin_rounded, size: 15, color: accent),
          ],
        ),
      ),
    );
  }
}
