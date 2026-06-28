import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/services/shell.dart';
import '../services/memory_service.dart';

/// Outcome of a "Free Up Memory" purge, used by the UI to compose a SnackBar.
class FreeResult {
  const FreeResult({required this.ok, required this.reclaimedBytes});
  final bool ok;

  /// freeBytes(after) - freeBytes(before); may be <= 0 if nothing was reclaimed.
  final int reclaimedBytes;
}

/// Drives the Memory tool: polls live RAM stats every 3 seconds, exposes the
/// current snapshot + top processes, and runs the actions (purge inactive
/// memory, quit a process). Self-loads in its constructor.
class MemoryController extends ChangeNotifier {
  MemoryController() {
    refresh();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => refresh());
  }

  final MemoryService _service = const MemoryService();

  Timer? _timer;
  bool _disposed = false;
  bool _loading = false;

  MemorySnapshot snapshot = MemorySnapshot.empty;
  List<MemoryProcess> processes = const [];

  /// True until the first poll completes.
  bool loaded = false;

  /// True while a "Free Up Memory" purge is in flight.
  bool freeing = false;

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  /// Re-reads memory stats and the top process list.
  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    try {
      final results = await Future.wait([
        _service.read(),
        _service.topProcesses(),
      ]);
      if (_disposed) return;
      snapshot = results[0] as MemorySnapshot;
      processes = results[1] as List<MemoryProcess>;
      loaded = true;
      _safeNotify();
    } catch (_) {
      // Degrade gracefully — keep whatever we last had.
      loaded = true;
      _safeNotify();
    } finally {
      _loading = false;
    }
  }

  /// Frees inactive memory via `purge`, escalating to an admin prompt if the
  /// unprivileged call fails. Returns how much free memory was reclaimed so the
  /// caller can surface it.
  Future<FreeResult> freeMemory() async {
    if (freeing) return const FreeResult(ok: false, reclaimedBytes: 0);
    freeing = true;
    _safeNotify();

    final beforeFree = snapshot.freeBytes;
    var ok = false;
    try {
      final r = await Shell.run('purge', const []);
      ok = r.code == 0;
      if (!ok) {
        ok = await Shell.runAsAdmin(
          'purge',
          prompt: 'Helm needs permission to free inactive memory',
        );
      }
    } catch (_) {
      ok = false;
    }

    // Re-read so the gauge + tiles reflect the post-purge reality.
    await refresh();
    freeing = false;
    _safeNotify();

    final reclaimed = snapshot.freeBytes - beforeFree;
    return FreeResult(ok: ok, reclaimedBytes: reclaimed);
  }

  /// Sends SIGTERM to a process by pid (graceful quit). Returns true on success.
  /// The caller is responsible for confirming with the user first.
  Future<bool> quitProcess(int pid) async {
    if (pid <= 0) return false;
    var ok = false;
    try {
      final r = await Shell.run('kill', ['$pid']);
      ok = r.code == 0;
    } catch (_) {
      ok = false;
    }
    await refresh();
    return ok;
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
