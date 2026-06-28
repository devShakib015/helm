import 'package:flutter/foundation.dart';

import '../../../core/models/file_entry.dart';
import '../../../core/services/deletion_service.dart';
import '../engine/large_old_finder.dart';
import '../engine/scan_session.dart';
import 'scan_state.dart';
import 'storage_controller.dart';

enum FileSort { sizeDesc, dateAsc, nameAsc }

enum AgeFilter { any, months3, months6, year1, year2 }

extension AgeFilterX on AgeFilter {
  String get label => switch (this) {
        AgeFilter.any => 'Any age',
        AgeFilter.months3 => '3+ months',
        AgeFilter.months6 => '6+ months',
        AgeFilter.year1 => '1+ year',
        AgeFilter.year2 => '2+ years',
      };

  Duration? get minAge => switch (this) {
        AgeFilter.any => null,
        AgeFilter.months3 => const Duration(days: 90),
        AgeFilter.months6 => const Duration(days: 182),
        AgeFilter.year1 => const Duration(days: 365),
        AgeFilter.year2 => const Duration(days: 730),
      };
}

class LargeFilesController extends ChangeNotifier {
  LargeFilesController(this._storage);
  final StorageController _storage;

  final LargeFileFinder _finder = LargeFileFinder();
  final DeletionService _deleter = DeletionService();

  ScanState state = ScanState.idle;
  ScanProgress progress = const ScanProgress();
  List<FileEntry> _files = const [];
  final Set<String> _selected = {};
  ScanSession<List<FileEntry>>? _session;

  int minBytes = 100 * 1000 * 1000; // 100 MB
  FileSort sort = FileSort.sizeDesc;
  AgeFilter ageFilter = AgeFilter.any;

  bool get isScanning => state == ScanState.scanning;
  bool get hasResults => _files.isNotEmpty;
  int get totalFound => _files.length;

  List<FileEntry> get files {
    final minAge = ageFilter.minAge;
    final now = DateTime.now();
    var list = _files.where((f) {
      if (minAge == null) return true;
      final m = f.modified;
      if (m == null) return false;
      return now.difference(m) >= minAge;
    }).toList();
    switch (sort) {
      case FileSort.sizeDesc:
        list.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
      case FileSort.dateAsc:
        list.sort((a, b) => (a.modifiedMs ?? 0).compareTo(b.modifiedMs ?? 0));
      case FileSort.nameAsc:
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return list;
  }

  bool isSelected(String path) => _selected.contains(path);
  int get selectedCount => _selected.length;
  int get selectedBytes =>
      _files.where((f) => _selected.contains(f.path)).fold(0, (s, f) => s + f.sizeBytes);

  Future<void> scan({int? minBytes}) async {
    if (state == ScanState.scanning) return;
    if (minBytes != null) this.minBytes = minBytes;
    _files = const [];
    _selected.clear();
    progress = ScanProgress.start();
    state = ScanState.scanning;
    notifyListeners();

    final session = _finder.start(minBytes: this.minBytes);
    _session = session;
    final sub = session.ticks.listen((tick) {
      progress = progress.add(tick);
      notifyListeners();
    });

    try {
      final result = await session.result;
      await sub.cancel();
      if (state == ScanState.cancelled) return;
      _files = result;
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

  void selectVisible() {
    _selected.addAll(files.map((f) => f.path));
    notifyListeners();
  }

  void clearSelection() {
    _selected.clear();
    notifyListeners();
  }

  void setSort(FileSort value) {
    sort = value;
    notifyListeners();
  }

  void setAgeFilter(AgeFilter value) {
    ageFilter = value;
    notifyListeners();
  }

  Future<DeletionResult> deleteSelected() async {
    final paths = _files
        .where((f) => _selected.contains(f.path))
        .map((f) => f.path)
        .toList();
    final res = await _deleter.moveToTrash(paths);
    final removed = res.removed.toSet();
    _files = [for (final f in _files) if (!removed.contains(f.path)) f];
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
