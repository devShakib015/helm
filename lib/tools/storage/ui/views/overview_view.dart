import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/app_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/byte_format.dart';
import '../../../../core/widgets/buttons.dart';
import '../../../../core/widgets/glass_panel.dart';
import '../../state/scan_state.dart';
import '../../state/storage_controller.dart';
import '../category_ui.dart';
import '../widgets/donut_chart.dart';
import '../widgets/page_chrome.dart';
import '../widgets/segment_bar.dart';

class OverviewView extends StatelessWidget {
  const OverviewView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<StorageController>();
    final app = context.read<AppController>();
    final v = c.volume;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Insets.xxl, Insets.xl, Insets.xxl, Insets.xxl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Storage',
                subtitle:
                    '${v.name}${v.deviceModel != null ? ' · ${v.deviceModel}' : ''} · ${formatBytes(v.totalBytes)} drive',
                actions: [
                  HelmButton(
                    label: c.hasResults ? 'Re-analyze' : 'Analyze Disk',
                    icon: Icons.radar_rounded,
                    onPressed: c.isScanning ? null : c.startScan,
                  ),
                ],
              ),
              const SizedBox(height: Insets.xl),
              if (c.stale)
                Padding(
                  padding: const EdgeInsets.only(bottom: Insets.lg),
                  child: NoticeBanner(
                    icon: Icons.refresh_rounded,
                    title: 'Results may be out of date',
                    message: 'You removed files since the last analysis.',
                    accent: AppColors.warning,
                    primaryLabel: 'Re-analyze',
                    onPrimary: c.isScanning ? null : c.startScan,
                  ),
                ),
              _VolumeHero(controller: c),
              const SizedBox(height: Insets.lg),
              _BreakdownCard(controller: c, app: app),
              if (c.snapshots.isNotEmpty) ...[
                const SizedBox(height: Insets.lg),
                _SnapshotsCard(controller: c),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _VolumeHero extends StatelessWidget {
  const _VolumeHero({required this.controller});
  final StorageController controller;

  @override
  Widget build(BuildContext context) {
    final v = controller.volume;
    final freeParts = formatBytesParts(v.freeBytes);
    return GlassPanel(
      padding: const EdgeInsets.all(Insets.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          DonutChart(
            size: 196,
            thickness: 20,
            segments: usageSegments(
              used: v.usedBytes,
              purgeable: v.purgeableBytes,
              free: v.freeBytes,
            ),
            center: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RichText(
                  text: TextSpan(children: [
                    TextSpan(text: freeParts.value, style: AppType.display),
                    TextSpan(
                        text: ' ${freeParts.unit}',
                        style: AppType.headline
                            .copyWith(color: AppColors.textSecondary)),
                  ]),
                ),
                Text('available', style: AppType.caption),
              ],
            ),
          ),
          const SizedBox(width: Insets.xxl),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('This Mac', style: AppType.micro),
                const SizedBox(height: Insets.sm),
                SegmentBar(
                  height: 16,
                  segments: [
                    BarSegment(v.usedBytes.toDouble(), AppColors.accent),
                    BarSegment(v.purgeableBytes.toDouble(), AppColors.purgeable),
                    BarSegment(v.freeBytes.toDouble(), AppColors.free),
                  ],
                ),
                const SizedBox(height: Insets.lg),
                LegendRow(
                    color: AppColors.accent,
                    label: 'Used',
                    value: formatBytes(v.usedBytes)),
                LegendRow(
                    color: AppColors.purgeable,
                    label: 'Purgeable',
                    value: formatBytes(v.purgeableBytes)),
                LegendRow(
                    color: AppColors.free,
                    label: 'Free',
                    value: formatBytes(v.freeBytes),
                    emphasized: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({required this.controller, required this.app});
  final StorageController controller;
  final AppController app;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(Insets.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Disk Breakdown', style: AppType.headline),
              const Spacer(),
              if (controller.hasResults)
                HelmButton(
                  label: 'View all',
                  kind: HelmButtonKind.ghost,
                  onPressed: () =>
                      app.selectStorageSection(StorageSection.categories),
                ),
            ],
          ),
          const SizedBox(height: Insets.lg),
          if (controller.isScanning)
            _InlineScanProgress(controller: controller)
          else if (controller.state == ScanState.error)
            _emptyHint(
              context,
              icon: Icons.error_outline_rounded,
              text: 'Something interrupted the scan. Try analyzing again.',
            )
          else if (!controller.hasResults)
            _emptyHint(
              context,
              icon: Icons.donut_large_rounded,
              text: 'Analyze your disk to see exactly what\'s using space, '
                  'broken down by category.',
            )
          else
            _CategoryPreview(controller: controller, app: app),
        ],
      ),
    );
  }

  Widget _emptyHint(BuildContext context,
      {required IconData icon, required String text}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Insets.lg),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textTertiary, size: 22),
          const SizedBox(width: Insets.md),
          Expanded(child: Text(text, style: AppType.secondary)),
        ],
      ),
    );
  }
}

class _CategoryPreview extends StatelessWidget {
  const _CategoryPreview({required this.controller, required this.app});
  final StorageController controller;
  final AppController app;

  @override
  Widget build(BuildContext context) {
    final cats = controller.categories.take(7).toList();
    final v = controller.volume;
    final segments = [
      for (final cat in controller.categories)
        DonutSegment(cat.sizeBytes.toDouble(), categoryColor(cat.kind)),
      DonutSegment(v.freeBytes.toDouble(), AppColors.free),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        DonutChart(
          size: 150,
          thickness: 16,
          segments: segments,
          center: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(formatBytes(v.occupiedBytes), style: AppType.headline),
              Text('used', style: AppType.caption),
            ],
          ),
        ),
        const SizedBox(width: Insets.xl),
        Expanded(
          child: Column(
            children: [
              for (final cat in cats)
                LegendRow(
                  color: categoryColor(cat.kind),
                  label: categoryLabel(cat.kind),
                  value: formatBytes(cat.sizeBytes),
                  onTap: () {
                    controller.select_(cat);
                    app.selectStorageSection(StorageSection.categories);
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InlineScanProgress extends StatelessWidget {
  const _InlineScanProgress({required this.controller});
  final StorageController controller;

  @override
  Widget build(BuildContext context) {
    final p = controller.progress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: Insets.md),
            Text('Analyzing… ${formatBytes(p.bytes)} · ${formatCount(p.files)} files',
                style: AppType.bodyStrong),
            const Spacer(),
            HelmButton(
              label: 'Cancel',
              kind: HelmButtonKind.ghost,
              onPressed: controller.cancelScan,
            ),
          ],
        ),
        const SizedBox(height: Insets.md),
        Text(
          p.currentPath ?? 'Preparing…',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.caption.copyWith(color: AppColors.textTertiary),
        ),
      ],
    );
  }
}

class _SnapshotsCard extends StatelessWidget {
  const _SnapshotsCard({required this.controller});
  final StorageController controller;

  @override
  Widget build(BuildContext context) {
    final snaps = controller.snapshots;
    return GlassPanel(
      padding: const EdgeInsets.all(Insets.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.history_rounded,
                  color: AppColors.purgeable, size: 20),
              const SizedBox(width: Insets.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${snaps.length} APFS Local Snapshot${snaps.length == 1 ? '' : 's'}',
                        style: AppType.headline),
                    Text(
                        'Time Machine snapshots stored on this disk. macOS frees them as needed — or thin them now.',
                        style: AppType.caption),
                  ],
                ),
              ),
              const SizedBox(width: Insets.md),
              HelmButton(
                label: 'Thin Snapshots',
                kind: HelmButtonKind.ghost,
                icon: Icons.auto_fix_high_rounded,
                onPressed: () => controller.thinSnapshots(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
