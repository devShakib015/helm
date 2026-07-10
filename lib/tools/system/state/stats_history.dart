import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'stats_controller.dart';

/// One 30-second telemetry sample.
class HistPoint {
  const HistPoint({
    required this.tMs,
    required this.cpu,
    required this.gpu,
    required this.ram,
    this.tempCpu,
    required this.netDown,
    required this.netUp,
  });

  final int tMs;
  final double cpu;
  final double gpu;
  final double ram;
  final double? tempCpu;
  final double netDown; // bytes/s
  final double netUp;

  List<dynamic> toJson() => [tMs, cpu, gpu, ram, tempCpu, netDown, netUp];

  factory HistPoint.fromJson(List<dynamic> j) => HistPoint(
        tMs: (j[0] as num).toInt(),
        cpu: (j[1] as num).toDouble(),
        gpu: (j[2] as num).toDouble(),
        ram: (j[3] as num).toDouble(),
        tempCpu: (j[4] as num?)?.toDouble(),
        netDown: (j[5] as num).toDouble(),
        netUp: (j[6] as num).toDouble(),
      );
}

/// Keeps 24 hours of samples (one per 30 s, ≤2880 points) for the history
/// charts on the monitor pages. Listens to the live [StatsController],
/// persists compactly to Application Support, and reloads on launch so charts
/// survive restarts.
class StatsHistory extends ChangeNotifier {
  StatsHistory(this._stats) {
    _load().then((_) {
      _stats.addListener(_onStats);
    });
  }

  static const Duration sampleEvery = Duration(seconds: 30);
  static const int maxPoints = 2880; // 24 h
  static const Duration _saveEvery = Duration(minutes: 5);

  final StatsController _stats;
  final List<HistPoint> _points = [];
  DateTime _lastSample = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastSave = DateTime.now();
  File? _file;
  bool _disposed = false;

  List<HistPoint> get points => List.unmodifiable(_points);

  /// Points within the trailing [window].
  List<HistPoint> recent(Duration window) {
    final cutoff =
        DateTime.now().subtract(window).millisecondsSinceEpoch;
    return _points.where((p) => p.tMs >= cutoff).toList();
  }

  void _onStats() {
    final now = DateTime.now();
    if (now.difference(_lastSample) < sampleEvery) return;
    _lastSample = now;
    final s = _stats.stats;
    if (s.memTotal <= 0) return; // no real sample yet
    _points.add(HistPoint(
      tMs: now.millisecondsSinceEpoch,
      cpu: s.cpu,
      gpu: s.gpu,
      ram: s.memPct,
      tempCpu: s.tempCpu,
      netDown: s.netDown,
      netUp: s.netUp,
    ));
    if (_points.length > maxPoints) {
      _points.removeRange(0, _points.length - maxPoints);
    }
    if (!_disposed) notifyListeners();
    if (now.difference(_lastSave) >= _saveEvery) {
      _lastSave = now;
      _save();
    }
  }

  Future<void> _load() async {
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}/stats_history.json');
      if (await _file!.exists()) {
        final raw = await _file!.readAsString();
        final cutoff = DateTime.now()
            .subtract(const Duration(hours: 24))
            .millisecondsSinceEpoch;
        final list = (json.decode(raw) as List)
            .map((e) => HistPoint.fromJson(e as List))
            .where((p) => p.tMs >= cutoff)
            .toList();
        _points
          ..clear()
          ..addAll(list);
        if (!_disposed) notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      _file ??= File(
          '${(await getApplicationSupportDirectory()).path}/stats_history.json');
      // Atomic write (tmp + rename): dying mid-write must never leave a
      // truncated file that silently wipes 24h of history on the next load.
      final tmp = File('${_file!.path}.tmp');
      await tmp
          .writeAsString(json.encode(_points.map((p) => p.toJson()).toList()));
      await tmp.rename(_file!.path);
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _stats.removeListener(_onStats);
    super.dispose();
  }
}
