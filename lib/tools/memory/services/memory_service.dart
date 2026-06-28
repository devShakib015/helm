import '../../../core/services/shell.dart';

/// A live snapshot of system memory, derived from `sysctl` + `vm_stat`, using
/// the **same accounting as Activity Monitor**:
///
///   Memory Used = App Memory + Wired + Compressed
///
/// Crucially, *inactive / cached* memory is NOT counted as used — macOS reclaims
/// it instantly when an app needs it, so it's effectively available. And memory
/// "pressure" is the kernel's own signal (`kern.memorystatus_vm_pressure_level`),
/// not a naive used÷total ratio (which is always high because macOS caches
/// aggressively and says nothing about health).
class MemorySnapshot {
  const MemorySnapshot({
    required this.totalBytes,
    required this.freeBytes,
    required this.wiredBytes,
    required this.activeBytes,
    required this.inactiveBytes,
    required this.compressedBytes,
    required this.appMemoryBytes,
    this.rawPressureLevel = 0,
  });

  /// Total physical RAM.
  final int totalBytes;

  /// Genuinely free pages (free + speculative).
  final int freeBytes;

  /// Wired (cannot be paged out) memory.
  final int wiredBytes;

  /// Active pages (kept for the breakdown display).
  final int activeBytes;

  /// Inactive pages — reclaimable cache, counted as available, not used.
  final int inactiveBytes;

  /// Memory occupied by the compressor.
  final int compressedBytes;

  /// "App Memory" as Activity Monitor reports it ≈ anonymous − purgeable pages.
  final int appMemoryBytes;

  /// Kernel pressure level from sysctl (1 normal, 2 warning, 4 critical, 0
  /// unknown → derived from available memory).
  final int rawPressureLevel;

  /// Activity Monitor's "Memory Used" — App + Wired + Compressed. Excludes
  /// inactive/cached memory.
  int get usedBytes {
    final u = appMemoryBytes + wiredBytes + compressedBytes;
    if (u < 0) return 0;
    return u > totalBytes ? totalBytes : u;
  }

  /// Memory available to apps right now (everything that isn't really used).
  int get availableBytes {
    final a = totalBytes - usedBytes;
    return a < 0 ? 0 : a;
  }

  /// Reclaimable "Cached Files" (inactive + purgeable + file-backed) — the
  /// remainder once truly-used and truly-free are removed.
  int get cachedBytes {
    final c = totalBytes - usedBytes - freeBytes;
    return c < 0 ? 0 : c;
  }

  /// 0..1 share of RAM that's actually used (for the ring fill, not pressure).
  double get usedFraction {
    if (totalBytes <= 0) return 0;
    final f = usedBytes / totalBytes;
    return f < 0 ? 0 : (f > 1 ? 1 : f);
  }

  /// Effective pressure level: the kernel's value if known, otherwise derived
  /// from how little memory is available.
  int get pressureLevel {
    if (rawPressureLevel == 1 || rawPressureLevel == 2 || rawPressureLevel == 4) {
      return rawPressureLevel;
    }
    final availFrac = totalBytes <= 0 ? 1.0 : availableBytes / totalBytes;
    if (availFrac < 0.10) return 4;
    if (availFrac < 0.20) return 2;
    return 1;
  }

  String get pressureLabel => switch (pressureLevel) {
        2 => 'Warning',
        4 => 'Critical',
        _ => 'Normal',
      };

  bool get healthy => pressureLevel == 1;

  static const MemorySnapshot empty = MemorySnapshot(
    totalBytes: 0,
    freeBytes: 0,
    wiredBytes: 0,
    activeBytes: 0,
    inactiveBytes: 0,
    compressedBytes: 0,
    appMemoryBytes: 0,
  );
}

/// One aggregated process entry in the "Top Memory" list. Processes sharing the
/// same command are summed; [pid] is a representative pid we can signal.
class MemoryProcess {
  const MemoryProcess({
    required this.name,
    required this.pid,
    required this.bytes,
  });

  final String name;
  final int pid;
  final int bytes;
}

/// Reads live memory state by parsing standard macOS command-line utilities.
/// Every parse is defensive: on any failure it degrades to empty data rather
/// than throwing, so the UI never sees an exception.
class MemoryService {
  const MemoryService();

  Future<int> _totalRam() async {
    try {
      final out = await Shell.out('sysctl', ['-n', 'hw.memsize']);
      return int.tryParse(out.trim()) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// The kernel's memory-pressure level (1/2/4), or 0 if unreadable.
  Future<int> _pressureLevel() async {
    try {
      final out = await Shell.out(
        'sysctl',
        ['-n', 'kern.memorystatus_vm_pressure_level'],
      );
      final v = int.tryParse(out.trim());
      if (v != null && (v == 1 || v == 2 || v == 4)) return v;
    } catch (_) {}
    return 0;
  }

  /// Parses `vm_stat` into an Activity-Monitor-accurate [MemorySnapshot].
  Future<MemorySnapshot> read() async {
    try {
      final total = await _totalRam();
      final pressure = await _pressureLevel();
      final out = await Shell.out('vm_stat', const []);
      if (out.trim().isEmpty) return MemorySnapshot.empty;

      var pageSize = 4096;
      final pageMatch = RegExp(r'page size of (\d+) bytes').firstMatch(out);
      if (pageMatch != null) {
        pageSize = int.tryParse(pageMatch.group(1)!) ?? 4096;
      }

      int pages(String label) {
        final re = RegExp('${RegExp.escape(label)}:\\s*(\\d+)\\.');
        final m = re.firstMatch(out);
        return m == null ? 0 : (int.tryParse(m.group(1)!) ?? 0);
      }

      int bytes(String label) => pages(label) * pageSize;

      final free = bytes('Pages free');
      final speculative = bytes('Pages speculative');
      final active = bytes('Pages active');
      final inactive = bytes('Pages inactive');
      final wired = bytes('Pages wired down');
      final compressed = bytes('Pages occupied by compressor');
      final anonymous = bytes('Anonymous pages');
      final purgeable = bytes('Pages purgeable');

      // App Memory ≈ anonymous − purgeable. Fall back to active on the rare
      // macOS build that omits the "Anonymous pages" line.
      var appMemory = anonymous - purgeable;
      if (anonymous <= 0) appMemory = active;
      if (appMemory < 0) appMemory = 0;

      return MemorySnapshot(
        totalBytes: total,
        freeBytes: free + speculative,
        wiredBytes: wired,
        activeBytes: active,
        inactiveBytes: inactive,
        compressedBytes: compressed,
        appMemoryBytes: appMemory,
        rawPressureLevel: pressure,
      );
    } catch (_) {
      return MemorySnapshot.empty;
    }
  }

  /// Top memory-consuming processes via `ps -axo pid=,rss=,comm=`. `rss` is in
  /// KB. Entries are aggregated by command (summed rss, first pid kept), sorted
  /// descending, and the top [limit] are returned.
  Future<List<MemoryProcess>> topProcesses({int limit = 12}) async {
    try {
      final out = await Shell.out('ps', const ['-axo', 'pid=,rss=,comm=']);
      if (out.trim().isEmpty) return const [];

      final byComm = <String, ({int pid, int rssKb})>{};
      for (final raw in out.split('\n')) {
        final line = raw.trimRight();
        if (line.trim().isEmpty) continue;
        final m = RegExp(r'^\s*(\d+)\s+(\d+)\s+(.*)$').firstMatch(line);
        if (m == null) continue;
        final pid = int.tryParse(m.group(1)!);
        final rssKb = int.tryParse(m.group(2)!);
        final comm = m.group(3)!.trim();
        if (pid == null || rssKb == null || comm.isEmpty || pid <= 0) continue;

        final existing = byComm[comm];
        byComm[comm] = existing == null
            ? (pid: pid, rssKb: rssKb)
            : (pid: existing.pid, rssKb: existing.rssKb + rssKb);
      }

      final list = byComm.entries
          .map((e) => MemoryProcess(
                name: _basename(e.key),
                pid: e.value.pid,
                bytes: e.value.rssKb * 1024,
              ))
          .toList()
        ..sort((a, b) => b.bytes.compareTo(a.bytes));

      return list.length > limit ? list.sublist(0, limit) : list;
    } catch (_) {
      return const [];
    }
  }

  String _basename(String comm) {
    final i = comm.lastIndexOf('/');
    final base = (i >= 0 && i < comm.length - 1) ? comm.substring(i + 1) : comm;
    return base.isEmpty ? comm : base;
  }
}
