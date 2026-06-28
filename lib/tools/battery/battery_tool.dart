import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/page_header.dart';
import '../../core/widgets/ring_gauge.dart';
import 'services/battery_service.dart';
import 'state/battery_controller.dart';

/// Read-only dashboard of battery health and power state: a big charge ring,
/// a grid of health stat tiles, and a few macOS energy tips. Refresh is manual.
class BatteryTool extends StatelessWidget {
  const BatteryTool({super.key});

  static const Color _accent = Color(0xFF38BDF8);

  @override
  Widget build(BuildContext context) {
    final c = context.watch<BatteryController>();

    if (c.loading) {
      return const Center(
        child: CircularProgressIndicator(color: _accent),
      );
    }

    if (!c.hasBattery) {
      return Padding(
        padding: const EdgeInsets.all(Insets.xxl),
        child: EmptyState(
          icon: Icons.power_rounded,
          accent: _accent,
          title: 'Running on AC power',
          message: 'No battery detected on this Mac.',
          action: HelmButton(
            label: 'Refresh',
            kind: HelmButtonKind.ghost,
            icon: Icons.refresh_rounded,
            onPressed: c.refresh,
          ),
        ),
      );
    }

    final info = c.info;

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
                title: 'Battery',
                subtitle: _headerSubtitle(info),
                actions: [
                  HelmButton(
                    label: 'Refresh',
                    kind: HelmButtonKind.ghost,
                    icon: Icons.refresh_rounded,
                    onPressed: c.refresh,
                  ),
                ],
              ),
              const SizedBox(height: Insets.xl),
              _ChargePanel(info: info, accent: _accent),
              const SizedBox(height: Insets.lg),
              _StatGrid(info: info, accent: _accent),
              const SizedBox(height: Insets.lg),
              const _EnergyTips(accent: _accent),
            ],
          ),
        ),
      ),
    );
  }

  String _headerSubtitle(BatteryInfo info) {
    final src = info.powerSource ?? (info.onAcPower ? 'AC Power' : 'Battery');
    final pct = info.chargePercent;
    if (pct == null) return 'Power source · $src';
    return '$pct% charged · $src';
  }
}

/// The hero charge ring plus a one-line status caption underneath.
class _ChargePanel extends StatelessWidget {
  const _ChargePanel({required this.info, required this.accent});

  final BatteryInfo info;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final pct = info.chargePercent;
    final ringColor = _ringColor(info, accent);

    return GlassPanel(
      padding: const EdgeInsets.symmetric(
          horizontal: Insets.xl, vertical: Insets.xl),
      child: Column(
        children: [
          RingGauge(
            value: info.fraction,
            size: 188,
            thickness: 16,
            color: ringColor,
            center: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  pct == null ? '--' : '$pct%',
                  style: AppType.display.copyWith(
                    fontSize: 44,
                    color: AppColors.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_statusIcon(info), size: 14, color: ringColor),
                    const SizedBox(width: 5),
                    Text(
                      _statusText(info),
                      style: AppType.caption.copyWith(color: ringColor),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: Insets.lg),
          Text(
            _powerLine(info),
            style: AppType.secondary,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _powerLine(BatteryInfo info) {
    if (info.charging) {
      final t = info.timeRemaining;
      if (t != null && t.isNotEmpty && !t.toLowerCase().contains('calcul')) {
        return 'Charging · $t';
      }
      return 'Charging';
    }
    if (info.fullyCharged) return 'Fully charged · running on adapter';
    if (info.onAcPower) return 'Plugged in · not charging';
    final t = info.timeRemaining;
    if (t != null && t.isNotEmpty && !t.toLowerCase().contains('calcul')) {
      return 'On battery · $t';
    }
    return 'On battery power';
  }
}

/// The row/grid of health stat tiles.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.info, required this.accent});

  final BatteryInfo info;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final cap = info.maxCapacityPercent;
    final tiles = <Widget>[
      StatTile(
        label: 'Condition',
        value: info.condition ?? 'Unknown',
        icon: Icons.favorite_rounded,
        color: _conditionColor(info.condition),
      ),
      StatTile(
        label: 'Cycle Count',
        value: info.cycleCount?.toString() ?? '—',
        icon: Icons.loop_rounded,
        color: AppColors.textPrimary,
      ),
      StatTile(
        label: 'Max Capacity',
        value: cap == null ? '—' : '$cap%',
        sub: cap == null ? null : 'of original design',
        icon: Icons.battery_charging_full_rounded,
        color: _capacityColor(cap),
      ),
      StatTile(
        label: 'Power Source',
        value: info.onAcPower ? 'AC Power' : 'Battery',
        sub: info.chargerName,
        icon: info.onAcPower ? Icons.power_rounded : Icons.battery_std_rounded,
        color: info.onAcPower ? accent : AppColors.textPrimary,
      ),
      StatTile(
        label: 'Time Remaining',
        value: _timeValue(info),
        icon: Icons.schedule_rounded,
        color: AppColors.textPrimary,
      ),
      StatTile(
        label: 'Charging',
        value: _chargingValue(info),
        icon: info.charging
            ? Icons.bolt_rounded
            : Icons.bolt_outlined,
        color: info.charging ? accent : AppColors.textSecondary,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Aim for ~3 columns on wide layouts, fewer when cramped.
        final cols = constraints.maxWidth >= 760
            ? 3
            : (constraints.maxWidth >= 480 ? 2 : 1);
        const gap = Insets.md;
        final tileWidth =
            (constraints.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final t in tiles)
              SizedBox(width: tileWidth, child: t),
          ],
        );
      },
    );
  }

  String _timeValue(BatteryInfo info) {
    final t = info.timeRemaining;
    if (info.fullyCharged && !info.charging) return 'Charged';
    if (t == null || t.isEmpty) {
      return info.onAcPower ? 'On adapter' : 'Calculating…';
    }
    // Strip a trailing "remaining"/"until full" for a tidy tile value.
    return t
        .replaceAll(RegExp(r'\s*(remaining|until full)\s*',
            caseSensitive: false), '')
        .trim()
        .ifEmpty(t);
  }

  String _chargingValue(BatteryInfo info) {
    if (info.charging) return 'Yes';
    if (info.fullyCharged) return 'Full';
    if (info.onAcPower) return 'Not charging';
    return 'No';
  }
}

/// Static macOS energy-saving guidance.
class _EnergyTips extends StatelessWidget {
  const _EnergyTips({required this.accent});

  final Color accent;

  static const List<({IconData icon, String title, String body})> _tips = [
    (
      icon: Icons.thermostat_rounded,
      title: 'Keep it cool',
      body:
          'Heat is the biggest enemy of battery health. Avoid leaving your Mac in a hot car or in direct sun.',
    ),
    (
      icon: Icons.battery_saver_rounded,
      title: 'Use Optimised Charging',
      body:
          'In System Settings → Battery, enable Optimised Battery Charging so macOS learns your routine and limits time at 100%.',
    ),
    (
      icon: Icons.brightness_6_rounded,
      title: 'Dim the display',
      body:
          'The screen draws the most power. Lower brightness and enable Low Power Mode when you need to stretch a charge.',
    ),
    (
      icon: Icons.percent_rounded,
      title: 'Avoid the extremes',
      body:
          'Lithium-ion batteries age fastest at 0% and 100%. Keeping charge roughly between 20–80% prolongs lifespan.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(Insets.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_rounded, size: 16, color: accent),
              const SizedBox(width: Insets.sm),
              Text('Energy Tips', style: AppType.headline),
            ],
          ),
          const SizedBox(height: Insets.md),
          for (var i = 0; i < _tips.length; i++) ...[
            if (i > 0) const SizedBox(height: Insets.md),
            _TipRow(tip: _tips[i], accent: accent),
          ],
        ],
      ),
    );
  }
}

class _TipRow extends StatelessWidget {
  const _TipRow({required this.tip, required this.accent});

  final ({IconData icon, String title, String body}) tip;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: Icon(tip.icon, size: 17, color: accent),
        ),
        const SizedBox(width: Insets.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tip.title, style: AppType.bodyStrong),
              const SizedBox(height: 2),
              Text(
                tip.body,
                style: AppType.caption.copyWith(color: AppColors.textTertiary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---- shared helpers -------------------------------------------------------

Color _ringColor(BatteryInfo info, Color accent) {
  if (info.charging) return accent;
  final pct = info.chargePercent ?? 0;
  if (pct > 50) return AppColors.success;
  if (pct >= 20) return AppColors.warning;
  return AppColors.danger;
}

IconData _statusIcon(BatteryInfo info) {
  if (info.charging) return Icons.bolt_rounded;
  if (info.fullyCharged) return Icons.check_rounded;
  if (info.onAcPower) return Icons.power_rounded;
  return Icons.battery_std_rounded;
}

String _statusText(BatteryInfo info) {
  if (info.charging) return 'Charging';
  if (info.fullyCharged) return 'Charged';
  if (info.onAcPower) return 'Plugged in';
  return 'On battery';
}

Color _conditionColor(String? condition) {
  if (condition == null) return AppColors.textPrimary;
  final l = condition.toLowerCase();
  if (l.contains('service') || l.contains('replace')) return AppColors.danger;
  if (l.contains('fair') || l.contains('check')) return AppColors.warning;
  if (l.contains('good') || l.contains('normal')) return AppColors.success;
  return AppColors.textPrimary;
}

Color _capacityColor(int? cap) {
  if (cap == null) return AppColors.textPrimary;
  if (cap >= 80) return AppColors.success;
  if (cap >= 60) return AppColors.warning;
  return AppColors.danger;
}

extension _IfEmpty on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
