import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/services/shell.dart';
import '../../../core/utils/mac_paths.dart';
import '../../../core/utils/native_stat.dart';
import '../models/installed_app.dart';

/// Reads the list of installed applications and finds the scattered support
/// files each one leaves behind. Everything here is read-only — actual removal
/// goes through `NativeBridge.moveToTrash` in the controller.
class UninstallerService {
  /// Scans `/Applications` and `~/Applications` for `.app` bundles, resolves
  /// each one's bundle identifier and size, and returns them sorted by size
  /// (largest first). Sizing runs concurrently but capped to avoid spawning
  /// hundreds of `du` processes at once.
  Future<List<InstalledApp>> listApps() async {
    final bundles = <String>[];
    for (final dir in [MacPaths.systemApplications, MacPaths.userApplications]) {
      bundles.addAll(_appBundlesIn(dir));
    }

    final apps = await _mapCapped<String, InstalledApp?>(
      bundles,
      _describeApp,
      concurrency: 8,
    );

    final result = [
      for (final a in apps) ?a,
    ]..sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    return result;
  }

  /// Lists the immediate `.app` bundle paths inside [dir] that Helm could
  /// actually uninstall. Returns an empty list if the directory is missing or
  /// unreadable.
  ///
  /// The name ending in `.app` was the only test, and it let through three
  /// things that are not removable applications:
  ///
  ///   * **Symlinks.** `/Applications/Safari.app` is one — a link into
  ///     `/System/Cryptexes`, on the read-only system volume. It listed at 0 B,
  ///     and picking it offered a removal that could never succeed. Even where
  ///     the target is real, trashing a link removes the shortcut and leaves
  ///     the app, which is not what "uninstall" means.
  ///   * **Folders that merely end in `.app`.** Without `Contents/Info.plist`
  ///     there is no bundle id, so no leftover can be matched to it and the
  ///     entry can only ever offer to delete itself.
  ///   * **Anything the system has locked.** SIP-restricted, system-immutable
  ///     or un-unlinkable items cannot be removed by anyone short of booting
  ///     into Recovery — see [FileFacts.isSystemLocked].
  ///
  /// Filtering here rather than at removal time is deliberate: the Uninstaller
  /// now explains a refusal properly, but the better outcome is not to offer
  /// something that was never going to work.
  List<String> _appBundlesIn(String dir) {
    try {
      final d = Directory(dir);
      if (!d.existsSync()) return const [];
      final out = <String>[];
      for (final entry in d.listSync(followLinks: false)) {
        if (!entry.path.endsWith('.app')) continue;
        // listSync(followLinks: false) yields a Link for a symlink, so this
        // rejects Safari without a separate symlink test.
        if (entry is! Directory) continue;
        if (!File('${entry.path}/Contents/Info.plist').existsSync()) continue;
        final facts = factsFor(entry.path);
        if (facts != null && facts.isSystemLocked) continue;
        out.add(entry.path);
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<InstalledApp?> _describeApp(String appPath) async {
    try {
      final base = _baseName(appPath);
      final name = base.endsWith('.app')
          ? base.substring(0, base.length - 4)
          : base;
      final bundleId = await _bundleId(appPath);
      final size = await _duSize(appPath);
      return InstalledApp(
        name: name,
        path: appPath,
        bundleId: bundleId,
        sizeBytes: size,
      );
    } catch (_) {
      return null;
    }
  }

  Future<String> _bundleId(String appPath) async {
    try {
      final out = await Shell.out(
        'defaults',
        ['read', '$appPath/Contents/Info', 'CFBundleIdentifier'],
      );
      return out.trim();
    } catch (_) {
      return '';
    }
  }

  /// Size in bytes via `du -sk` (reports KiB blocks; multiply by 1024).
  Future<int> _duSize(String path) async {
    try {
      final out = await Shell.out('du', ['-sk', path]);
      final token = out.trim().split(RegExp(r'\s+')).first;
      final kb = int.tryParse(token) ?? 0;
      return kb * 1024;
    } catch (_) {
      return 0;
    }
  }

  /// Finds the leftover files associated with [app] across the standard macOS
  /// support locations. Matching is intentionally strict: a candidate's name
  /// (lowercased) must either start with the bundle id or contain the app's
  /// base name with spaces removed.
  Future<List<Leftover>> findLeftovers(
    InstalledApp app, {
    List<InstalledApp> installed = const [],
  }) async {
    final bundleId = usableBundleId(app.bundleId);
    final appKey = app.name.toLowerCase().replaceAll(' ', '');
    final home = MacPaths.home;

    // Bundle ids of the OTHER apps still installed. Sibling releases share a
    // prefix (Chrome / Chrome Beta, VS Code / VS Code Insiders), so a folder
    // one of them claims more specifically belongs to it — not to this app.
    // Without this, uninstalling Chrome would offer to delete Chrome Beta's
    // profile while Beta is still installed and in use.
    final others = <String>[
      for (final o in installed)
        if (o.path != app.path && usableBundleId(o.bundleId).isNotEmpty)
          usableBundleId(o.bundleId),
    ];

    final found = <_Candidate>[];
    final seen = <String>{};

    void add(String path, String name, String category) {
      if (seen.add(path)) {
        found.add(_Candidate(path: path, name: name, category: category));
      }
    }

    final letter = RegExp(r'[a-z]');
    bool matches(String childName) {
      final lower = childName.toLowerCase();
      // Strongest signal: a reverse-DNS name beginning with the bundle id —
      // but only at a segment boundary, and only when no sibling app claims
      // it more specifically.
      if (bundleId.isNotEmpty && bundlePrefix(lower, bundleId)) {
        for (final other in others) {
          if (other.length > bundleId.length && bundlePrefix(lower, other)) {
            return false; // belongs to that still-installed app
          }
        }
        return true;
      }
      if (appKey.length < 3) return false;
      // Name match must be at a token boundary, never a loose substring — else
      // a short app like "Arc" wrongly matches "seArch"/"theunArchiver". Accept
      // an exact name, or "<name>" followed by a non-letter (e.g. "arc.", "arc-").
      final childKey = lower.replaceAll(' ', '');
      if (childKey == appKey) return true;
      if (childKey.startsWith(appKey)) {
        final next = childKey.length > appKey.length ? childKey[appKey.length] : '';
        if (next.isEmpty || !letter.hasMatch(next)) return true;
      }
      return false;
    }

    // Directories whose immediate children we scan with the generic matcher.
    final scanDirs = <({String dir, String category})>[
      (dir: MacPaths.userAppSupport, category: 'Support'),
      (dir: MacPaths.userCaches, category: 'Caches'),
      (dir: MacPaths.userContainers, category: 'Container'),
      (dir: MacPaths.userGroupContainers, category: 'Group Container'),
      (dir: MacPaths.userLogs, category: 'Logs'),
      (dir: '$home/Library/HTTPStorages', category: 'HTTP Storage'),
      (dir: '$home/Library/WebKit', category: 'WebKit'),
    ];

    for (final spec in scanDirs) {
      for (final child in _children(spec.dir)) {
        if (matches(child.name)) {
          add(child.path, child.name, spec.category);
        }
      }
    }

    // Preferences: a single `<bundleid>.plist` file.
    if (bundleId.isNotEmpty) {
      final pref = '${MacPaths.userPreferences}/$bundleId.plist';
      if (_exists(pref)) {
        add(pref, '$bundleId.plist', 'Preferences');
      }
    }

    // Saved Application State: `<bundleid>.savedState`.
    if (bundleId.isNotEmpty) {
      final saved = '${MacPaths.savedAppState}/$bundleId.savedState';
      if (_exists(saved)) {
        add(saved, '$bundleId.savedState', 'Saved State');
      }
    }

    // Cookies: `<bundleid>.binarycookies`.
    if (bundleId.isNotEmpty) {
      final cookie = '$home/Library/Cookies/$bundleId.binarycookies';
      if (_exists(cookie)) {
        add(cookie, '$bundleId.binarycookies', 'Cookies');
      }
    }

    // LaunchAgents: plists whose name contains the bundle id.
    if (bundleId.isNotEmpty) {
      for (final child in _children('$home/Library/LaunchAgents')) {
        final lower = child.name.toLowerCase();
        if (lower.endsWith('.plist') && lower.contains(bundleId)) {
          add(child.path, child.name, 'Launch Agent');
        }
      }
    }

    // Size everything concurrently (capped).
    final sized = await _mapCapped<_Candidate, Leftover>(
      found,
      (c) async => Leftover(
        path: c.path,
        name: c.name,
        sizeBytes: await _duSize(c.path),
        category: c.category,
      ),
      concurrency: 8,
    );

    sized.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    return sized;
  }

  /// A bundle id is only trustworthy as a match key when it is a real
  /// reverse-DNS identifier. A stub like "com" or "a" would prefix-match a
  /// huge share of the user's Library, so such ids are discarded and matching
  /// falls back to the (much stricter) app-name rule.
  @visibleForTesting
  static String usableBundleId(String raw) {
    final b = raw.trim().toLowerCase();
    if (b.length < 6 || !b.contains('.')) return '';
    if (b.split('.').where((p) => p.isNotEmpty).length < 2) return '';
    return b;
  }

  /// True when [name] is [bundleId] itself, or sits under it at a segment
  /// boundary: "com.acme.app" matches "com.acme.app.helper" but never
  /// "com.acme.applesauce" (a different app that merely shares a prefix).
  @visibleForTesting
  static bool bundlePrefix(String name, String bundleId) {
    if (!name.startsWith(bundleId)) return false;
    if (name.length == bundleId.length) return true;
    final next = name[bundleId.length];
    return next == '.' || next == '-' || next == '_' || next == ' ';
  }

  /// Immediate children of [dir] as (path, name) records. Empty on failure.
  List<({String path, String name})> _children(String dir) {
    try {
      final d = Directory(dir);
      if (!d.existsSync()) return const [];
      return [
        for (final e in d.listSync(followLinks: false))
          (path: e.path, name: _baseName(e.path)),
      ];
    } catch (_) {
      return const [];
    }
  }

  bool _exists(String path) {
    try {
      return File(path).existsSync() || Directory(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  String _baseName(String path) {
    final trimmed =
        path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final i = trimmed.lastIndexOf('/');
    return i == -1 ? trimmed : trimmed.substring(i + 1);
  }

  /// Maps [items] through [task] with at most [concurrency] in flight at once.
  Future<List<R>> _mapCapped<T, R>(
    List<T> items,
    Future<R> Function(T) task, {
    required int concurrency,
  }) async {
    final results = List<R?>.filled(items.length, null);
    var next = 0;

    Future<void> worker() async {
      while (true) {
        final i = next;
        if (i >= items.length) return;
        next++;
        results[i] = await task(items[i]);
      }
    }

    final workers = [
      for (var w = 0; w < concurrency && w < items.length; w++) worker(),
    ];
    await Future.wait(workers);
    return [for (final r in results) r as R];
  }
}

class _Candidate {
  _Candidate({required this.path, required this.name, required this.category});
  final String path;
  final String name;
  final String category;
}
