import 'package:flutter/material.dart';

import '../core/models/system_stats.dart';

/// The system readings that can raise a threshold notification. Five climb
/// "above" a limit (CPU, GPU, RAM, Disk, Temp); battery falls "below" one.
enum AlertMetric { cpu, gpu, ram, disk, temp, battery }

/// Static description of one alertable metric: how to label it, what unit it
/// uses, which direction trips the alert, the allowed range, and how to pull
/// the live value out of a [SystemStats] sample.
class AlertMetricInfo {
  const AlertMetricInfo({
    required this.label,
    required this.unit,
    required this.below,
    required this.defaultThreshold,
    required this.min,
    required this.max,
    required this.step,
    required this.argb,
    required this.icon,
    required this.read,
  });

  final String label;
  final String unit; // '%' or '°C'
  final bool below; // true → alert when value <= threshold (battery)
  final int defaultThreshold;
  final int min;
  final int max;
  final int step;
  final int argb;
  final IconData icon;

  /// Live value for this metric, or null when the reading is unavailable
  /// (e.g. temperature on a Mac without SMC data, or battery on a desktop).
  final double? Function(SystemStats s) read;

  Color get color => Color(argb);

  /// Notification headline, e.g. "High Memory Usage" / "Low Battery".
  String get alertTitle => below ? 'Low $label' : 'High $label Usage';

  /// Body for a tripped reading against the user's chosen [threshold].
  String bodyFor(double value, int threshold) {
    final v = value.round();
    return below
        ? '$label is at $v$unit — below your $threshold$unit alert.'
        : '$label is at $v$unit — above your $threshold$unit alert.';
  }
}

const Map<AlertMetric, AlertMetricInfo> kAlertInfo = {
  AlertMetric.cpu: AlertMetricInfo(
    label: 'CPU',
    unit: '%',
    below: false,
    defaultThreshold: 90,
    min: 50,
    max: 99,
    step: 5,
    argb: 0xFFFB5C5C,
    icon: Icons.developer_board_rounded,
    read: _cpu,
  ),
  AlertMetric.gpu: AlertMetricInfo(
    label: 'GPU',
    unit: '%',
    below: false,
    defaultThreshold: 90,
    min: 50,
    max: 99,
    step: 5,
    argb: 0xFF22D3EE,
    icon: Icons.auto_awesome_motion_rounded,
    read: _gpu,
  ),
  AlertMetric.ram: AlertMetricInfo(
    label: 'Memory',
    unit: '%',
    below: false,
    defaultThreshold: 90,
    min: 50,
    max: 99,
    step: 5,
    argb: 0xFFA78BFA,
    icon: Icons.memory_rounded,
    read: _ram,
  ),
  AlertMetric.disk: AlertMetricInfo(
    label: 'Disk',
    unit: '%',
    below: false,
    defaultThreshold: 90,
    min: 50,
    max: 99,
    step: 5,
    argb: 0xFF34D399,
    icon: Icons.storage_rounded,
    read: _disk,
  ),
  AlertMetric.temp: AlertMetricInfo(
    label: 'CPU Temp',
    unit: '°C',
    below: false,
    defaultThreshold: 90,
    min: 60,
    max: 105,
    step: 5,
    argb: 0xFFFBBF24,
    icon: Icons.thermostat_rounded,
    read: _temp,
  ),
  AlertMetric.battery: AlertMetricInfo(
    label: 'Battery',
    unit: '%',
    below: true,
    defaultThreshold: 20,
    min: 5,
    max: 50,
    step: 5,
    argb: 0xFF38BDF8,
    icon: Icons.battery_alert_rounded,
    read: _battery,
  ),
};

AlertMetricInfo alertInfo(AlertMetric m) => kAlertInfo[m]!;

// Value extractors (kept top-level so the map entries can stay const).
double? _cpu(SystemStats s) => s.cpu;
double? _gpu(SystemStats s) => s.gpu;
double? _ram(SystemStats s) => s.memPct;
double? _disk(SystemStats s) => s.diskPct;
double? _temp(SystemStats s) => s.tempCpu;
double? _battery(SystemStats s) => s.batteryPct?.toDouble();

/// A user-configured alert rule for one metric.
class AlertRule {
  AlertRule({required this.enabled, required this.threshold});
  bool enabled;
  int threshold;
}
