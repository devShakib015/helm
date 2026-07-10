import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../core/models/snapshot_info.dart';
import '../../../core/models/storage_category.dart';
import '../../../core/models/volume_info.dart';
import '../../../core/services/deletion_service.dart';
import '../../../core/services/native_system.dart';
import '../../../core/services/permissions_service.dart';
import '../../../core/services/system_info_service.dart';
import '../engine/category_scanner.dart';
import '../engine/scan_session.dart';
import 'scan_state.dart';

/// Owns the storage overview: volume capacity, APFS snapshots, Full Disk Access
/// status, and the category breakdown scan. The single source of truth for
/// "how full is the disk", which the other storage controllers refresh after
/// they delete things.
class StorageController extends ChangeNotifier with WidgetsBindingObserver {
  StorageController() {
    // Re-probe Full Disk Access whenever the app returns to the foreground —
    // that's exactly when the user comes back from System Settings after
    // flipping the toggle.
    WidgetsBinding.instance.addObserver(this);
  }

  final SystemInfoService _sys = SystemInfoService();
  final PermissionsService _perm = PermissionsService();
  final DeletionService _deleter = DeletionService();
  final CategoryScanner _scanner = CategoryScanner();

  VolumeInfo volume = VolumeInfo.empty;
  List<SnapshotInfo> snapshots = const [];
  FdaStatus fda = FdaStatus.unknown;
  bool fdaDismissed = false;

  ScanState state = ScanState.idle;
  ScanProgress progress = const ScanProgress();
  List<StorageCategory> categories = const [];
  StorageCategory? selected;

  /// True when results are older than the on-disk reality (after a deletion).
  bool stale = false;

  ScanSession<List<StorageCategory>>? _session;
  StreamSubscription<ScanTick>? _ticksSub;
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool get isScanning => state == ScanState.scanning;
  bool get hasResults => categories.isNotEmpty;

  StorageCategory? categoryOf(CategoryKind kind) {
    for (final c in categories) {
      if (c.kind == kind) return c;
    }
    return null;
  }

  Future<void> init() async {
    fda = await _perm.checkFullDiskAccess();
    await refreshVolume();
  }

  Future<void> refreshVolume() async {
    volume = await _sys.bootVolume();
    snapshots = await _sys.localSnapshots();
    notifyListeners();
  }

  Future<void> recheckPermissions() async {
    fda = await _perm.checkFullDiskAccess();
    _notify();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) recheckPermissions();
  }

  void dismissFdaBanner() {
    fdaDismissed = true;
    notifyListeners();
  }

  void openFdaSettings() => _perm.openFullDiskAccessSettings();

  /// macOS applies a fresh Full Disk Access grant only to newly-launched
  /// processes, so "I granted it but Helm still says limited" is fixed by a
  /// relaunch. This spawns a new instance and quits this one.
  void relaunchApp() => NativeSystem.relaunchApp();

  void markStale() {
    stale = true;
    notifyListeners();
  }

  Future<void> startScan() async {
    if (state == ScanState.scanning) return;
    categories = const [];
    selected = null;
    stale = false;
    progress = ScanProgress.start();
    state = ScanState.scanning;
    notifyListeners();

    final session = _scanner.start();
    _session = session;
    _ticksSub = session.ticks.listen((tick) {
      if (_disposed) return;
      progress = progress.add(tick);
      _notify();
    });

    try {
      final cats = await session.result;
      if (state == ScanState.cancelled) return;
      categories = _withDerivedSystemData(cats);
      state = ScanState.done;
    } on ScanCancelled {
      // Expected — state was already set by cancelScan().
    } catch (_) {
      if (state != ScanState.cancelled) state = ScanState.error;
    } finally {
      await _ticksSub?.cancel();
      _ticksSub = null;
      progress = progress.finish();
      _session = null;
      _notify();
    }
  }

  /// Appends a "System Data" slice for everything used on disk that isn't in a
  /// tangible category — mirroring how macOS itself accounts for the remainder.
  List<StorageCategory> _withDerivedSystemData(List<StorageCategory> cats) {
    final known = cats.fold<int>(0, (s, c) => s + c.sizeBytes);
    // Reconcile against occupied space (used + purgeable) because the scanners
    // sum real on-disk sizes, which include cache/snapshot bytes macOS reports
    // as purgeable. Using usedBytes here would understate (often go negative).
    final remainder = volume.occupiedBytes - known;
    final list = [...cats];
    if (remainder > 1000 * 1000) {
      list.add(StorageCategory(
        kind: CategoryKind.systemData,
        sizeBytes: remainder,
        itemCount: 0,
        paths: const [],
      ));
    }
    list.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    return list;
  }

  void cancelScan() {
    if (state != ScanState.scanning) return;
    state = ScanState.cancelled;
    _session?.cancel();
    _session = null;
    progress = progress.finish();
    notifyListeners();
  }

  void select_(StorageCategory? c) {
    selected = c;
    notifyListeners();
  }

  Future<DeletionResult> trashPaths(List<String> paths) async {
    final res = await _deleter.moveToTrash(paths);
    if (res.removed.isNotEmpty) markStale();
    await refreshVolume();
    return res;
  }

  Future<bool> thinSnapshots() async {
    final ok = await _sys.thinLocalSnapshots();
    await refreshVolume();
    return ok;
  }

  void revealInFinder(String path) => _sys.revealInFinder(path);
  void openPath(String path) => _sys.openPath(path);

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _ticksSub?.cancel();
    _session?.cancel();
    super.dispose();
  }
}
