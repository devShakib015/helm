import 'dart:io';

import '../../../core/services/native_bridge.dart';
import '../../../core/services/shell.dart';
import '../../../core/utils/mac_paths.dart';
import '../models/startup_item.dart';

/// Reads (and modifies) the things macOS launches automatically: classic
/// Login Items, per-user LaunchAgents, and the read-only system
/// LaunchAgents / LaunchDaemons. Everything is gathered by parsing the output
/// of stock CLI tools — no extra packages, no native code beyond the shared
/// Trash bridge.
class StartupService {
  /// Loads every startup entry across all sources. Each source is wrapped so a
  /// failure in one (e.g. System Events not responding) never blocks the rest.
  Future<List<StartupItem>> load() async {
    final results = await Future.wait([
      _loginItems(),
      _userAgents(),
      _systemEntries(
        '/Library/LaunchAgents',
        StartupKind.systemAgent,
      ),
      _systemEntries(
        '/Library/LaunchDaemons',
        StartupKind.systemDaemon,
      ),
    ]);
    return [for (final list in results) ...list];
  }

  // ---- Login Items --------------------------------------------------------

  Future<List<StartupItem>> _loginItems() async {
    try {
      final namesRaw = await Shell.out('osascript', [
        '-e',
        'tell application "System Events" to get the name of every login item',
      ]);
      final pathsRaw = await Shell.out('osascript', [
        '-e',
        'tell application "System Events" to get the path of every login item',
      ]);

      final names = _splitList(namesRaw);
      final paths = _splitList(pathsRaw);
      if (names.isEmpty) return const [];

      return [
        for (var i = 0; i < names.length; i++)
          StartupItem(
            name: names[i],
            path: i < paths.length ? paths[i] : '',
            kind: StartupKind.loginItem,
            enabled: true,
            canModify: true,
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  // ---- User LaunchAgents --------------------------------------------------

  Future<List<StartupItem>> _userAgents() async {
    final dir = Directory('${MacPaths.home}/Library/LaunchAgents');
    final plists = await _plistsIn(dir);
    final items = <StartupItem>[];

    for (final file in plists) {
      try {
        final base = _basename(file.path);
        final noExt = file.path.endsWith('.plist')
            ? file.path.substring(0, file.path.length - '.plist'.length)
            : file.path;

        var label = (await Shell.out('defaults', ['read', noExt, 'Label']))
            .trim();
        if (label.isEmpty) label = base;

        // `Disabled` key — `1`/`true` means the agent won't run.
        final disabledRaw =
            (await Shell.out('defaults', ['read', noExt, 'Disabled']))
                .trim()
                .toLowerCase();
        final disabled = disabledRaw == '1' || disabledRaw == 'true';

        items.add(StartupItem(
          name: label,
          path: file.path,
          kind: StartupKind.userAgent,
          enabled: !disabled,
          canModify: true,
        ));
      } catch (_) {
        // Skip an unreadable plist rather than failing the whole list.
      }
    }
    return items;
  }

  // ---- System agents & daemons (read-only) --------------------------------

  Future<List<StartupItem>> _systemEntries(
    String path,
    StartupKind kind,
  ) async {
    final plists = await _plistsIn(Directory(path));
    final items = <StartupItem>[];

    for (final file in plists) {
      try {
        final base = _basename(file.path);
        final noExt = file.path.endsWith('.plist')
            ? file.path.substring(0, file.path.length - '.plist'.length)
            : file.path;

        var label =
            (await Shell.out('defaults', ['read', noExt, 'Label'])).trim();
        if (label.isEmpty) label = base;

        items.add(StartupItem(
          name: label,
          path: file.path,
          kind: kind,
          enabled: true,
          canModify: false,
        ));
      } catch (_) {
        // Ignore individual failures.
      }
    }
    return items;
  }

  // ---- Mutations ----------------------------------------------------------

  /// Deletes a classic login item by name via System Events. Returns true on
  /// success.
  Future<bool> removeLoginItem(String name) async {
    try {
      final escaped = name.replaceAll('"', '\\"');
      final r = await Shell.run('osascript', [
        '-e',
        'tell application "System Events" to delete login item "$escaped"',
      ]);
      return r.code == 0;
    } catch (_) {
      return false;
    }
  }

  /// Unloads a user LaunchAgent then moves its plist to the Trash (recoverable).
  /// Returns true if the plist was trashed.
  Future<bool> removeUserAgent(String path) async {
    try {
      // Best-effort unload so the agent stops immediately; ignore its result
      // because the plist removal is what actually disables it for next login.
      await Shell.run('launchctl', ['unload', path]);
      final res = await NativeBridge.moveToTrash([path]);
      return res.trashed.contains(path);
    } catch (_) {
      return false;
    }
  }

  // ---- Helpers ------------------------------------------------------------

  /// AppleScript returns lists as comma-and-space separated text. Splits and
  /// trims, dropping empties.
  List<String> _splitList(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const [];
    return [
      for (final part in trimmed.split(', '))
        if (part.trim().isNotEmpty) part.trim(),
    ];
  }

  Future<List<File>> _plistsIn(Directory dir) async {
    try {
      if (!await dir.exists()) return const [];
      final entries = await dir.list(followLinks: false).toList();
      return [
        for (final e in entries)
          if (e is File && e.path.endsWith('.plist')) e,
      ]..sort((a, b) => _basename(a.path)
          .toLowerCase()
          .compareTo(_basename(b.path).toLowerCase()));
    } catch (_) {
      return const [];
    }
  }

  String _basename(String path) {
    final i = path.lastIndexOf('/');
    return i >= 0 ? path.substring(i + 1) : path;
  }
}
