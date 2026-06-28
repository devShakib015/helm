import 'package:flutter/foundation.dart';

import '../../../core/models/duplicate_set.dart';
import '../../../core/services/deletion_service.dart';
import '../engine/duplicate_finder.dart';
import '../engine/scan_session.dart';
import 'scan_state.dart';
import 'storage_controller.dart';

class DuplicatesController extends ChangeNotifier {
  DuplicatesController(this._storage);
  final StorageController _storage;

  final DuplicateFinder _finder = DuplicateFinder();
  final DeletionService _deleter = DeletionService();

  ScanState state = ScanState.idle;
  ScanProgress progress = const ScanProgress();
  List<DuplicateSet> sets = const [];

  /// Paths the user has marked for removal. Helm never lets every copy in a set
  /// be selected at once — at least one always survives.
  final Set<String> _selected = {};
  ScanSession<List<DuplicateSet>>? _session;

  bool get isScanning => state == ScanState.scanning;
  bool get hasResults => sets.isNotEmpty;

  int get totalSets => sets.length;
  int get totalReclaimable => sets.fold(0, (s, d) => s + d.reclaimableBytes);

  bool isSelected(String path) => _selected.contains(path);
  int get selectedCount => _selected.length;
  int get selectedBytes {
    var sum = 0;
    for (final set in sets) {
      for (final f in set.files) {
        if (_selected.contains(f.path)) sum += f.sizeBytes;
      }
    }
    return sum;
  }

  Future<void> scan() async {
    if (state == ScanState.scanning) return;
    sets = const [];
    _selected.clear();
    progress = ScanProgress.start();
    state = ScanState.scanning;
    notifyListeners();

    final session = _finder.start();
    _session = session;
    final sub = session.ticks.listen((tick) {
      progress = progress.add(tick);
      notifyListeners();
    });

    try {
      final result = await session.result;
      await sub.cancel();
      if (state == ScanState.cancelled) return;
      sets = result;
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

  void toggle(String path) {
    if (!_selected.remove(path)) _selected.add(path);
    notifyListeners();
  }

  /// Smart pick: in every set keep the oldest copy (the likely original) and
  /// mark the rest for removal.
  void autoSelect() {
    _selected.clear();
    for (final set in sets) {
      final ordered = [...set.files]
        ..sort((a, b) => (a.modifiedMs ?? 0).compareTo(b.modifiedMs ?? 0));
      for (var i = 1; i < ordered.length; i++) {
        _selected.add(ordered[i].path);
      }
    }
    notifyListeners();
  }

  void clearSelection() {
    _selected.clear();
    notifyListeners();
  }

  /// Returns the paths to delete, guaranteeing at least one survivor per set.
  List<String> _safeDeletionPaths() {
    final paths = <String>[];
    for (final set in sets) {
      final selectedInSet =
          set.files.where((f) => _selected.contains(f.path)).toList();
      // If the user somehow selected every copy, spare the first one.
      if (selectedInSet.length >= set.files.length && set.files.isNotEmpty) {
        selectedInSet.removeWhere((f) => f.path == set.files.first.path);
      }
      paths.addAll(selectedInSet.map((f) => f.path));
    }
    return paths;
  }

  Future<DeletionResult> deleteSelected() async {
    final paths = _safeDeletionPaths();
    final res = await _deleter.moveToTrash(paths);
    final removed = res.removed.toSet();

    final next = <DuplicateSet>[];
    for (final set in sets) {
      final remaining =
          set.files.where((f) => !removed.contains(f.path)).toList();
      if (remaining.length >= 2) {
        next.add(DuplicateSet(
            hash: set.hash, sizeBytes: set.sizeBytes, files: remaining));
      }
    }
    sets = next;
    _selected.removeAll(removed);

    await _storage.refreshVolume();
    _storage.markStale();
    notifyListeners();
    return res;
  }

  @override
  void dispose() {
    _session?.cancel();
    super.dispose();
  }
}
