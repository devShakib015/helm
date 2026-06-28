import 'package:flutter/foundation.dart';

import '../../../core/services/native_bridge.dart';
import '../models/trace_group.dart';
import '../services/privacy_service.dart';

/// Drives the Privacy tool: scans for the traces macOS leaves behind, tracks
/// the user's selection, and clears (Trashes) what they pick. Safe groups are
/// pre-selected; caution groups (history, shell logs) start unchecked.
class PrivacyController extends ChangeNotifier {
  PrivacyController() {
    scan();
  }

  bool _disposed = false;

  /// True while the initial scan is running.
  bool scanning = true;

  List<TraceGroup> groups = const [];

  bool get hasResults => groups.isNotEmpty;

  int get totalBytes => groups.fold(0, (s, g) => s + g.totalBytes);
  int get selectedBytes => groups.fold(0, (s, g) => s + g.selectedBytes);
  int get selectedCount => groups.fold(0, (s, g) => s + g.selectedCount);

  Future<void> scan() async {
    scanning = true;
    _safeNotify();
    try {
      groups = await PrivacyService.scan();
    } catch (_) {
      groups = const [];
    } finally {
      scanning = false;
      _safeNotify();
    }
  }

  void toggleItem(TraceItem item) {
    item.selected = !item.selected;
    _safeNotify();
  }

  void setGroup(TraceGroup group, bool value) {
    group.selectAll(value);
    _safeNotify();
  }

  void clearSelection() {
    for (final g in groups) {
      g.selectAll(false);
    }
    _safeNotify();
  }

  /// Moves every selected trace to the Trash (recoverable), drops the cleared
  /// items, and prunes groups that end up empty. Returns how many were trashed
  /// and how many failed (typically: need Full Disk Access).
  Future<({int trashed, int failed})> clearSelected() async {
    final paths = <String>[
      for (final g in groups)
        for (final item in g.items)
          if (item.selected) item.path,
    ];
    if (paths.isEmpty) return (trashed: 0, failed: 0);

    final res = await NativeBridge.moveToTrash(paths);
    final removed = res.trashed.toSet();

    for (final g in groups) {
      g.items.removeWhere((i) => removed.contains(i.path));
    }
    groups = [for (final g in groups) if (!g.isEmpty) g];
    _safeNotify();

    return (trashed: res.trashed.length, failed: res.failed.length);
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
