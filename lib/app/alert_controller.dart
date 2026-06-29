import '../core/services/native_system.dart';
import '../tools/system/state/stats_controller.dart';
import 'alert_metric.dart';
import 'settings_controller.dart';

/// Watches live system stats and raises a macOS notification when an enabled
/// metric crosses its threshold. Uses simple hysteresis + a cooldown so a value
/// hovering around the limit doesn't spam: a rule fires when it first enters the
/// alert zone, re-arms only after the reading clears the limit (by a margin),
/// and otherwise re-fires at most once per [_cooldown] while it stays bad.
class AlertController {
  AlertController(this._stats, this._settings) {
    _stats.addListener(_evaluate);
  }

  final StatsController _stats;
  final SettingsController _settings;

  static const Duration _cooldown = Duration(minutes: 3);
  static const double _margin = 4; // re-arm hysteresis, in % / °C

  final Map<AlertMetric, bool> _armed = {
    for (final m in AlertMetric.values) m: true,
  };
  final Map<AlertMetric, DateTime> _lastFired = {};

  void _evaluate() {
    final s = _stats.stats;
    final now = DateTime.now();

    for (final m in AlertMetric.values) {
      final rule = _settings.alertRule(m);
      if (!rule.enabled) {
        _armed[m] = true; // a disabled rule resets cleanly
        continue;
      }
      final info = alertInfo(m);
      final value = info.read(s);
      if (value == null) continue; // reading unavailable right now

      final t = rule.threshold.toDouble();
      final tripped = info.below ? value <= t : value >= t;

      // Re-arm once the reading clears the threshold by the hysteresis margin.
      final cleared =
          info.below ? value >= t + _margin : value <= t - _margin;
      if (cleared) _armed[m] = true;

      if (!tripped) continue;

      final last = _lastFired[m];
      final cooledDown = last == null || now.difference(last) >= _cooldown;
      if ((_armed[m] ?? true) && cooledDown) {
        _armed[m] = false;
        _lastFired[m] = now;
        NativeSystem.notify(
          info.alertTitle,
          info.bodyFor(value, rule.threshold),
          sound: true,
        );
      }
    }
  }

  void dispose() {
    _stats.removeListener(_evaluate);
  }
}
