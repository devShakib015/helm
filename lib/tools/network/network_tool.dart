import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/byte_format.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/page_header.dart';
import '../system/ui/history_panel.dart';
import 'services/network_service.dart';
import 'state/network_controller.dart';
import 'widgets/sparkline.dart';

/// Accent for the Network tool.
const Color _kAccent = Color(0xFF22D3EE);

/// Live network monitor: download/upload throughput with sparklines, interface
/// addressing/status, and a list of established connections. The controller
/// self-samples on a 2s timer, so this root can stay stateless.
class NetworkTool extends StatelessWidget {
  const NetworkTool({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<NetworkController>();

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
                title: 'Network',
                subtitle: c.paused
                    ? 'Live monitoring paused'
                    : 'Live throughput, interfaces and connections',
                actions: [
                  HelmButton(
                    label: c.paused ? 'Resume' : 'Pause',
                    kind: HelmButtonKind.ghost,
                    icon: c.paused
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
                    onPressed: c.toggle,
                  ),
                ],
              ),
              const SizedBox(height: Insets.xl),
              if (c.loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 80),
                  child: Center(
                    child: CircularProgressIndicator(color: _kAccent),
                  ),
                )
              else ...[
              // Top row: Download / Upload big readouts over sparklines.
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                  Expanded(
                    child: _ThroughputCard(
                      label: 'Download',
                      icon: Icons.south_rounded,
                      bytesPerSec: c.downBytesPerSec,
                      samples: c.downSamples,
                      color: _kAccent,
                    ),
                  ),
                  const SizedBox(width: Insets.lg),
                  Expanded(
                    child: _ThroughputCard(
                      label: 'Upload',
                      icon: Icons.north_rounded,
                      bytesPerSec: c.upBytesPerSec,
                      samples: c.upSamples,
                      color: AppColors.accentAlt,
                    ),
                  ),
                  ],
                ),
              ),

              if (c.wifi.hasData) ...[
                const SizedBox(height: Insets.lg),
                _WifiCard(wifi: c.wifi),
              ],

              const SizedBox(height: Insets.lg),
              HistoryPanel(
                title: 'Download History',
                color: _kAccent,
                extract: (p) => p.netDown,
                maxY: null,
                formatValue: (v) => '${formatBytes(v.round())}/s',
              ),

              const SizedBox(height: Insets.lg),
              _InterfaceRow(interfaces: c.interfaces),

              const SizedBox(height: Insets.lg),
              _ConnectionsPanel(connections: c.connections),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ThroughputCard extends StatelessWidget {
  const _ThroughputCard({
    required this.label,
    required this.icon,
    required this.bytesPerSec,
    required this.samples,
    required this.color,
  });

  final String label;
  final IconData icon;
  final double bytesPerSec;
  final List<double> samples;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final parts = formatBytesParts(bytesPerSec.round());
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(
          Insets.xl, Insets.lg, Insets.xl, Insets.md),
      glow: color.withValues(alpha: 0.10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: Insets.sm),
              Text(label.toUpperCase(), style: AppType.micro),
            ],
          ),
          const SizedBox(height: Insets.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                parts.value,
                style: AppType.display.copyWith(
                  color: AppColors.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${parts.unit}/s',
                  style: AppType.headline.copyWith(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.sm),
          Sparkline(samples: samples, color: color),
        ],
      ),
    );
  }
}

class _WifiCard extends StatelessWidget {
  const _WifiCard({required this.wifi});
  final WifiInfo wifi;

  @override
  Widget build(BuildContext context) {
    final quality = wifi.quality;
    final bars = quality == null
        ? 0
        : (quality * 4).clamp(0, 4).ceil();
    return GlassPanel(
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _kAccent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: const Icon(Icons.wifi_rounded, size: 20, color: _kAccent),
          ),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(wifi.ssid ?? 'Wi-Fi', style: AppType.bodyStrong),
                const SizedBox(height: 2),
                Text(
                  [
                    if (wifi.signalDbm != null) '${wifi.signalDbm} dBm',
                    if (wifi.rateMbps != null) '${wifi.rateMbps} Mbps',
                  ].join('  ·  '),
                  style: AppType.caption.copyWith(color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
          _SignalBars(bars: bars),
        ],
      ),
    );
  }
}

class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.bars});
  final int bars;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (i) {
        final on = i < bars;
        return Padding(
          padding: const EdgeInsets.only(left: 3),
          child: Container(
            width: 5,
            height: 8.0 + i * 5,
            decoration: BoxDecoration(
              color: on
                  ? _kAccent
                  : AppColors.textTertiary.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }
}

class _InterfaceRow extends StatelessWidget {
  const _InterfaceRow({required this.interfaces});
  final List<NetInterface> interfaces;

  @override
  Widget build(BuildContext context) {
    if (interfaces.isEmpty) {
      return const SizedBox.shrink();
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        for (var i = 0; i < interfaces.length; i++) ...[
          if (i > 0) const SizedBox(width: Insets.lg),
          Expanded(child: _InterfaceCard(iface: interfaces[i])),
        ],
      ],
      ),
    );
  }
}

class _InterfaceCard extends StatelessWidget {
  const _InterfaceCard({required this.iface});
  final NetInterface iface;

  @override
  Widget build(BuildContext context) {
    final color = iface.active ? AppColors.success : AppColors.textTertiary;
    return GlassPanel(
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.glassStrong,
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Icon(
              iface.name == 'en1'
                  ? Icons.settings_ethernet_rounded
                  : Icons.lan_rounded,
              size: 20,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(iface.name, style: AppType.bodyStrong),
                const SizedBox(height: 2),
                Text(
                  iface.ipv4 ?? 'No IP address',
                  style: AppType.mono.copyWith(
                    color: iface.ipv4 != null
                        ? AppColors.textSecondary
                        : AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Insets.sm),
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: iface.active
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.6),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            iface.active ? 'Active' : 'Inactive',
            style: AppType.caption.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _ConnectionsPanel extends StatelessWidget {
  const _ConnectionsPanel({required this.connections});
  final List<NetConnection> connections;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(Insets.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Insets.md, Insets.sm, Insets.md, Insets.sm),
            child: Row(
              children: [
                const Icon(Icons.swap_horiz_rounded,
                    size: 16, color: _kAccent),
                const SizedBox(width: Insets.sm),
                Text('Active Connections', style: AppType.bodyStrong),
                const SizedBox(width: Insets.sm),
                Text(
                  '${connections.length}',
                  style: AppType.caption.copyWith(color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.stroke),
          if (connections.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: Insets.xxl),
              child: EmptyState(
                icon: Icons.cloud_off_rounded,
                accent: _kAccent,
                title: 'No active connections',
                message:
                    'No established TCP connections right now. They\'ll appear here as apps start talking to the network.',
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: Insets.xs),
                itemCount: connections.length,
                separatorBuilder: (_, _) => const SizedBox(height: 1),
                itemBuilder: (context, i) =>
                    _ConnectionRow(conn: connections[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class _ConnectionRow extends StatelessWidget {
  const _ConnectionRow({required this.conn});
  final NetConnection conn;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: Insets.md, vertical: 7),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              conn.process,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.bodyStrong,
            ),
          ),
          const SizedBox(width: Insets.md),
          Icon(Icons.arrow_right_alt_rounded,
              size: 16, color: AppColors.textTertiary),
          const SizedBox(width: Insets.md),
          Expanded(
            flex: 7,
            child: Text(
              conn.remote,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: AppType.mono.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
