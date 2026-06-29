import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/models/system_stats.dart';
import '../../../core/services/native_system.dart';

/// Polls native `systemStats` on an interval and keeps rolling history buffers
/// for the live charts. Runs for the whole app lifetime so the menu bar stays
/// live even when the window is closed.
class StatsController extends ChangeNotifier {
  static const int historyLen = 60;

  SystemStats stats = SystemStats.empty;
  bool loaded = false;

  final List<double> cpuHistory = [];
  final List<double> gpuHistory = [];
  final List<double> memHistory = [];
  final List<double> netDownHistory = [];
  final List<double> netUpHistory = [];

  Timer? _timer;
  int _intervalSec = 2;
  bool _disposed = false;

  void start({int intervalSec = 2}) {
    _intervalSec = intervalSec;
    _tick();
    _restart();
  }

  void setInterval(int seconds) {
    final s = seconds.clamp(1, 10);
    if (s == _intervalSec) return;
    _intervalSec = s;
    _restart();
  }

  void _restart() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: _intervalSec), (_) => _tick());
  }

  Future<void> _tick() async {
    final m = await NativeSystem.systemStats();
    if (_disposed || m == null) return;
    stats = SystemStats.fromMap(m);
    _push(cpuHistory, stats.cpu);
    _push(gpuHistory, stats.gpu);
    _push(memHistory, stats.memPct);
    _push(netDownHistory, stats.netDown);
    _push(netUpHistory, stats.netUp);
    loaded = true;
    notifyListeners();
  }

  void _push(List<double> list, double value) {
    list.add(value);
    if (list.length > historyLen) list.removeAt(0);
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
