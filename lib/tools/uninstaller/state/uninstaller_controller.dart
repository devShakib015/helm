import 'package:flutter/foundation.dart';

import '../../../core/services/native_bridge.dart';
import '../models/installed_app.dart';
import '../services/uninstaller_service.dart';

/// Drives the Uninstaller: lists installed apps, finds an app's leftovers when
/// it's selected, and moves the chosen items to the Trash.
class UninstallerController extends ChangeNotifier {
  UninstallerController() {
    loadApps();
  }

  final UninstallerService _service = UninstallerService();

  bool _disposed = false;

  /// All discovered apps, sorted largest-first.
  List<InstalledApp> apps = const [];

  /// Whether the initial app scan is running.
  bool loadingApps = true;

  /// The app the user has open in the detail pane (null = nothing selected).
  InstalledApp? selected;

  /// Leftovers for [selected]. Empty until they're loaded.
  List<Leftover> leftovers = const [];

  /// Whether the leftover lookup for [selected] is in flight.
  bool loadingLeftovers = false;

  /// Whether the app bundle itself is queued for removal (always true by
  /// default — uninstalling without removing the app makes little sense).
  bool appSelectedForRemoval = true;

  /// Whether a move-to-trash is currently running.
  bool uninstalling = false;

  // ---- Derived totals -----------------------------------------------------

  int get leftoversBytes => leftovers.fold(0, (s, l) => s + l.sizeBytes);

  /// App bundle + all of its leftovers, regardless of selection.
  int get totalBytes => (selected?.sizeBytes ?? 0) + leftoversBytes;

  /// Bytes the user has actually queued for removal.
  int get selectedBytes {
    var total = 0;
    if (appSelectedForRemoval) total += selected?.sizeBytes ?? 0;
    for (final l in leftovers) {
      if (l.selected) total += l.sizeBytes;
    }
    return total;
  }

  /// Number of items (app + leftovers) queued for removal.
  int get selectedCount {
    var count = appSelectedForRemoval && selected != null ? 1 : 0;
    for (final l in leftovers) {
      if (l.selected) count++;
    }
    return count;
  }

  // ---- Actions ------------------------------------------------------------

  Future<void> loadApps() async {
    loadingApps = true;
    _safeNotify();
    try {
      apps = await _service.listApps();
    } catch (_) {
      apps = const [];
    }
    loadingApps = false;
    _safeNotify();
  }

  Future<void> selectApp(InstalledApp app) async {
    selected = app;
    leftovers = const [];
    appSelectedForRemoval = true;
    loadingLeftovers = true;
    _safeNotify();

    List<Leftover> found;
    try {
      found = await _service.findLeftovers(app);
    } catch (_) {
      found = const [];
    }

    // Guard against a newer selection having superseded this one.
    if (selected?.path != app.path) return;
    leftovers = found;
    loadingLeftovers = false;
    _safeNotify();
  }

  void toggleApp(bool value) {
    appSelectedForRemoval = value;
    _safeNotify();
  }

  void toggleLeftover(Leftover leftover) {
    leftover.selected = !leftover.selected;
    _safeNotify();
  }

  /// Moves [selectedPaths] to the Trash, then removes the uninstalled app from
  /// the list and clears the detail pane. Returns the trashed/failed split.
  Future<({List<String> trashed, List<String> failed})> uninstall(
    List<String> selectedPaths,
  ) async {
    if (selectedPaths.isEmpty) {
      return (trashed: const <String>[], failed: const <String>[]);
    }
    uninstalling = true;
    _safeNotify();

    ({List<String> trashed, List<String> failed}) result;
    try {
      result = await NativeBridge.moveToTrash(selectedPaths);
    } catch (_) {
      result = (trashed: const <String>[], failed: selectedPaths);
    }

    final trashedSet = result.trashed.toSet();
    final removed = selected;

    // Drop trashed leftovers from the detail pane.
    leftovers = [
      for (final l in leftovers)
        if (!trashedSet.contains(l.path)) l,
    ];

    // If the app bundle itself was trashed, remove it from the master list and
    // close the detail pane.
    if (removed != null && trashedSet.contains(removed.path)) {
      apps = [
        for (final a in apps)
          if (a.path != removed.path) a,
      ];
      selected = null;
      leftovers = const [];
    }

    uninstalling = false;
    _safeNotify();
    return result;
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
