import 'package:flutter/foundation.dart';

import '../services/battery_service.dart';

/// Owns the battery dashboard's state. Reads a fresh [BatteryInfo] snapshot on
/// construction and again whenever [refresh] is called. There's no timer —
/// battery health changes slowly, so a manual refresh is plenty.
class BatteryController extends ChangeNotifier {
  BatteryController({BatteryService? service})
      : _service = service ?? const BatteryService() {
    refresh();
  }

  final BatteryService _service;

  BatteryInfo info = BatteryInfo.none;

  /// True until the first read completes.
  bool loading = true;

  bool _busy = false;
  bool _disposed = false;

  bool get hasBattery => info.hasBattery;

  Future<void> refresh() async {
    if (_busy) return;
    _busy = true;
    // Keep the first paint as a spinner; later refreshes update in place.
    if (info == BatteryInfo.none && loading) {
      _safeNotify();
    }
    try {
      info = await _service.read();
    } catch (_) {
      info = BatteryInfo.none;
    } finally {
      loading = false;
      _busy = false;
      _safeNotify();
    }
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
