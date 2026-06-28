import 'package:flutter/material.dart';

import '../../../../core/models/scan_node.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/byte_format.dart';
import '../../../../core/widgets/buttons.dart';
import '../../../../core/widgets/confirm.dart';
import '../../../../core/widgets/glass_panel.dart';
import '../../../../core/widgets/hoverable.dart';
import '../../state/storage_controller.dart';
import '../category_ui.dart';
import '../widgets/treemap.dart';

/// Drill-down browser for a scanned tree: a squarified treemap on the left and
/// the current folder's contents on the right. Tapping a folder dives in;
/// breadcrumbs climb back out.
class ExplorerView extends StatefulWidget {
  const ExplorerView({
    super.key,
    required this.root,
    required this.title,
    required this.controller,
    required this.onClose,
    this.accent = AppColors.accent,
  });

  final ScanNode root;
  final String title;
  final StorageController controller;
  final VoidCallback onClose;
  final Color accent;

  @override
  State<ExplorerView> createState() => _ExplorerViewState();
}

class _ExplorerViewState extends State<ExplorerView> {
  late List<ScanNode> _stack = [widget.root];
  bool _busy = false;

  ScanNode get _current => _stack.last;

  void _drill(ScanNode node) {
    if (!node.isDirectory || node.children.isEmpty || node.path.isEmpty) return;
    setState(() => _stack = [..._stack, node]);
  }

  void _popTo(int index) {
    setState(() => _stack = _stack.sublist(0, index + 1));
  }

  Future<void> _delete(ScanNode child) async {
    final ok = await showHelmConfirm(
      context,
      title: 'Move to Trash?',
      message:
          '"${child.name}" (${formatBytes(child.sizeBytes)}) will be moved to the Trash. You can restore it from there.',
      confirmLabel: 'Move to Trash',
      danger: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final res = await widget.controller.trashPaths([child.path]);
    if (!mounted) return;
    if (res.removed.contains(child.path)) {
      for (final ancestor in _stack) {
        ancestor.sizeBytes -= child.sizeBytes;
        ancestor.fileCount -= child.fileCount;
      }
      _current.children.remove(child);
    }
    setState(() => _busy = false);
    if (res.failed.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Some items could not be removed.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Insets.xxl, Insets.xl, Insets.xxl, Insets.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _breadcrumb(),
          const SizedBox(height: Insets.lg),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: GlassPanel(
                    padding: const EdgeInsets.all(Insets.md),
                    child: Treemap(
                      nodes: _current.children,
                      onTap: _drill,
                    ),
                  ),
                ),
                const SizedBox(width: Insets.lg),
                Expanded(
                  flex: 2,
                  child: GlassPanel(
                    padding: const EdgeInsets.all(Insets.sm),
                    child: _contentsList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _breadcrumb() {
    return Row(
      children: [
        IconSquareButton(
          icon: Icons.arrow_back_rounded,
          tooltip: 'Back to categories',
          onPressed: widget.onClose,
          size: 34,
        ),
        const SizedBox(width: Insets.md),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: Row(
              children: [
                for (var i = 0; i < _stack.length; i++) ...[
                  if (i > 0)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.chevron_right_rounded,
                          size: 18, color: AppColors.textTertiary),
                    ),
                  Hoverable(
                    onTap: () => _popTo(i),
                    builder: (context, hovered, _) => Text(
                      i == 0 ? widget.title : _stack[i].name,
                      style: (i == _stack.length - 1
                              ? AppType.bodyStrong
                              : AppType.secondary)
                          .copyWith(
                        color: hovered
                            ? AppColors.textPrimary
                            : (i == _stack.length - 1
                                ? AppColors.textPrimary
                                : AppColors.textSecondary),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: Insets.md),
        Text(formatBytes(_current.sizeBytes), style: AppType.title),
      ],
    );
  }

  Widget _contentsList() {
    final children = _current.children;
    if (children.isEmpty) {
      return Center(
        child: Text('No further detail', style: AppType.caption),
      );
    }
    final maxSize = children.first.sizeBytes.clamp(1, 1 << 62);
    return ListView.builder(
      itemCount: children.length,
      itemBuilder: (context, i) {
        final node = children[i];
        return _NodeRow(
          node: node,
          fraction: node.sizeBytes / maxSize,
          accent: widget.accent,
          busy: _busy,
          onDrill: () => _drill(node),
          onReveal: () => widget.controller.revealInFinder(node.path),
          onDelete: node.path.isEmpty ? null : () => _delete(node),
        );
      },
    );
  }
}

class _NodeRow extends StatelessWidget {
  const _NodeRow({
    required this.node,
    required this.fraction,
    required this.accent,
    required this.busy,
    required this.onDrill,
    required this.onReveal,
    required this.onDelete,
  });

  final ScanNode node;
  final double fraction;
  final Color accent;
  final bool busy;
  final VoidCallback onDrill;
  final VoidCallback onReveal;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final drillable =
        node.isDirectory && node.children.isNotEmpty && node.path.isNotEmpty;
    final glyph = fileGlyph(node.name, isDir: node.isDirectory);
    return Hoverable(
      enabled: drillable,
      onTap: drillable ? onDrill : null,
      cursor: drillable ? SystemMouseCursors.click : SystemMouseCursors.basic,
      builder: (context, hovered, _) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Insets.md, vertical: Insets.sm),
        decoration: BoxDecoration(
          color: hovered ? AppColors.glass : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: Row(
          children: [
            Icon(glyph.icon, size: 19, color: glyph.color),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(node.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.body),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: fraction.toDouble().clamp(0, 1),
                      minHeight: 3,
                      backgroundColor: AppColors.glassStrong,
                      valueColor: AlwaysStoppedAnimation(
                          glyph.color.withValues(alpha: 0.8)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Insets.md),
            Text(formatBytes(node.sizeBytes), style: AppType.mono),
            const SizedBox(width: Insets.sm),
            if (hovered && onDelete != null)
              IconSquareButton(
                icon: Icons.delete_outline_rounded,
                tooltip: 'Move to Trash',
                color: AppColors.danger,
                onPressed: busy ? () {} : onDelete!,
              )
            else if (hovered)
              IconSquareButton(
                icon: Icons.folder_open_rounded,
                tooltip: 'Reveal in Finder',
                onPressed: onReveal,
              )
            else if (drillable)
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: AppColors.textTertiary)
            else
              const SizedBox(width: 30),
          ],
        ),
      ),
    );
  }
}
