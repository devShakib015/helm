import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/glass_panel.dart';
import '../state/bt_devices_controller.dart';

/// Battery levels of connected Bluetooth devices (AirPods, Magic Keyboard,
/// Magic Mouse…). Renders nothing when no device reports a battery, so it can
/// be dropped into any page unconditionally.
class BtDevicesPanel extends StatelessWidget {
  const BtDevicesPanel({super.key});

  static IconData _icon(BtDevice d) {
    final k = '${d.kind} ${d.name}'.toLowerCase();
    if (k.contains('headphone') || k.contains('airpod')) {
      return Icons.headphones_rounded;
    }
    if (k.contains('keyboard')) return Icons.keyboard_rounded;
    if (k.contains('mouse')) return Icons.mouse_rounded;
    if (k.contains('trackpad')) return Icons.touch_app_rounded;
    if (k.contains('speaker')) return Icons.speaker_rounded;
    return Icons.bluetooth_rounded;
  }

  static Color _levelColor(int pct) {
    if (pct <= 15) return AppColors.danger;
    if (pct <= 30) return AppColors.warning;
    return AppColors.success;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<BtDevicesController>();
    if (c.devices.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassPanel(
          padding: const EdgeInsets.all(Insets.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.bluetooth_rounded,
                      size: 16, color: Color(0xFF38BDF8)),
                  const SizedBox(width: Insets.sm),
                  Text('Connected Devices', style: AppType.headline),
                ],
              ),
              const SizedBox(height: Insets.md),
              for (var i = 0; i < c.devices.length; i++) ...[
                if (i > 0) const SizedBox(height: Insets.md),
                _DeviceRow(device: c.devices[i]),
              ],
            ],
          ),
        ),
        const SizedBox(height: Insets.lg),
      ],
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.device});

  final BtDevice device;

  @override
  Widget build(BuildContext context) {
    final color = BtDevicesPanel._levelColor(device.percent);
    return Row(
      children: [
        Icon(BtDevicesPanel._icon(device),
            size: 16, color: AppColors.textSecondary),
        const SizedBox(width: Insets.md),
        SizedBox(
          width: 220,
          child: Text(
            device.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.body,
          ),
        ),
        const SizedBox(width: Insets.md),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.sm),
            child: LinearProgressIndicator(
              value: device.percent / 100,
              minHeight: 6,
              color: color,
              backgroundColor: AppColors.glassStrong,
            ),
          ),
        ),
        const SizedBox(width: Insets.md),
        SizedBox(
          width: 44,
          child: Text(
            '${device.percent}%',
            textAlign: TextAlign.right,
            style: AppType.mono.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
