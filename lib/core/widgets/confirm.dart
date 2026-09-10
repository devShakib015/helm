import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/removal_failure.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'buttons.dart';
import 'glass_panel.dart';

/// A glassy modal confirmation. Returns true if the user confirms.
Future<bool> showHelmConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  IconData icon = Icons.help_outline_rounded,
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (context) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: GlassPanel(
          blur: true,
          color: const Color(0xF21A2030),
          border: AppColors.strokeStrong,
          padding: const EdgeInsets.all(Insets.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: (danger ? AppColors.danger : AppColors.accent)
                          .withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                    child: Icon(icon,
                        color: danger ? AppColors.danger : AppColors.accent,
                        size: 22),
                  ),
                  const SizedBox(width: Insets.md),
                  Expanded(child: Text(title, style: AppType.headline)),
                ],
              ),
              const SizedBox(height: Insets.lg),
              Text(message, style: AppType.secondary),
              const SizedBox(height: Insets.xl),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  HelmButton(
                    label: cancelLabel,
                    kind: HelmButtonKind.ghost,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  const SizedBox(width: Insets.md),
                  HelmButton(
                    label: confirmLabel,
                    kind: danger ? HelmButtonKind.danger : HelmButtonKind.primary,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return result ?? false;
}

/// Reports what a removal actually did, when part of it did not happen.
///
/// Helm used to answer this with a count — "Moved 3 items to Trash · 1 skipped"
/// — which tells the user the one thing they already know and none of the thing
/// they need. The reason is almost always the same and is entirely actionable:
/// the item lives under `/Library`, which belongs to root, and removing it needs
/// an administrator. Saying so, and naming the items, is the whole fix.
Future<void> showRemovalReport(
  BuildContext context, {
  required int removed,
  required List<RemovalFailure> failed,
  String removedNoun = 'items',
}) async {
  if (failed.isEmpty) return;
  final admin = failed.where((f) => f.needsAdmin).toList();
  final other = failed.where((f) => !f.needsAdmin).toList();

  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (context) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: GlassPanel(
          blur: true,
          color: const Color(0xF21A2030),
          border: AppColors.strokeStrong,
          padding: const EdgeInsets.all(Insets.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                    child: const Icon(Icons.lock_outline_rounded,
                        color: AppColors.warning, size: 22),
                  ),
                  const SizedBox(width: Insets.md),
                  Expanded(
                    child: Text(
                      failed.length == 1
                          ? 'One item could not be removed'
                          : '${failed.length} items could not be removed',
                      style: AppType.headline,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Insets.lg),
              Text(
                removed > 0
                    ? '$removed $removedNoun went to the Trash. The rest are listed below, with the reason the system gave.'
                    : 'Nothing was removed. Here is the reason the system gave.',
                style: AppType.secondary,
              ),
              if (admin.isNotEmpty) ...[
                const SizedBox(height: Insets.lg),
                _ReasonGroup(
                  title: admin.length == 1
                      ? 'Needs an administrator'
                      : 'Need an administrator',
                  // The actionable half. Says what macOS reported and what
                  // would change it, and hedges the *cause* — /Library being
                  // root-owned is the usual one, but the error does not say
                  // so, and asserting it would repeat the "needs Full Disk
                  // Access" mistake this dialog replaced.
                  note:
                      'macOS refused: Helm runs as you, not as an administrator. Usually that is because the item sits in a folder the system owns, such as /Library. Remove them in Finder, where you will be asked for your password — or leave them, since they are inert without the app.',
                  items: admin,
                ),
              ],
              if (other.isNotEmpty) ...[
                const SizedBox(height: Insets.lg),
                _ReasonGroup(
                  title: other.length == 1 ? 'Other reason' : 'Other reasons',
                  note: null,
                  items: other,
                ),
              ],
              const SizedBox(height: Insets.xl),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  HelmButton(
                    label: 'Copy paths',
                    kind: HelmButtonKind.ghost,
                    onPressed: () => Clipboard.setData(ClipboardData(
                        text: failed.map((f) => f.path).join('\n'))),
                  ),
                  const SizedBox(width: Insets.md),
                  HelmButton(
                    label: 'Done',
                    kind: HelmButtonKind.primary,
                    onPressed: () => Navigator.of(context).pop(),
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

class _ReasonGroup extends StatelessWidget {
  const _ReasonGroup({
    required this.title,
    required this.note,
    required this.items,
  });

  final String title;
  final String? note;
  final List<RemovalFailure> items;

  @override
  Widget build(BuildContext context) {
    // Capped, with the remainder counted rather than dropped: a silent cut
    // would be the same shape of bug this dialog exists to fix.
    const cap = 6;
    final shown = items.take(cap).toList();
    final rest = items.length - shown.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppType.bodyStrong),
        if (note != null) ...[
          const SizedBox(height: Insets.xs),
          Text(note!, style: AppType.caption),
        ],
        const SizedBox(height: Insets.sm),
        for (final f in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: Insets.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 3),
                  child: Icon(Icons.remove_rounded,
                      size: 14, color: AppColors.textTertiary),
                ),
                const SizedBox(width: Insets.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(f.name,
                          style: AppType.body,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(f.path,
                          style: AppType.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (rest > 0)
          Text('and $rest more', style: AppType.caption),
      ],
    );
  }
}
