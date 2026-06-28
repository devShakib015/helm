import 'package:flutter/foundation.dart';

import '../../../core/models/cleanable_group.dart';
import '../../../core/services/deletion_service.dart';
import '../engine/junk_scanner.dart';
import '../engine/scan_session.dart';
import 'scan_state.dart';
import 'storage_controller.dart';

/// Drives the junk cleaner: scanning for reclaimable groups, tracking the
/// user's selection, and removing what they pick.
class CleanerController extends ChangeNotifier {
  CleanerController(this._storage);
  final StorageController _storage;

  final JunkScanner _scanner = JunkScanner();
  final DeletionService _deleter = DeletionService();

  ScanState state = ScanState.idle;
  ScanProgress progress = const ScanProgress();
  List<CleanableGroup> groups = const [];
  ScanSession<List<CleanableGroup>>? _session;

  bool get isScanning => state == ScanState.scanning;
  bool get hasResults => groups.isNotEmpty;

  int get totalBytes => groups.fold(0, (s, g) => s + g.totalBytes);
  int get selectedBytes => groups.fold(0, (s, g) => s + g.selectedBytes);
  int get selectedCount => groups.fold(0, (s, g) => s + g.selectedCount);

  Future<void> scan() async {
    if (state == ScanState.scanning) return;
    groups = const [];
    progress = ScanProgress.start();
    state = ScanState.scanning;
    notifyListeners();

    final session = _scanner.start();
    _session = session;
    final sub = session.ticks.listen((tick) {
      progress = progress.add(tick);
      notifyListeners();
    });

    try {
      final result = await session.result;
      await sub.cancel();
      if (state == ScanState.cancelled) return;
      groups = result;
      state = ScanState.done;
    } catch (_) {
      await sub.cancel();
      if (state != ScanState.cancelled) state = ScanState.error;
    } finally {
      progress = progress.finish();
      _session = null;
      notifyListeners();
    }
  }

  void cancel() {
    if (state != ScanState.scanning) return;
    state = ScanState.cancelled;
    _session?.cancel();
    _session = null;
    notifyListeners();
  }

  void toggleItem(CleanableItem item) {
    item.selected = !item.selected;
    notifyListeners();
  }

  void setGroup(CleanableGroup group, bool value) {
    group.selectAll(value);
    notifyListeners();
  }

  void selectAllSafe() {
    for (final g in groups) {
      g.selectAll(g.risk == CleanupRisk.safe);
    }
    notifyListeners();
  }

  void clearSelection() {
    for (final g in groups) {
      g.selectAll(false);
    }
    notifyListeners();
  }

  /// Removes everything selected. The Trash group is emptied permanently (its
  /// items are already discarded); everything else moves to the Trash so it's
  /// recoverable.
  Future<DeletionResult> cleanSelected() async {
    final trashPaths = <String>[];
    final permanentPaths = <String>[];
    for (final g in groups) {
      for (final item in g.items) {
        if (!item.selected) continue;
        if (g.kind == CleanupKind.trash) {
          permanentPaths.add(item.path);
        } else {
          trashPaths.add(item.path);
        }
      }
    }

    final r1 = await _deleter.moveToTrash(trashPaths);
    final r2 = await _deleter.deletePermanently(permanentPaths);
    final removed = {...r1.removed, ...r2.removed};

    for (final g in groups) {
      g.items.removeWhere((i) => removed.contains(i.path));
    }
    groups = [for (final g in groups) if (!g.isEmpty) g];

    await _storage.refreshVolume();
    _storage.markStale();
    notifyListeners();

    return DeletionResult(
      removed: [...r1.removed, ...r2.removed],
      failed: [...r1.failed, ...r2.failed],
    );
  }

  @override
  void dispose() {
    _session?.cancel();
    super.dispose();
  }
}
