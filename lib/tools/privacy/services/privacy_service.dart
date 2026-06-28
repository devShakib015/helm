import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/services/shell.dart';
import '../../../core/utils/mac_paths.dart';
import '../models/trace_group.dart';

/// Discovers the privacy traces macOS leaves around the user account and sizes
/// them, so the controller can present clearable groups. Everything is derived
/// from `$HOME` and probed read-only; nothing is removed here.
class PrivacyService {
  PrivacyService._();

  /// Tool accent — purple, matching the Privacy tool's icon chip.
  static const Color accent = Color(0xFF7B61FF);

  /// Builds every non-empty trace group. Groups whose paths don't exist are
  /// dropped entirely. Never throws — a failed probe just yields no items.
  static Future<List<TraceGroup>> scan() async {
    final groups = <TraceGroup>[
      await _recentItems(),
      await _quickLook(),
      await _safariHistory(),
      await _chromeHistory(),
      await _shellHistory(),
      await _terminalSavedState(),
    ];
    return [for (final g in groups) if (!g.isEmpty) g];
  }

  // ---- Groups -------------------------------------------------------------

  static Future<TraceGroup> _recentItems() async {
    final group = TraceGroup(
      title: 'Recent Items',
      description:
          'Recently-opened files and apps remembered across the system.',
      icon: Icons.history_rounded,
      color: const Color(0xFF7B61FF),
      caution: true,
    );
    final root =
        '${MacPaths.home}/Library/Application Support/com.apple.sharedfilelist';
    await _addItem(group, root, 'Shared File Lists');
    // Per-list entries (com.apple.LSSharedFileList.*).
    for (final child in await _children(root)) {
      final name = _basename(child);
      if (name.startsWith('com.apple.LSSharedFileList')) {
        await _addItem(group, child, _prettyListName(name));
      }
    }
    return group;
  }

  static Future<TraceGroup> _quickLook() async {
    final group = TraceGroup(
      title: 'Quick Look Thumbnails',
      description:
          'Cached previews macOS generated for files you browsed in Finder.',
      icon: Icons.image_search_rounded,
      color: const Color(0xFF7B61FF),
      caution: false,
    );
    var dir = '';
    try {
      dir = (await Shell.out('getconf', ['DARWIN_USER_CACHE_DIR'])).trim();
    } catch (_) {
      dir = '';
    }
    final primary = dir.isEmpty
        ? null
        : '${dir.endsWith('/') ? dir : '$dir/'}com.apple.QuickLook.thumbnailcache';
    final fallback =
        '${MacPaths.userCaches}/com.apple.QuickLook.thumbnailcache';
    final path =
        (primary != null && await _exists(primary)) ? primary : fallback;
    await _addItem(group, path, 'Thumbnail Cache');
    return group;
  }

  static Future<TraceGroup> _safariHistory() async {
    final group = TraceGroup(
      title: 'Safari History',
      description: 'Your Safari browsing history and download record.',
      icon: Icons.public_rounded,
      color: const Color(0xFF7B61FF),
      caution: true,
    );
    final base = '${MacPaths.home}/Library/Safari';
    await _addItem(group, '$base/History.db', 'History.db');
    await _addItem(group, '$base/History.db-wal', 'History.db-wal');
    await _addItem(group, '$base/History.db-shm', 'History.db-shm');
    await _addItem(group, '$base/Downloads.plist', 'Downloads.plist');
    return group;
  }

  static Future<TraceGroup> _chromeHistory() async {
    final group = TraceGroup(
      title: 'Chrome History',
      description: 'Google Chrome browsing history and cookies.',
      icon: Icons.travel_explore_rounded,
      color: const Color(0xFF7B61FF),
      caution: true,
    );
    final base = '${MacPaths.userAppSupport}/Google/Chrome/Default';
    await _addItem(group, '$base/History', 'History');
    await _addItem(group, '$base/Cookies', 'Cookies');
    return group;
  }

  static Future<TraceGroup> _shellHistory() async {
    final group = TraceGroup(
      title: 'Shell History',
      description: 'Commands you typed in the terminal, saved by your shell.',
      icon: Icons.terminal_rounded,
      color: const Color(0xFF7B61FF),
      caution: true,
    );
    await _addItem(group, '${MacPaths.home}/.zsh_history', '.zsh_history');
    await _addItem(group, '${MacPaths.home}/.bash_history', '.bash_history');
    return group;
  }

  static Future<TraceGroup> _terminalSavedState() async {
    final group = TraceGroup(
      title: 'Terminal Saved State',
      description: 'Restored Terminal windows and their scrollback contents.',
      icon: Icons.restore_rounded,
      color: const Color(0xFF7B61FF),
      caution: false,
    );
    await _addItem(
      group,
      '${MacPaths.savedAppState}/com.apple.Terminal.savedState',
      'com.apple.Terminal.savedState',
    );
    return group;
  }

  // ---- Helpers ------------------------------------------------------------

  /// Adds [path] to [group] if it exists on disk, sizing it via `du -sk`.
  static Future<void> _addItem(
    TraceGroup group,
    String path,
    String name,
  ) async {
    if (MacPaths.isProtected(path)) return;
    if (!await _exists(path)) return;
    final size = await _sizeOf(path);
    group.items.add(TraceItem(
      path: path,
      name: name,
      sizeBytes: size,
      selected: !group.caution,
    ));
  }

  static Future<bool> _exists(String path) async {
    try {
      return await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.notFound;
    } catch (_) {
      return false;
    }
  }

  /// Disk usage in bytes via `du -sk` (kibibytes). Degrades to 0 on failure.
  static Future<int> _sizeOf(String path) async {
    try {
      final r = await Shell.run('du', ['-sk', path]);
      if (r.code != 0) return 0;
      final first = r.out.trim().split(RegExp(r'\s+')).first;
      final kb = int.tryParse(first) ?? 0;
      return kb * 1024;
    } catch (_) {
      return 0;
    }
  }

  /// Immediate children of a directory (full paths). Empty if not a directory.
  static Future<List<String>> _children(String path) async {
    try {
      final dir = Directory(path);
      if (!await dir.exists()) return const [];
      final out = <String>[];
      await for (final e in dir.list(followLinks: false)) {
        out.add(e.path);
      }
      out.sort();
      return out;
    } catch (_) {
      return const [];
    }
  }

  static String _basename(String path) {
    final parts = path.split('/');
    return parts.isEmpty ? path : parts.last;
  }

  /// Turns "com.apple.LSSharedFileList.RecentDocuments.sfl3" into something a
  /// human recognises, e.g. "Recent Documents".
  static String _prettyListName(String fileName) {
    var s = fileName.replaceFirst('com.apple.LSSharedFileList.', '');
    // Drop trailing extension like .sfl, .sfl2, .sfl3, .plist.
    final dot = s.lastIndexOf('.');
    if (dot > 0) s = s.substring(0, dot);
    // Split CamelCase into words.
    final spaced = s.replaceAllMapped(
      RegExp(r'(?<=[a-z0-9])(?=[A-Z])'),
      (_) => ' ',
    );
    return spaced.isEmpty ? fileName : spaced;
  }
}
