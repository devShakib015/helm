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
import '../../core/widgets/ring_gauge.dart';
import '../system/ui/history_panel.dart';
import 'services/memory_service.dart';
import 'state/memory_controller.dart';

/// Live RAM dashboard: a memory-pressure ring, a breakdown of where memory is
/// going, and the top memory-consuming processes (each quittable).
class MemoryTool extends StatefulWidget {
  const MemoryTool({super.key});

  /// This tool's accent — emerald.
  static const Color accent = Color(0xFF34D399);

  @override
  State<MemoryTool> createState() => _MemoryToolState();
}

class _MemoryToolState extends State<MemoryTool> {
  /// Pids currently being quit, so we can busy/disable their row buttons.
  final Set<int> _quitting = {};

  Color _pressureColor(int level) {
    if (level == 4) return AppColors.danger;
    if (level == 2) return AppColors.warning;
    return AppColors.success;
  }

  Future<void> _freeMemory(MemoryController c) async {
    final res = await c.freeMemory();
    if (!mounted) return;
    final reclaimed = res.reclaimedBytes;
    final String text;
    if (res.ok && reclaimed > 0) {
      text = 'Freed ${formatBytes(reclaimed)} of inactive memory.';
    } else if (res.ok) {
      text = 'Freed inactive memory.';
    } else {
      text = 'Couldn\'t free memory — permission denied.';
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _quit(MemoryController c, MemoryProcess p) async {
    final ok = await showHelmConfirm(
      context,
      title: 'Quit ${p.name}?',
      message: 'Quit ${p.name}? Unsaved work may be lost.',
      confirmLabel: 'Quit',
      danger: true,
      icon: Icons.power_settings_new_rounded,
    );
    if (!ok || !mounted) return;
    setState(() => _quitting.add(p.pid));
    final done = await c.quitProcess(p.pid);
    if (!mounted) return;
    setState(() => _quitting.remove(p.pid));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(done
          ? 'Asked ${p.name} to quit.'
          : 'Couldn\'t quit ${p.name}.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<MemoryController>();

    if (!c.loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final snap = c.snapshot;
    if (snap.totalBytes <= 0) {
      return const EmptyState(
        icon: Icons.memory_rounded,
        accent: MemoryTool.accent,
        title: 'Memory stats unavailable',
        message:
            'Helm couldn\'t read live memory statistics from the system. Try refreshing in a moment.',
      );
    }

    final ringColor = _pressureColor(snap.pressureLevel);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          Insets.xxl, Insets.xl, Insets.xxl, Insets.xxl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Memory',
                subtitle:
                    '${snap.pressureLabel} pressure · ${formatBytes(snap.usedBytes)} of ${formatBytes(snap.totalBytes)} used',
                actions: [
                  HelmButton(
                    label: 'Free Up Memory',
                    icon: Icons.auto_awesome_rounded,
                    busy: c.freeing,
                    onPressed: c.freeing ? null : () => _freeMemory(c),
                  ),
                  HelmButton(
                    label: 'Refresh',
                    kind: HelmButtonKind.ghost,
                    icon: Icons.refresh_rounded,
                    onPressed: c.refresh,
                  ),
                ],
              ),
              const SizedBox(height: Insets.xl),
              _PressurePanel(snapshot: snap, color: ringColor),
              const SizedBox(height: Insets.lg),
              HistoryPanel(
                title: 'History',
                color: ringColor,
                extract: (p) => p.ram,
              ),
              const SizedBox(height: Insets.lg),
              _Breakdown(snapshot: snap),
              const SizedBox(height: Insets.lg),
              _TopProcesses(
                processes: c.processes,
                quitting: _quitting,
                onQuit: (p) => _quit(c, p),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The hero panel: ring gauge on the left, headline numbers on the right.
class _PressurePanel extends StatelessWidget {
  const _PressurePanel({required this.snapshot, required this.color});

  final MemorySnapshot snapshot;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final used = formatBytesParts(snapshot.usedBytes);
    final total = formatBytesParts(snapshot.totalBytes);
    final pct = (snapshot.usedFraction * 100).round();

    return GlassPanel(
      padding: const EdgeInsets.all(Insets.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          RingGauge(
            value: snapshot.usedFraction,
            color: color,
            size: 180,
            thickness: 16,
            center: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${used.value} ${used.unit}',
                  style: AppType.title.copyWith(
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'of ${total.value} ${total.unit}',
                  style: AppType.caption
                      .copyWith(color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(width: Insets.xl),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('MEMORY PRESSURE', style: AppType.micro),
                const SizedBox(height: Insets.sm),
                Text(
                  snapshot.pressureLabel,
                  style: AppType.display.copyWith(color: color),
                ),
                const SizedBox(height: Insets.sm),
                Text(
                  '$pct% used · ${formatBytes(snapshot.availableBytes)} available. ${_label(snapshot.pressureLevel)}',
                  style: AppType.secondary,
                ),
                const SizedBox(height: Insets.lg),
                Wrap(
                  spacing: Insets.xl,
                  runSpacing: Insets.md,
                  children: [
                    _MiniStat(
                      label: 'App Memory',
                      value: formatBytes(snapshot.appMemoryBytes),
                    ),
                    _MiniStat(
                      label: 'Wired',
                      value: formatBytes(snapshot.wiredBytes),
                    ),
                    _MiniStat(
                      label: 'Compressed',
                      value: formatBytes(snapshot.compressedBytes),
                    ),
                    _MiniStat(
                      label: 'Cached',
                      value: formatBytes(snapshot.cachedBytes),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _label(int level) {
    if (level == 4) return 'Under pressure — quitting apps will help.';
    if (level == 2) return 'Moderate — macOS is compressing memory.';
    return 'macOS has plenty of headroom.';
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: AppType.micro),
        const SizedBox(height: 3),
        Text(
          value,
          style: AppType.bodyStrong.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Horizontal proportional bar + tiles for where memory is going.
class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.snapshot});

  final MemorySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final segments = <({String label, int bytes, Color color})>[
      (label: 'App', bytes: snapshot.appMemoryBytes, color: MemoryTool.accent),
      (label: 'Wired', bytes: snapshot.wiredBytes, color: AppColors.accentAlt),
      (
        label: 'Compressed',
        bytes: snapshot.compressedBytes,
        color: AppColors.warning
      ),
      (label: 'Cached', bytes: snapshot.cachedBytes, color: AppColors.purgeable),
      (label: 'Free', bytes: snapshot.freeBytes, color: AppColors.free),
    ];
    final total = segments.fold<int>(0, (s, e) => s + e.bytes);

    return GlassPanel(
      padding: const EdgeInsets.all(Insets.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('BREAKDOWN', style: AppType.micro),
          const SizedBox(height: Insets.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.sm),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  for (final s in segments)
                    if (s.bytes > 0)
                      Expanded(
                        flex: total > 0 ? s.bytes : 1,
                        child: Container(color: s.color),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Insets.lg),
          Wrap(
            spacing: Insets.xl,
            runSpacing: Insets.md,
            children: [
              for (final s in segments)
                _LegendTile(
                  label: s.label,
                  value: formatBytes(s.bytes),
                  color: s.color,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendTile extends StatelessWidget {
  const _LegendTile({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: Insets.sm),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppType.caption),
            Text(
              value,
              style: AppType.bodyStrong.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The "Top Memory" list — aggregated processes, each with a ghost Quit button.
class _TopProcesses extends StatelessWidget {
  const _TopProcesses({
    required this.processes,
    required this.quitting,
    required this.onQuit,
  });

  final List<MemoryProcess> processes;
  final Set<int> quitting;
  final ValueChanged<MemoryProcess> onQuit;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(Insets.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Insets.sm, Insets.sm, Insets.sm, Insets.xs),
            child: Text('TOP MEMORY', style: AppType.micro),
          ),
          if (processes.isEmpty)
            const Padding(
              padding: EdgeInsets.all(Insets.lg),
              child: Text('No process data available.',
                  style: AppType.secondary),
            )
          else
            for (var i = 0; i < processes.length; i++) ...[
              if (i > 0)
                const Divider(height: 1, color: AppColors.stroke),
              _ProcessRow(
                process: processes[i],
                busy: quitting.contains(processes[i].pid),
                onQuit: () => onQuit(processes[i]),
              ),
            ],
        ],
      ),
    );
  }
}

class _ProcessRow extends StatelessWidget {
  const _ProcessRow({
    required this.process,
    required this.busy,
    required this.onQuit,
  });

  final MemoryProcess process;
  final bool busy;
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: Insets.sm, vertical: Insets.sm),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: MemoryTool.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: const Icon(Icons.memory_rounded,
                color: MemoryTool.accent, size: 18),
          ),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(process.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.bodyStrong),
                const SizedBox(height: 1),
                Text('PID ${process.pid}',
                    style: AppType.caption
                        .copyWith(color: AppColors.textTertiary)),
              ],
            ),
          ),
          const SizedBox(width: Insets.md),
          Text(
            formatBytes(process.bytes),
            style: AppType.mono,
          ),
          const SizedBox(width: Insets.md),
          _QuitButton(busy: busy, onPressed: onQuit),
        ],
      ),
    );
  }
}

/// A small ghost "Quit" button used per process row.
class _QuitButton extends StatelessWidget {
  const _QuitButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      enabled: !busy,
      onTap: busy ? null : onPressed,
      builder: (context, hovered, pressed) => AnimatedContainer(
        duration: Motion.fast,
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: Insets.md),
        decoration: BoxDecoration(
          color: hovered ? AppColors.dangerSoft : AppColors.glassStrong,
          borderRadius: Radii.pill,
          border: Border.all(
            color: hovered
                ? AppColors.danger.withValues(alpha: 0.4)
                : AppColors.stroke,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.danger),
              )
            else
              Icon(Icons.close_rounded,
                  size: 13,
                  color: hovered
                      ? AppColors.danger
                      : AppColors.textSecondary),
            const SizedBox(width: 5),
            Text(
              'Quit',
              style: AppType.caption.copyWith(
                color: hovered ? AppColors.danger : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
