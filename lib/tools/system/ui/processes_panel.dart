import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/byte_format.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/hoverable.dart';
import '../state/processes_controller.dart';

/// Activity-Monitor-lite: the busiest processes with live CPU/MEM, search,
/// sort, and Quit / Force Kill on hover.
class ProcessesPanel extends StatelessWidget {
  const ProcessesPanel({super.key, required this.accent});

  final Color accent;

  Future<void> _kill(
      BuildContext context, ProcessesController c, ProcInfo p,
      {required bool force}) async {
    final ok = await c.kill(p, force: force);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? '${force ? 'Killed' : 'Quit'} ${p.name}'
          : 'Couldn\'t signal ${p.name} — it may belong to the system'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ProcessesController>();

    return GlassPanel(
      padding: const EdgeInsets.all(Insets.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.account_tree_rounded, size: 16, color: accent),
              const SizedBox(width: Insets.sm),
              Text('Processes', style: AppType.headline),
              const Spacer(),
              _SortPill(
                label: 'CPU',
                selected: c.sort == ProcSort.cpu,
                color: accent,
                onTap: () => c.setSort(ProcSort.cpu),
              ),
              const SizedBox(width: 4),
              _SortPill(
                label: 'Memory',
                selected: c.sort == ProcSort.memory,
                color: accent,
                onTap: () => c.setSort(ProcSort.memory),
              ),
            ],
          ),
          const SizedBox(height: Insets.md),
          if (!c.loaded)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Insets.xl),
              child: Center(
                child: Text('Sampling processes…',
                    style: AppType.caption
                        .copyWith(color: AppColors.textTertiary)),
              ),
            )
          else ...[
            // Header row.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.sm),
              child: Row(
                children: [
                  const Expanded(child: Text('NAME', style: AppType.micro)),
                  SizedBox(
                      width: 64,
                      child: Text('CPU',
                          textAlign: TextAlign.right, style: AppType.micro)),
                  SizedBox(
                      width: 76,
                      child: Text('MEMORY',
                          textAlign: TextAlign.right, style: AppType.micro)),
                  const SizedBox(width: 66),
                ],
              ),
            ),
            const SizedBox(height: Insets.xs),
            for (final p in c.processes.take(15))
              _ProcRow(
                proc: p,
                accent: accent,
                onQuit: () => _kill(context, c, p, force: false),
                onForce: () => _kill(context, c, p, force: true),
              ),
          ],
        ],
      ),
    );
  }
}

class _ProcRow extends StatelessWidget {
  const _ProcRow({
    required this.proc,
    required this.accent,
    required this.onQuit,
    required this.onForce,
  });

  final ProcInfo proc;
  final Color accent;
  final VoidCallback onQuit;
  final VoidCallback onForce;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: () {},
      cursor: SystemMouseCursors.basic,
      builder: (context, hovered, _) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: Insets.sm, vertical: 5),
        decoration: BoxDecoration(
          color: hovered ? AppColors.glass : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                proc.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.body,
              ),
            ),
            SizedBox(
              width: 64,
              child: Text(
                '${proc.cpu.toStringAsFixed(1)}%',
                textAlign: TextAlign.right,
                style: AppType.mono.copyWith(
                  color:
                      proc.cpu >= 80 ? AppColors.danger : AppColors.textSecondary,
                ),
              ),
            ),
            SizedBox(
              width: 76,
              child: Text(
                formatBytes(proc.memBytes),
                textAlign: TextAlign.right,
                style: AppType.mono.copyWith(color: AppColors.textSecondary),
              ),
            ),
            SizedBox(
              width: 66,
              child: hovered
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconSquareButton(
                          icon: Icons.close_rounded,
                          tooltip: 'Quit',
                          onPressed: onQuit,
                        ),
                        const SizedBox(width: 4),
                        IconSquareButton(
                          icon: Icons.bolt_rounded,
                          tooltip: 'Force Kill',
                          color: AppColors.danger,
                          onPressed: onForce,
                        ),
                      ],
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _SortPill extends StatelessWidget {
  const _SortPill({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (context, hovered, _) => AnimatedContainer(
        duration: Motion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.20)
              : (hovered ? AppColors.glassHover : Colors.transparent),
          borderRadius: Radii.pill,
          border: Border.all(
            color: selected ? color.withValues(alpha: 0.5) : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: AppType.caption.copyWith(
            color: selected ? color : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
