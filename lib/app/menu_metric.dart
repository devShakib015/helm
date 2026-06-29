import 'package:flutter/material.dart';

/// Metrics that can be shown in the menu bar (and reused as labels/colors in
/// the monitor pages).
enum MenuMetric { cpu, gpu, ram, disk, network, temp, battery }

class MetricInfo {
  const MetricInfo(this.label, this.short, this.argb, this.icon);
  final String label;
  final String short; // menu-bar label, e.g. "CPU"
  final int argb;
  final IconData icon;

  Color get color => Color(argb);

  /// 6-digit hex (no alpha) for the native menu-bar renderer.
  String get hex =>
      argb.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();
}

const Map<MenuMetric, MetricInfo> kMetricInfo = {
  MenuMetric.cpu: MetricInfo('Processor', 'CPU', 0xFFFB5C5C, Icons.developer_board_rounded),
  MenuMetric.gpu: MetricInfo('Graphics', 'GPU', 0xFF22D3EE, Icons.auto_awesome_motion_rounded),
  MenuMetric.ram: MetricInfo('Memory', 'RAM', 0xFFA78BFA, Icons.memory_rounded),
  MenuMetric.disk: MetricInfo('Disk', 'SSD', 0xFF34D399, Icons.storage_rounded),
  MenuMetric.network: MetricInfo('Network', 'NET', 0xFF5AC8FA, Icons.swap_vert_rounded),
  MenuMetric.temp: MetricInfo('Sensors', 'TMP', 0xFFFBBF24, Icons.thermostat_rounded),
  MenuMetric.battery: MetricInfo('Battery', 'BAT', 0xFF34D399, Icons.battery_charging_full_rounded),
};

MetricInfo metricInfo(MenuMetric m) => kMetricInfo[m]!;
