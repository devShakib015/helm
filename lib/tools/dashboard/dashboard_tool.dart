import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_controller.dart';
import '../../app/menu_metric.dart';
import '../../app/tool_registry.dart';
import '../../core/models/system_stats.dart';
import '../../core/services/device_info_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/byte_format.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/hoverable.dart';
import '../../core/widgets/page_header.dart';
import '../../core/widgets/ring_gauge.dart';
import '../system/state/stats_controller.dart';

/// The app's marquee first page: a clean device spec sheet. A gradient hero
/// names the Mac and its OS, a live mini-stats row mirrors the menu-bar metrics,
/// and a glass "spec sheet" lists the static hardware facts.
///
/// `DeviceInfo` is loaded once in [initState]; the live bits read
/// [StatsController] via `context.watch`.
class DashboardTool extends StatefulWidget {
  const DashboardTool({super.key});

  @override
  State<DashboardTool> createState() => _DashboardToolState();
}

class _DashboardToolState extends State<DashboardTool> {
  DeviceInfo? _device;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final info = await DeviceInfoService().load();
    if (!mounted) return;
    setState(() => _device = info);
  }

  @override
  Widget build(BuildContext context) {
    final device = _device;
    if (device == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }

    final stats = context.watch<StatsController>().stats;

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
                title: 'Dashboard',
                subtitle: '${device.modelName} · ${device.osName}',
              ),
              const SizedBox(height: Insets.xl),
              _Hero(device: device),
              const SizedBox(height: Insets.lg),
              _LiveStatsRow(stats: stats),
              const SizedBox(height: Insets.lg),
              _SpecSheet(device: device, stats: stats),
              const SizedBox(height: Insets.xl),
              const _AllToolsSection(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Every tool, grouped by category, as a clickable launcher — a quick map of
/// what Helm can do straight from the first page.
class _AllToolsSection extends StatelessWidget {
  const _AllToolsSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('All Tools', style: AppType.title),
        const SizedBox(height: 2),
        Text('Everything Helm can do, grouped by purpose',
            style: AppType.secondary),
        for (final cat in ToolCategory.values) ...[
          Padding(
            padding:
                const EdgeInsets.fromLTRB(Insets.xs, Insets.lg, 0, Insets.sm),
            child: Row(
              children: [
                Icon(cat.icon, size: 13, color: AppColors.textTertiary),
                const SizedBox(width: 7),
                Text(cat.label.toUpperCase(), style: AppType.micro),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, c) {
              final tools = toolsInCategory(cat);
              final cols =
                  c.maxWidth >= 860 ? 3 : (c.maxWidth >= 560 ? 2 : 1);
              const gap = Insets.md;
              final w = (c.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final t in tools)
                    SizedBox(width: w, child: _ToolCard(meta: t)),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({required this.meta});

  final ToolMeta meta;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: () => context.read<AppController>().select(meta.id),
      builder: (context, hovered, _) => AnimatedContainer(
        duration: Motion.fast,
        padding: const EdgeInsets.all(Insets.md),
        decoration: BoxDecoration(
          color: hovered ? AppColors.glassHover : AppColors.glass,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(
              color: hovered ? AppColors.strokeStrong : AppColors.stroke),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: meta.accent.withValues(alpha: hovered ? 0.22 : 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(meta.icon, size: 20, color: meta.accent),
            ),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(meta.name, style: AppType.bodyStrong),
                  const SizedBox(height: 1),
                  Text(
                    meta.tagline,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.micro.copyWith(letterSpacing: 0),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Big rounded gradient tile: laptop glyph in a circle, model name, OS line.
class _Hero extends StatelessWidget {
  const _Hero({required this.device});

  final DeviceInfo device;

  @override
  Widget build(BuildContext context) {
    final title = device.chip.isEmpty
        ? device.modelName
        : '${device.modelName} · ${device.chip}';
    final osLine = device.osVersion.isEmpty
        ? device.osName
        : '${device.osName} (${device.osVersion})';

    return GlassPanel(
      padding: const EdgeInsets.symmetric(
          horizontal: Insets.xl, vertical: Insets.xxl),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0x335AC8FA), Color(0x335E5CE6)],
      ),
      border: AppColors.strokeStrong,
      glow: AppColors.accent.withValues(alpha: 0.12),
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.accentGradient,
              boxShadow: [
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.35),
                  blurRadius: 28,
                  spreadRadius: -4,
                ),
              ],
            ),
            child: const Icon(
              Icons.laptop_mac_rounded,
              size: 46,
              color: AppColors.textOnAccent,
            ),
          ),
          const SizedBox(height: Insets.lg),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppType.display,
          ),
          const SizedBox(height: Insets.xs),
          Text(
            osLine,
            textAlign: TextAlign.center,
            style: AppType.headline.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Four small live gauges mirroring the menu-bar metrics.
class _LiveStatsRow extends StatelessWidget {
  const _LiveStatsRow({required this.stats});

  final SystemStats stats;

  @override
  Widget build(BuildContext context) {
    final cells = <Widget>[
      _MiniGauge(
        metric: MenuMetric.cpu,
        percent: stats.cpu,
      ),
      _MiniGauge(
        metric: MenuMetric.gpu,
        percent: stats.gpu,
      ),
      _MiniGauge(
        metric: MenuMetric.ram,
        percent: stats.memPct,
      ),
      _MiniGauge(
        metric: MenuMetric.disk,
        percent: stats.diskPct,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 640 ? 4 : 2;
        const gap = Insets.md;
        final tileWidth =
            (constraints.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final c in cells) SizedBox(width: tileWidth, child: c),
          ],
        );
      },
    );
  }
}

class _MiniGauge extends StatelessWidget {
  const _MiniGauge({required this.metric, required this.percent});

  final MenuMetric metric;
  final double percent;

  @override
  Widget build(BuildContext context) {
    final info = metricInfo(metric);
    final value = (percent / 100).clamp(0.0, 1.0);
    return GlassPanel(
      padding: const EdgeInsets.symmetric(
          horizontal: Insets.md, vertical: Insets.lg),
      child: Column(
        children: [
          RingGauge(
            value: value,
            size: 96,
            thickness: 9,
            color: info.color,
            center: Text(
              '${percent.round()}%',
              style: AppType.headline.copyWith(
                color: AppColors.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: Insets.md),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(info.icon, size: 13, color: info.color),
              const SizedBox(width: 5),
              Text(info.short, style: AppType.micro),
            ],
          ),
        ],
      ),
    );
  }
}

/// Glass spec sheet: labelled rows separated by thin dividers.
class _SpecSheet extends StatelessWidget {
  const _SpecSheet({required this.device, required this.stats});

  final DeviceInfo device;
  final SystemStats stats;

  @override
  Widget build(BuildContext context) {
    final rows = <({String label, String value})>[
      (
        label: 'Processor',
        value: _processorValue(device),
      ),
      (
        label: 'Memory',
        value: device.memory.isEmpty ? '—' : device.memory,
      ),
      (
        label: 'Graphics',
        value: _graphicsValue(device),
      ),
      (
        label: 'Disk',
        value: device.diskTotalBytes > 0
            ? '${device.diskName} (${formatBytes(device.diskTotalBytes)})'
            : device.diskName,
      ),
      (
        label: 'Display',
        value: _displayValue(device),
      ),
      (
        label: 'Model identifier',
        value: device.modelIdentifier.isEmpty ? '—' : device.modelIdentifier,
      ),
      (
        label: 'Model number',
        value: device.modelNumber.isEmpty ? '—' : device.modelNumber,
      ),
      (
        label: 'Serial number',
        value: device.serial.isEmpty ? '—' : device.serial,
      ),
      (
        label: 'Uptime',
        value: _formatUptime(stats.uptime),
      ),
      (
        label: 'macOS build',
        value: device.osBuild.isEmpty ? '—' : device.osBuild,
      ),
    ];

    return GlassPanel(
      padding: const EdgeInsets.symmetric(
          horizontal: Insets.xl, vertical: Insets.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.stroke),
            _SpecRow(label: rows[i].label, value: rows[i].value),
          ],
        ],
      ),
    );
  }

  String _processorValue(DeviceInfo d) {
    final name = d.chip.isEmpty ? 'Apple silicon' : d.chip;
    if (d.coresTotal <= 0) return name;
    final breakdown = (d.coresPerformance > 0 || d.coresEfficiency > 0)
        ? ' (${d.coresPerformance}P + ${d.coresEfficiency}E)'
        : '';
    return '$name\n${d.coresTotal} cores$breakdown';
  }

  String _graphicsValue(DeviceInfo d) {
    final name = d.graphics.isEmpty ? (d.chip.isEmpty ? '—' : d.chip) : d.graphics;
    if (d.gpuCores > 0) return '$name\n${d.gpuCores}-core GPU';
    return name;
  }

  String _displayValue(DeviceInfo d) {
    if (d.displayResolution.isEmpty) return '—';
    return '${d.displayResolution}${d.displayRefresh.isEmpty ? '' : ' · ${d.displayRefresh}'}';
  }
}

class _SpecRow extends StatelessWidget {
  const _SpecRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Insets.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(label, style: AppType.secondary),
            ),
          ),
          const SizedBox(width: Insets.lg),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: AppType.bodyStrong,
            ),
          ),
        ],
      ),
    );
  }
}

/// Formats seconds of uptime like "14h 51m" or "2d 3h".
String _formatUptime(double seconds) {
  final total = seconds.isFinite && seconds > 0 ? seconds.round() : 0;
  if (total <= 0) return '—';
  final days = total ~/ 86400;
  final hours = (total % 86400) ~/ 3600;
  final mins = (total % 3600) ~/ 60;
  if (days > 0) return '${days}d ${hours}h';
  if (hours > 0) return '${hours}h ${mins}m';
  if (mins > 0) return '${mins}m';
  return '${total}s';
}
