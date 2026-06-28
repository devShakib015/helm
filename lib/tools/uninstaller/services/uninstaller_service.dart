import 'dart:async';
import 'dart:io';

import '../../../core/services/shell.dart';
import '../../../core/utils/mac_paths.dart';
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

  /// Lists the immediate `.app` bundle paths inside [dir]. Returns an empty
  /// list if the directory is missing or unreadable.
  List<String> _appBundlesIn(String dir) {
    try {
      final d = Directory(dir);
      if (!d.existsSync()) return const [];
      final out = <String>[];
      for (final entry in d.listSync(followLinks: false)) {
        if (entry.path.endsWith('.app')) out.add(entry.path);
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
  Future<List<Leftover>> findLeftovers(InstalledApp app) async {
    final bundleId = app.bundleId.toLowerCase();
    final appKey = app.name.toLowerCase().replaceAll(' ', '');
    final home = MacPaths.home;

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
      // Strongest signal: a reverse-DNS name beginning with the bundle id.
      if (bundleId.isNotEmpty && lower.startsWith(bundleId)) return true;
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
