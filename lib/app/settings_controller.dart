import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/services/native_system.dart';
import 'alert_metric.dart';
import 'menu_metric.dart';

/// Persistent app settings (shared_preferences), plus the bridge to native for
/// launch-at-login and menu-bar residency. The single source of truth the menu
/// bar and clipboard read from.
class SettingsController extends ChangeNotifier {
  SharedPreferences? _p;

  // Menu bar
  bool menuBarEnabled = true;
  List<MenuMetric> menuMetrics = const [
    MenuMetric.cpu,
    MenuMetric.ram,
    MenuMetric.network,
  ];
  bool menuColored = true;
  int refreshSeconds = 2;

  // Clipboard
  bool clipboardEnabled = true;
  int clipboardHistorySize = 200;
  bool clipboardIgnoreConcealed = true;
  bool clipboardClearOnQuit = false;
  bool clipboardNotify = true;

  // Alerts — one rule per metric, seeded from the metric defaults (all off).
  final Map<AlertMetric, AlertRule> _alertRules = {
    for (final m in AlertMetric.values)
      m: AlertRule(enabled: false, threshold: alertInfo(m).defaultThreshold),
  };

  // General
  bool launchAtLogin = false;
  bool residentInMenuBar = true;

  bool loaded = false;

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    final p = _p!;
    menuBarEnabled = p.getBool('menuBarEnabled') ?? true;
    menuColored = p.getBool('menuColored') ?? true;
    refreshSeconds = p.getInt('refreshSeconds') ?? 2;
    final metrics = p.getStringList('menuMetrics');
    if (metrics != null && metrics.isNotEmpty) {
      menuMetrics = metrics
          .map(_metricFromName)
          .whereType<MenuMetric>()
          .toList(growable: false);
      if (menuMetrics.isEmpty) menuMetrics = const [MenuMetric.cpu];
    }
    clipboardEnabled = p.getBool('clipboardEnabled') ?? true;
    clipboardHistorySize = p.getInt('clipboardHistorySize') ?? 200;
    clipboardIgnoreConcealed = p.getBool('clipboardIgnoreConcealed') ?? true;
    clipboardClearOnQuit = p.getBool('clipboardClearOnQuit') ?? false;
    clipboardNotify = p.getBool('clipboardNotify') ?? true;
    for (final m in AlertMetric.values) {
      final rule = _alertRules[m]!;
      rule.enabled = p.getBool('alert_${m.name}_on') ?? false;
      rule.threshold =
          p.getInt('alert_${m.name}_t') ?? alertInfo(m).defaultThreshold;
    }
    residentInMenuBar = p.getBool('residentInMenuBar') ?? true;
    launchAtLogin = await NativeSystem.getLaunchAtLogin();
    loaded = true;
    notifyListeners();
  }

  MenuMetric? _metricFromName(String name) {
    for (final m in MenuMetric.values) {
      if (m.name == name) return m;
    }
    return null;
  }

  // ---- Menu bar setters ----
  void setMenuBarEnabled(bool v) {
    menuBarEnabled = v;
    _p?.setBool('menuBarEnabled', v);
    notifyListeners();
  }

  void setMenuColored(bool v) {
    menuColored = v;
    _p?.setBool('menuColored', v);
    notifyListeners();
  }

  void setRefreshSeconds(int v) {
    refreshSeconds = v.clamp(1, 10);
    _p?.setInt('refreshSeconds', refreshSeconds);
    notifyListeners();
  }

  void toggleMetric(MenuMetric m) {
    final list = [...menuMetrics];
    if (list.contains(m)) {
      list.remove(m);
    } else {
      list.add(m);
    }
    if (list.isEmpty) return; // keep at least one
    menuMetrics = list;
    _p?.setStringList('menuMetrics', list.map((e) => e.name).toList());
    notifyListeners();
  }

  bool hasMetric(MenuMetric m) => menuMetrics.contains(m);

  // ---- Clipboard setters ----
  void setClipboardEnabled(bool v) {
    clipboardEnabled = v;
    _p?.setBool('clipboardEnabled', v);
    notifyListeners();
  }

  void setClipboardHistorySize(int v) {
    clipboardHistorySize = v.clamp(20, 1000);
    _p?.setInt('clipboardHistorySize', clipboardHistorySize);
    notifyListeners();
  }

  void setClipboardIgnoreConcealed(bool v) {
    clipboardIgnoreConcealed = v;
    _p?.setBool('clipboardIgnoreConcealed', v);
    notifyListeners();
  }

  void setClipboardClearOnQuit(bool v) {
    clipboardClearOnQuit = v;
    _p?.setBool('clipboardClearOnQuit', v);
    notifyListeners();
  }

  void setClipboardNotify(bool v) {
    clipboardNotify = v;
    _p?.setBool('clipboardNotify', v);
    notifyListeners();
  }

  // ---- Alert setters ----
  AlertRule alertRule(AlertMetric m) => _alertRules[m]!;

  bool get anyAlertEnabled => _alertRules.values.any((r) => r.enabled);

  void setAlertEnabled(AlertMetric m, bool v) {
    _alertRules[m]!.enabled = v;
    _p?.setBool('alert_${m.name}_on', v);
    notifyListeners();
  }

  void setAlertThreshold(AlertMetric m, int v) {
    final info = alertInfo(m);
    final clamped = v.clamp(info.min, info.max);
    _alertRules[m]!.threshold = clamped;
    _p?.setInt('alert_${m.name}_t', clamped);
    notifyListeners();
  }

  // ---- General setters ----
  Future<void> setLaunchAtLogin(bool v) async {
    final ok = await NativeSystem.setLaunchAtLogin(v);
    launchAtLogin = ok ? v : await NativeSystem.getLaunchAtLogin();
    notifyListeners();
  }

  void setResidentInMenuBar(bool v) {
    residentInMenuBar = v;
    _p?.setBool('residentInMenuBar', v);
    NativeSystem.setResident(v);
    notifyListeners();
  }
}
