import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/services/shell.dart';

/// One live process row.
class ProcInfo {
  const ProcInfo({
    required this.pid,
    required this.name,
    required this.cpu,
    required this.memBytes,
  });

  final int pid;
  final String name;
  final double cpu; // % of one core, Activity-Monitor style
  final int memBytes;
}

enum ProcSort { cpu, memory }

/// Live per-process CPU/memory via `top` (two samples, so the CPU numbers are
/// the CURRENT interval like Activity Monitor — `ps`'s %cpu is a lifetime
/// average and reads absurdly low). Polls every 4s; quit/force-kill included.
class ProcessesController extends ChangeNotifier {
  ProcessesController() {
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _tick());
  }

  static const int _rows = 30;

  List<ProcInfo> _procs = const [];
  ProcSort sort = ProcSort.cpu;
  String query = '';
  bool loaded = false;
  bool paused = false;

  Timer? _timer;
  bool _disposed = false;
  bool _sampling = false;
  final Map<int, DateTime> _recentlyKilled = {}; // pid → suppress-until

  List<ProcInfo> get processes {
    final q = query.trim().toLowerCase();
    final list = _procs
        .where((p) => q.isEmpty || p.name.toLowerCase().contains(q))
        .toList();
    list.sort((a, b) => sort == ProcSort.cpu
        ? b.cpu.compareTo(a.cpu)
        : b.memBytes.compareTo(a.memBytes));
    return list;
  }

  void setSort(ProcSort s) {
    if (sort == s) return;
    sort = s;
    _safeNotify();
    // The sample itself is criterion-ordered (top -o cpu/-o mem keeps only
    // the top rows BY that key), so a sort change needs a fresh fetch — just
    // re-sorting the top-30-by-CPU rows would fake the memory view.
    _tick();
  }

  void setQuery(String q) {
    query = q;
    _safeNotify();
  }

  void togglePaused() {
    paused = !paused;
    _safeNotify();
  }

  Future<void> _tick() async {
    if (_disposed || _sampling || paused) return;
    _sampling = true;
    try {
      // Two samples 1s apart; the second reflects current usage. `command`
      // is last so names containing spaces survive the split. The order key
      // matches the UI sort — top keeps only the top rows BY that key.
      final r = await Shell.run('top', [
        '-l', '2', '-s', '1', '-n', '$_rows',
        '-o', sort == ProcSort.cpu ? 'cpu' : 'mem',
        '-stats', 'pid,cpu,mem,command',
      ], timeout: const Duration(seconds: 15));
      if (_disposed || r.code != 0) return;
      var parsed = _parse(r.out);
      // A just-killed pid can still show in a sample that started before the
      // kill — suppress it briefly so rows don't flicker back from the dead.
      final now = DateTime.now();
      _recentlyKilled.removeWhere((_, t) => now.isAfter(t));
      if (_recentlyKilled.isNotEmpty) {
        parsed = parsed
            .where((p) => !_recentlyKilled.containsKey(p.pid))
            .toList();
      }
      // Non-tty `top` truncates command names (~16 chars); recover the full
      // executable names from `ps` in one cheap batch call.
      parsed = await _fullNames(parsed);
      if (_disposed) return;
      if (parsed.isNotEmpty || _procs.isEmpty) {
        _procs = parsed;
      }
      loaded = true;
      _safeNotify();
    } finally {
      _sampling = false;
    }
  }

  /// Replaces `top`'s truncated command names with full ones from `ps`.
  Future<List<ProcInfo>> _fullNames(List<ProcInfo> procs) async {
    if (procs.isEmpty) return procs;
    try {
      final pids = procs.map((p) => '${p.pid}').join(',');
      final r = await Shell.run('ps', ['-o', 'pid=,comm=', '-p', pids]);
      if (r.code != 0) return procs;
      final names = <int, String>{};
      for (final line in r.out.split('\n')) {
        final t = line.trim();
        if (t.isEmpty) continue;
        final sp = t.indexOf(' ');
        if (sp <= 0) continue;
        final pid = int.tryParse(t.substring(0, sp));
        if (pid == null) continue;
        final comm = t.substring(sp + 1).trim();
        if (comm.isEmpty) continue;
        names[pid] = comm.split('/').last;
      }
      return [
        for (final p in procs)
          names.containsKey(p.pid)
              ? ProcInfo(
                  pid: p.pid,
                  name: names[p.pid]!,
                  cpu: p.cpu,
                  memBytes: p.memBytes)
              : p,
      ];
    } catch (_) {
      return procs;
    }
  }

  /// Parses the LAST sample block of `top -l 2` output.
  List<ProcInfo> _parse(String out) {
    final lines = out.split('\n');
    var headerIdx = -1;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trimLeft().startsWith('PID')) headerIdx = i;
    }
    if (headerIdx < 0) return const [];
    final procs = <ProcInfo>[];
    for (var i = headerIdx + 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) break;
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 4) continue;
      final pid = int.tryParse(parts[0]);
      final cpu = double.tryParse(parts[1]);
      if (pid == null || cpu == null) continue;
      final mem = _memBytes(parts[2]);
      final name = parts.sublist(3).join(' ');
      if (name.isEmpty) continue;
      procs.add(ProcInfo(pid: pid, name: name, cpu: cpu, memBytes: mem));
    }
    return procs;
  }

  /// "394M", "1024K+", "2G-", "716B" → bytes.
  int _memBytes(String raw) {
    final s = raw.replaceAll(RegExp(r'[+\-]'), '');
    if (s.isEmpty) return 0;
    final unit = s[s.length - 1];
    final num = double.tryParse(s.substring(0, s.length - 1)) ??
        double.tryParse(s) ??
        0;
    return switch (unit) {
      'K' => (num * 1024).round(),
      'M' => (num * 1024 * 1024).round(),
      'G' => (num * 1024 * 1024 * 1024).round(),
      _ => num.round(),
    };
  }

  /// SIGTERM (polite) or SIGKILL (force). Returns false when the signal was
  /// refused (e.g. a root-owned process).
  Future<bool> kill(ProcInfo p, {bool force = false}) async {
    final r = await Shell.run('kill', [force ? '-9' : '-15', '${p.pid}']);
    if (r.code == 0) {
      _procs = _procs.where((x) => x.pid != p.pid).toList();
      // An in-flight sample may predate the kill; keep the row out until a
      // fresh sample can confirm reality.
      _recentlyKilled[p.pid] =
          DateTime.now().add(const Duration(seconds: 10));
      _safeNotify();
    }
    return r.code == 0;
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
