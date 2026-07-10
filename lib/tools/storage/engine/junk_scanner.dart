import 'dart:io';

import '../../../core/models/cleanable_group.dart';
import '../../../core/utils/mac_paths.dart';
import 'fs_util.dart';
import 'scan_session.dart';

/// Isolate entry point for the junk / cleaner scan. Produces a list of
/// [CleanableGroup]s, each populated with sized, individually-removable items.
void junkScanEntry(ScanBoot<void> boot) {
  final send = boot.sendPort;

  var pendBytes = 0;
  var pendFiles = 0;
  String? pendPath;

  void flush({bool force = false}) {
    if (force || pendFiles >= 800) {
      send.send(ScanTick(bytes: pendBytes, files: pendFiles, path: pendPath));
      pendBytes = 0;
      pendFiles = 0;
    }
  }

  void onProg(int b, int f, String? dir) {
    pendBytes += b;
    pendFiles += f;
    if (dir != null) pendPath = dir;
    flush();
  }

  final groups = <CleanableGroup>[];

  CleanableGroup group(
    CleanupKind kind,
    String title,
    String description,
    CleanupRisk risk,
  ) {
    final g = CleanableGroup(
        kind: kind, title: title, description: description, risk: risk);
    groups.add(g);
    return g;
  }

  // Paths owned by the dedicated Developer/Browser groups. The generic User
  // Caches sweep must skip anything overlapping them (in either nesting
  // direction) — double-listing means double-counted sizes and a guaranteed
  // "failed to remove" on the second delete of every default clean.
  final ownedElsewhere = <String>[
    for (final d in MacPaths.developerCaches()) d.path,
    for (final b in MacPaths.browserCaches()) b.path,
  ];
  bool ownedByDedicatedGroup(String path) {
    for (final o in ownedElsewhere) {
      if (path == o || o.startsWith('$path/') || path.startsWith('$o/')) {
        return true;
      }
    }
    return false;
  }

  void addChildrenOf(CleanableGroup g, String dir,
      {String? detail, bool guardSensitive = false}) {
    if (FileSystemEntity.typeSync(dir, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return;
    }
    for (final c in FsUtil.sizedChildren(dir, onProgress: onProg)) {
      if (c.bytes <= 0) continue;
      if (MacPaths.isProtected(c.path)) continue;
      // Identity/account/session state never appears in the cleaner at all —
      // deleting it silently logs the user out of Apple ID, Xcode, Mail, etc.
      if (guardSensitive && MacPaths.isSensitiveName(c.name)) continue;
      if (guardSensitive && ownedByDedicatedGroup(c.path)) continue;
      g.items.add(CleanableItem(
        path: c.path,
        name: c.name,
        sizeBytes: c.bytes,
        modifiedMs: c.mtime,
        detail: detail,
        risk: g.risk,
      ));
    }
    flush(force: true);
  }

  void addMeasuredPath(CleanableGroup g, String path, String name,
      {String? detail, CleanupRisk? risk}) {
    if (FileSystemEntity.typeSync(path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return;
    }
    if (MacPaths.isProtected(path)) return;
    final m = FsUtil.measure(path, onProgress: onProg);
    if (m.bytes <= 0) return;
    g.items.add(CleanableItem(
      path: path,
      name: name,
      sizeBytes: m.bytes,
      detail: detail,
      risk: risk ?? g.risk,
    ));
    flush(force: true);
  }

  // 1. User caches ----------------------------------------------------------
  // guardSensitive: account/identity/session caches are excluded entirely —
  // clearing them signs the user out of Apple ID, iCloud, Xcode, Mail, etc.
  final userCache = group(CleanupKind.userCache, 'User Caches',
      'App caches in your Library. Safe to clear — apps rebuild them. '
      'Login, account and session data is protected and never touched.',
      CleanupRisk.safe);
  addChildrenOf(userCache, MacPaths.userCaches, guardSensitive: true);

  // 2. System caches --------------------------------------------------------
  final sysCache = group(CleanupKind.systemCache, 'System Caches',
      'Shared caches in /Library. Usually safe; some need a restart to rebuild.',
      CleanupRisk.caution);
  addChildrenOf(sysCache, MacPaths.systemCaches, guardSensitive: true);

  // 3. User logs ------------------------------------------------------------
  final userLogs = group(CleanupKind.userLogs, 'User Logs',
      'Diagnostic logs written by your apps.', CleanupRisk.safe);
  addChildrenOf(userLogs, MacPaths.userLogs);

  // 4. System logs ----------------------------------------------------------
  final sysLogs = group(CleanupKind.systemLogs, 'System Logs',
      'System-wide diagnostic logs.', CleanupRisk.caution);
  addChildrenOf(sysLogs, MacPaths.systemLogs);

  // 5. Trash ----------------------------------------------------------------
  final trash = group(CleanupKind.trash, 'Trash',
      'Everything sitting in your Trash, ready to be emptied.', CleanupRisk.safe);
  addChildrenOf(trash, MacPaths.userTrash);

  // 6. Saved application state ----------------------------------------------
  final saved = group(CleanupKind.savedAppState, 'Saved App State',
      'Window/state snapshots apps restore on relaunch.', CleanupRisk.safe);
  addChildrenOf(saved, MacPaths.savedAppState);

  // 7. Developer junk -------------------------------------------------------
  // Truly-regenerable caches are safe. Things that hold WORK or configured
  // state (release archives, simulator devices, pnpm's content store) are
  // caution: listed, but never pre-selected.
  final dev = group(CleanupKind.developerJunk, 'Developer Junk',
      'Regenerable build caches are pre-selected. Archives and simulators hold '
      'real data, so they need an explicit tick.',
      CleanupRisk.safe);
  const devCaution = {
    'Xcode Archives': 'Your app release builds — not regenerable',
    'iOS Simulators': 'Removes simulator devices and everything in them',
    'pnpm store': 'Breaks existing node_modules hard links',
  };
  for (final d in MacPaths.developerCaches()) {
    final warning = devCaution[d.name];
    addMeasuredPath(dev, d.path, d.name,
        detail: warning,
        risk: warning == null ? CleanupRisk.safe : CleanupRisk.caution);
  }

  // 8. Browser caches -------------------------------------------------------
  final browser = group(CleanupKind.browserCache, 'Browser Caches',
      'Cached web content. Clearing means pages reload fresh.', CleanupRisk.safe);
  for (final b in MacPaths.browserCaches()) {
    addMeasuredPath(browser, b.path, b.name);
  }

  // 9. Old downloads --------------------------------------------------------
  final dl = group(CleanupKind.downloads, 'Old Downloads',
      'Files in ~/Downloads untouched for 30+ days. Review before removing.',
      CleanupRisk.caution);
  final cutoff = DateTime.now().subtract(const Duration(days: 30));
  try {
    for (final c in FsUtil.sizedChildren(MacPaths.downloads, onProgress: onProg)) {
      if (c.bytes <= 0) continue;
      final mtime = c.mtime;
      if (mtime == null) continue;
      if (DateTime.fromMillisecondsSinceEpoch(mtime).isAfter(cutoff)) continue;
      dl.items.add(CleanableItem(
        path: c.path,
        name: c.name,
        sizeBytes: c.bytes,
        modifiedMs: mtime,
        detail: 'Last opened ${_ageLabel(mtime)}',
        risk: CleanupRisk.caution,
      ));
    }
  } catch (_) {}
  flush(force: true);

  // 10. Mail downloads ------------------------------------------------------
  final mail = group(CleanupKind.mailDownloads, 'Mail Attachments',
      'Attachments saved by Mail. Originals stay on the server.', CleanupRisk.caution);
  for (final p in [
    '${MacPaths.home}/Library/Containers/com.apple.mail/Data/Library/Mail Downloads',
    '${MacPaths.home}/Library/Mail Downloads',
  ]) {
    addChildrenOf(mail, p);
  }

  // 11. App leftovers (conservative, opt-in) --------------------------------
  final leftovers = group(CleanupKind.appLeftovers, 'App Leftovers',
      'Support files for apps that appear to be uninstalled. Review carefully.',
      CleanupRisk.caution);
  _collectLeftovers(leftovers, onProg);
  flush(force: true);

  // Drop empty groups so the UI only shows what actually has reclaimable data.
  groups.removeWhere((g) => g.isEmpty);
  send.send(ScanResultMsg(groups));
}

String _ageLabel(int ms) {
  final days = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms)).inDays;
  if (days >= 365) return '${(days / 365).floor()}y ago';
  if (days >= 30) return '${(days / 30).floor()}mo ago';
  return '${days}d ago';
}

/// Reverse-DNS bundle ids of every app currently installed, used to decide if a
/// support folder is an orphan.
Set<String> _installedBundleIds() {
  final ids = <String>{};
  for (final dir in [
    MacPaths.systemApplications,
    MacPaths.userApplications,
    '/System/Applications',
    '/System/Library/CoreServices',
  ]) {
    final d = Directory(dir);
    if (!d.existsSync()) continue;
    List<FileSystemEntity> entries;
    try {
      entries = d.listSync(followLinks: false);
    } catch (_) {
      continue;
    }
    void addAppId(String appPath) {
      try {
        final res = Process.runSync(
          'defaults',
          ['read', '$appPath/Contents/Info', 'CFBundleIdentifier'],
        );
        final id = (res.stdout as String).trim();
        if (id.isNotEmpty) ids.add(id.toLowerCase());
      } catch (_) {}
    }

    for (final e in entries) {
      if (e.path.endsWith('.app')) {
        addAppId(e.path);
      } else if (e is Directory) {
        // Apps one level down too (e.g. /Applications/Setapp/Foo.app) —
        // missing them makes Leftovers flag installed apps as orphans.
        try {
          for (final sub in e.listSync(followLinks: false)) {
            if (sub.path.endsWith('.app')) addAppId(sub.path);
          }
        } catch (_) {}
      }
    }
  }
  return ids;
}

/// Finds support/cache folders named like a bundle id with no matching app.
/// Deliberately conservative: requires a reverse-DNS-looking name, skips Apple
/// and well-known vendors, and only ever marks items as *caution* (unselected).
void _collectLeftovers(
  CleanableGroup g,
  void Function(int, int, String?) onProg,
) {
  final installed = _installedBundleIds();
  const keepVendors = {
    'com.apple', 'com.google', 'com.microsoft', 'com.adobe', 'com.docker',
    'com.tinyspeck', 'com.spotify', 'org.mozilla', 'company.thebrowser',
    'com.brave', 'com.figma', 'notion', 'com.electron', 'crashpad',
  };
  final seen = <String>{};
  for (final base in [MacPaths.userAppSupport, MacPaths.userCaches]) {
    if (FileSystemEntity.typeSync(base, followLinks: false) ==
        FileSystemEntityType.notFound) {
      continue;
    }
    List<FileSystemEntity> entries;
    try {
      entries = Directory(base).listSync(followLinks: false);
    } catch (_) {
      continue;
    }
    for (final e in entries) {
      if (e is! Directory) continue;
      final name = e.path.split('/').last;
      final lower = name.toLowerCase();
      // Must look like a reverse-DNS bundle id (a.b.c) to qualify.
      if (lower.split('.').length < 3) continue;
      if (MacPaths.isSensitiveName(name)) continue;
      if (installed.contains(lower)) continue;
      if (keepVendors.any((v) => lower.startsWith(v) || lower.contains(v))) {
        continue;
      }
      if (!seen.add(lower)) continue;
      final m = FsUtil.measure(e.path, onProgress: onProg);
      if (m.bytes <= 0) continue;
      g.items.add(CleanableItem(
        path: e.path,
        name: name,
        sizeBytes: m.bytes,
        detail: 'No matching app found',
        risk: CleanupRisk.caution,
      ));
    }
  }
}

/// Drives the junk scan in a background isolate.
class JunkScanner {
  ScanSession<List<CleanableGroup>> start() {
    return startScan<void, List<CleanableGroup>>(junkScanEntry, null);
  }
}
