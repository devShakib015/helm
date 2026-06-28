import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/network_service.dart';

/// Drives the live Network monitor: samples cumulative byte counters every 2s,
/// derives per-second throughput, keeps a ring buffer for the sparklines, and
/// periodically refreshes interfaces and established connections. Wi-Fi is read
/// lazily once. The 2s timer is started in the constructor and cancelled in
/// dispose; every notify goes through [_safeNotify] so nothing fires after
/// disposal.
class NetworkController extends ChangeNotifier {
  NetworkController() {
    _start();
  }

  final NetworkService _service = NetworkService();

  static const int _bufferSize = 40;
  static const Duration _interval = Duration(seconds: 2);

  bool _disposed = false;
  Timer? _timer;

  bool paused = false;
  bool _loadedOnce = false;

  /// True until the very first sample lands, so the UI can show a spinner.
  bool get loading => !_loadedOnce;

  // Current per-second throughput.
  double downBytesPerSec = 0;
  double upBytesPerSec = 0;

  // Ring buffers of recent per-second throughput (oldest first, newest last).
  final List<double> downSamples = <double>[];
  final List<double> upSamples = <double>[];

  List<NetInterface> interfaces = const [];
  List<NetConnection> connections = const [];
  WifiInfo wifi = const WifiInfo();
  bool _wifiRequested = false;

  TrafficCounters? _lastCounters;
  DateTime? _lastSampleAt;
  int _ticks = 0;

  void _start() {
    // Prime an immediate sample, then sample on the interval.
    _tick();
    _timer = Timer.periodic(_interval, (_) => _tick());
  }

  Future<void> _tick() async {
    if (paused || _disposed) return;

    final now = DateTime.now();
    final counters = await _service.readCounters();
    if (_disposed) return;

    final prev = _lastCounters;
    final prevAt = _lastSampleAt;
    if (prev != null && prevAt != null) {
      final seconds = now.difference(prevAt).inMilliseconds / 1000.0;
      if (seconds > 0) {
        // Guard against counter resets (interface flap) producing negatives.
        final dIn = counters.inBytes - prev.inBytes;
        final dOut = counters.outBytes - prev.outBytes;
        downBytesPerSec = dIn > 0 ? dIn / seconds : 0;
        upBytesPerSec = dOut > 0 ? dOut / seconds : 0;
      }
      _pushSample(downSamples, downBytesPerSec);
      _pushSample(upSamples, upBytesPerSec);
    }
    _lastCounters = counters;
    _lastSampleAt = now;

    // Paint the dashboard immediately once we have a throughput baseline — the
    // UI must never wait on the slower interface/connection lookups below.
    _loadedOnce = true;
    _safeNotify();

    // Refresh interfaces & connections on the first tick and every ~5th tick
    // (~10s) thereafter — they change far less often than throughput.
    if (_ticks == 0 || _ticks % 5 == 0) {
      final ifaces = await _service.readInterfaces();
      if (_disposed) return;
      interfaces = ifaces;

      final conns = await _service.readConnections(cap: 60);
      if (_disposed) return;
      connections = conns;
      _safeNotify();
    }
    _ticks++;

    // Lazily fetch Wi-Fi once in the background; don't block the throughput
    // loop on it and don't retry if it comes back empty.
    if (!_wifiRequested) {
      _wifiRequested = true;
      unawaited(_loadWifi());
    }
  }

  Future<void> _loadWifi() async {
    try {
      final info = await _service.readWifi();
      if (_disposed) return;
      if (info.hasData) {
        wifi = info;
        _safeNotify();
      }
    } catch (_) {
      // Skip silently if slow/empty.
    }
  }

  void _pushSample(List<double> buffer, double value) {
    buffer.add(value);
    if (buffer.length > _bufferSize) {
      buffer.removeAt(0);
    }
  }

  /// Stops the live timer (freezes the readouts and sparklines).
  void pause() {
    if (paused) return;
    paused = true;
    _safeNotify();
  }

  /// Resumes live sampling. Re-baselines so the first delta after a pause isn't
  /// counted as a huge spike.
  void resume() {
    if (!paused) return;
    paused = false;
    _lastCounters = null;
    _lastSampleAt = null;
    _safeNotify();
  }

  void toggle() => paused ? resume() : pause();

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
