import 'dart:io';

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

  late final TextEditingController _search;

  @override
  void initState() {
    super.initState();
    // Seed from the controller so a query typed before navigating away isn't
    // an invisible filter behind an empty-looking search box.
    _search =
        TextEditingController(text: context.read<ClipboardController>().query);
  }

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
    final status = await c.copy(item);
    if (!mounted) return;
    final message = switch (status) {
      CopyStatus.ok => 'Copied to clipboard',
      CopyStatus.partial =>
        'Some of those files no longer exist — copied the ones that remain',
      CopyStatus.failed => switch (item.kind) {
          ClipKind.image =>
            'This image was too large to keep — only its preview is stored',
          ClipKind.file => 'Those files no longer exist',
          ClipKind.text => 'Couldn\'t copy to clipboard',
        },
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
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

  String get _caption {
    final age =
        formatAge(DateTime.fromMillisecondsSinceEpoch(item.createdMs));
    switch (item.kind) {
      case ClipKind.text:
        final truncNote = item.truncated ? ' · trimmed' : '';
        return '${formatCount(item.chars)} chars$truncNote · $age';
      case ClipKind.image:
        return 'PNG · ${formatBytes(item.sizeBytes)}'
            '${item.imageRestorable ? '' : ' · preview only'} · $age';
      case ClipKind.file:
        final n = item.files.length;
        final size =
            item.sizeBytes > 0 ? ' · ${formatBytes(item.sizeBytes)}' : '';
        return '$n ${n == 1 ? 'item' : 'items'}$size · $age';
    }
  }

  /// Leading visual: a real thumbnail for images (from disk, or from memory in
  /// clear-on-quit mode), a doc/folder glyph for file copies, the classic
  /// paste icon for text.
  Widget _leading() {
    if (item.kind == ClipKind.image && item.thumbBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(Radii.sm),
        child: Image.memory(
          item.thumbBytes!,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _iconBox(Icons.image_rounded),
        ),
      );
    }
    if (item.kind == ClipKind.image && item.thumbPath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(Radii.sm),
        child: Image.file(
          File(item.thumbPath!),
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _iconBox(Icons.image_rounded),
        ),
      );
    }
    return _iconBox(switch (item.kind) {
      ClipKind.image => Icons.image_rounded,
      ClipKind.file =>
        item.files.length == 1 ? Icons.description_rounded : Icons.folder_copy_rounded,
      ClipKind.text => item.pinned
          ? Icons.push_pin_rounded
          : Icons.content_paste_rounded,
    });
  }

  Widget _iconBox(IconData icon) => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: (item.pinned ? accent : AppColors.textTertiary)
              .withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: Icon(
          icon,
          size: 18,
          color: item.pinned ? accent : AppColors.textSecondary,
        ),
      );

  @override
  Widget build(BuildContext context) {
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
            _leading(),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.body,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _caption,
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
