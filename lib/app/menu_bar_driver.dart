import '../core/models/system_stats.dart';
import '../core/services/native_system.dart';
import '../core/utils/byte_format.dart';
import '../tools/clipboard/clipboard_controller.dart';
import '../tools/keepawake/keep_awake_controller.dart';
import '../tools/system/state/stats_controller.dart';
import 'menu_metric.dart';
import 'settings_controller.dart';

/// Glue between live stats + settings and the native menu-bar status item.
/// Builds the colored segment list and the dropdown detail lines, and keeps the
/// item's visibility / residency / refresh interval in sync with settings.
class MenuBarDriver {
  MenuBarDriver(this._stats, this._settings, this._clipboard, this._keepAwake) {
    _stats.addListener(_render);
    _settings.addListener(_applySettings);
    _clipboard.addListener(_render);
    _keepAwake.addListener(_render);
    _applySettings();
  }

  final StatsController _stats;
  final SettingsController _settings;
  final ClipboardController _clipboard;
  final KeepAwakeController _keepAwake;

  void _applySettings() {
    NativeSystem.menuBarSetVisible(_settings.menuBarEnabled);
    NativeSystem.setResident(_settings.residentInMenuBar);
    _stats.setInterval(_settings.refreshSeconds);
    _render();
  }

  void _render() {
    if (!_settings.menuBarEnabled) return;
    final s = _stats.stats;
    final segments = <Map<String, String>>[];
    for (final m in _settings.menuMetrics) {
      final seg = _segment(m, s);
      if (seg != null) segments.add(seg);
    }
    final clips = _settings.clipboardEnabled
        ? _clipboard.items.take(8).map((c) => c.text).toList()
        : const <String>[];
    NativeSystem.menuBarUpdate(
      segments: segments,
      details: _details(s),
      clips: clips,
      caffeine: _keepAwake.active,
    );
  }

  Map<String, String>? _segment(MenuMetric m, SystemStats s) {
    final info = metricInfo(m);
    final color = _settings.menuColored ? info.hex : '';
    String text;
    switch (m) {
      case MenuMetric.cpu:
        text = 'CPU ${s.cpu.round()}%';
      case MenuMetric.gpu:
        text = 'GPU ${s.gpu.round()}%';
      case MenuMetric.ram:
        text = 'RAM ${s.memPct.round()}%';
      case MenuMetric.disk:
        text = 'SSD ${s.diskPct.round()}%';
      case MenuMetric.network:
        text = '↓${_rate(s.netDown)} ↑${_rate(s.netUp)}';
      case MenuMetric.temp:
        if (s.tempCpu == null) return null; // hide if unavailable
        text = '${s.tempCpu!.round()}°';
      case MenuMetric.battery:
        if (s.batteryPct == null) return null; // hide on desktops
        text = 'BAT ${s.batteryPct}%${s.batteryCharging ? '⚡' : ''}';
    }
    return {'text': text, 'color': color};
  }

  List<String> _details(SystemStats s) {
    final lines = <String>[
      'Processor   ${s.cpu.round()}%',
      'Graphics    ${s.gpu.round()}%',
      'Memory      ${s.memPct.round()}%  ·  ${formatBytes(s.memUsed)}',
      'Disk        ${s.diskPct.round()}%  ·  ${formatBytes(s.diskFree)} free',
      'Download    ${formatBytes(s.netDown.round())}/s',
      'Upload      ${formatBytes(s.netUp.round())}/s',
    ];
    if (s.tempCpu != null) lines.add('CPU Temp    ${s.tempCpu!.round()}°C');
    if (s.batteryPct != null) {
      lines.add(
          'Battery     ${s.batteryPct}%${s.batteryCharging ? '  ·  Charging' : ''}');
    }
    lines.add('Uptime      ${_uptime(s.uptime)}');
    return lines;
  }

  /// Compact rate for the menu bar, e.g. "12K", "1.2M".
  String _rate(double bytesPerSec) {
    final p = formatBytesParts(bytesPerSec.round());
    final unit = p.unit.isEmpty ? 'B' : p.unit[0]; // B/K/M/G
    return '${p.value}$unit';
  }

  String _uptime(double seconds) {
    final s = seconds.round();
    final d = s ~/ 86400;
    final h = (s % 86400) ~/ 3600;
    final m = (s % 3600) ~/ 60;
    if (d > 0) return '${d}d ${h}h';
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  void dispose() {
    _stats.removeListener(_render);
    _settings.removeListener(_applySettings);
    _clipboard.removeListener(_render);
    _keepAwake.removeListener(_render);
  }
}
