import 'package:flutter/foundation.dart';

import '../models/startup_item.dart';
import '../services/startup_service.dart';

/// Drives the Startup tool: loads everything that launches at login/boot,
/// groups it by source for the UI, and removes the entries the user chooses.
class StartupController extends ChangeNotifier {
  StartupController() {
    load();
  }

  final StartupService _service = StartupService();

  bool _disposed = false;
  bool loading = true;
  List<StartupItem> items = const [];

  /// Items grouped in display order: login items, then user agents, then the
  /// read-only system entries (agents + daemons together).
  List<StartupItem> get loginItems =>
      [for (final i in items) if (i.kind == StartupKind.loginItem) i];

  List<StartupItem> get userAgents =>
      [for (final i in items) if (i.kind == StartupKind.userAgent) i];

  List<StartupItem> get systemItems => [
        for (final i in items)
          if (i.kind == StartupKind.systemAgent ||
              i.kind == StartupKind.systemDaemon)
            i
      ];

  int get totalCount => items.length;

  /// Loads (or reloads) every startup source.
  Future<void> load() async {
    loading = true;
    _safeNotify();
    try {
      items = await _service.load();
    } catch (_) {
      items = const [];
    } finally {
      loading = false;
      _safeNotify();
    }
  }

  /// User-facing refresh — same as [load].
  Future<void> refresh() => load();

  /// Removes one modifiable entry (login item or user agent). Returns true on
  /// success and drops it from the list. Read-only entries are ignored.
  Future<bool> remove(StartupItem item) async {
    if (!item.canModify) return false;

    bool ok;
    switch (item.kind) {
      case StartupKind.loginItem:
        ok = await _service.removeLoginItem(item.name);
        break;
      case StartupKind.userAgent:
        ok = await _service.removeUserAgent(item.path);
        break;
      case StartupKind.systemAgent:
      case StartupKind.systemDaemon:
        ok = false;
        break;
    }

    if (ok) {
      items = [for (final i in items) if (!identical(i, item)) i];
      _safeNotify();
    }
    return ok;
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
