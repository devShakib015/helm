import 'dart:io';

import '../../../core/models/scan_node.dart';
import '../../../core/utils/mac_paths.dart';

/// Pure filesystem walking primitives shared by every scanner. No Flutter
/// imports — these run inside background isolates.
///
/// Symlinks are never followed: `listSync(followLinks: false)` yields [Link]
/// objects for symlinks, which we skip. That avoids infinite loops and the
/// double-counting that macOS firmlinks (e.g. `/System/Volumes/Data`) would
/// otherwise cause.
class FsUtil {
  FsUtil._();

  /// Reports incremental progress: bytes & files added since the last call,
  /// plus the directory currently being entered (null for file ticks).
  /// Returning `false` aborts the walk early (used for cancellation).
  static int? _mtimeMs(FileSystemEntity e) {
    try {
      return e.statSync().modified.millisecondsSinceEpoch;
    } catch (_) {
      return null;
    }
  }

  /// Bundle/package extensions treated as a single opaque unit. Users act on
  /// these as a whole (delete an app, a photo library), and walking inside them
  /// would balloon the tree with thousands of internal files.
  static const Set<String> _opaqueExts = {
    '.app',
    '.photoslibrary',
    '.photolibrary',
    '.aplibrary',
    '.musiclibrary',
    '.tvlibrary',
    '.imovielibrary',
    '.theater',
    '.fcpbundle',
    '.pkg',
    '.mpkg',
  };

  static bool _isOpaqueBundle(String path) {
    for (final ext in _opaqueExts) {
      if (path.endsWith(ext)) return true;
    }
    return false;
  }

  /// Builds a full [ScanNode] tree rooted at [path], aggregating sizes.
  static ScanNode walkTree(
    String path, {
    required int maxDepth,
    void Function(int dBytes, int dFiles, String? dir)? onProgress,
    bool Function()? isCancelled,
    int depth = 0,
  }) {
    final name = _basename(path);
    final isApp = path.endsWith('.app');

    if (_isOpaqueBundle(path)) {
      final size = _measureFast(path, onProgress: onProgress, isCancelled: isCancelled);
      return ScanNode(
        path: path,
        name: name,
        isDirectory: true,
        isApp: isApp,
        sizeBytes: size.bytes,
        fileCount: size.files,
        modifiedMs: _mtimeMs(Directory(path)),
      );
    }

    final node = ScanNode(
      path: path,
      name: name,
      isDirectory: true,
      modifiedMs: _mtimeMs(Directory(path)),
    );
    onProgress?.call(0, 0, path);

    List<FileSystemEntity> entries;
    try {
      entries = Directory(path).listSync(followLinks: false);
    } on FileSystemException {
      node.accessDenied = true;
      return node;
    } catch (_) {
      node.accessDenied = true;
      return node;
    }

    for (final e in entries) {
      if (isCancelled?.call() ?? false) break;
      if (e is Link) continue; // never follow symlinks
      final p = e.path;
      if (MacPaths.isProtected(p)) continue;

      if (e is File) {
        int size = 0;
        int? mtime;
        try {
          final st = e.statSync();
          size = st.size;
          mtime = st.modified.millisecondsSinceEpoch;
        } catch (_) {
          continue;
        }
        node.children.add(ScanNode(
          path: p,
          name: _basename(p),
          isDirectory: false,
          sizeBytes: size,
          fileCount: 1,
          modifiedMs: mtime,
        ));
        node.sizeBytes += size;
        node.fileCount += 1;
        onProgress?.call(size, 1, null);
      } else if (e is Directory) {
        if (depth + 1 >= maxDepth) {
          // Stop building the tree but still account for the size.
          final m = _measureFast(p, onProgress: onProgress, isCancelled: isCancelled);
          node.children.add(ScanNode(
            path: p,
            name: _basename(p),
            isDirectory: true,
            sizeBytes: m.bytes,
            fileCount: m.files,
            modifiedMs: _mtimeMs(e),
          ));
          node.sizeBytes += m.bytes;
          node.fileCount += m.files;
        } else {
          final child = walkTree(
            p,
            maxDepth: maxDepth,
            onProgress: onProgress,
            isCancelled: isCancelled,
            depth: depth + 1,
          );
          node.children.add(child);
          node.sizeBytes += child.sizeBytes;
          node.fileCount += child.fileCount;
        }
      }
    }
    return node;
  }

  /// Fast size+count of a path without building a tree (low memory).
  static ({int bytes, int files}) measure(
    String path, {
    void Function(int dBytes, int dFiles, String? dir)? onProgress,
    bool Function()? isCancelled,
  }) {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return (bytes: 0, files: 0);
    if (type == FileSystemEntityType.file) {
      try {
        final s = File(path).statSync().size;
        onProgress?.call(s, 1, null);
        return (bytes: s, files: 1);
      } catch (_) {
        return (bytes: 0, files: 0);
      }
    }
    if (type == FileSystemEntityType.link) return (bytes: 0, files: 0);
    return _measureFast(path, onProgress: onProgress, isCancelled: isCancelled);
  }

  static ({int bytes, int files}) _measureFast(
    String path, {
    void Function(int dBytes, int dFiles, String? dir)? onProgress,
    bool Function()? isCancelled,
  }) {
    var bytes = 0;
    var files = 0;
    // Iterative DFS to avoid deep-recursion stack growth on pathological trees.
    final stack = <String>[path];
    while (stack.isNotEmpty) {
      if (isCancelled?.call() ?? false) break;
      final dir = stack.removeLast();
      if (MacPaths.isProtected(dir)) continue;
      onProgress?.call(0, 0, dir);
      List<FileSystemEntity> entries;
      try {
        entries = Directory(dir).listSync(followLinks: false);
      } catch (_) {
        continue;
      }
      for (final e in entries) {
        if (e is Link) continue;
        if (e is File) {
          try {
            final s = e.statSync().size;
            bytes += s;
            files += 1;
            onProgress?.call(s, 1, null);
          } catch (_) {}
        } else if (e is Directory) {
          stack.add(e.path);
        }
      }
    }
    return (bytes: bytes, files: files);
  }

  /// Immediate children of [path] sized individually — the basis for cleaner
  /// item lists (e.g. each subfolder of ~/Library/Caches becomes one item).
  static List<({String path, String name, int bytes, int files, int? mtime})>
      sizedChildren(
    String path, {
    bool Function()? isCancelled,
    void Function(int dBytes, int dFiles, String? dir)? onProgress,
  }) {
    final out = <({String path, String name, int bytes, int files, int? mtime})>[];
    List<FileSystemEntity> entries;
    try {
      entries = Directory(path).listSync(followLinks: false);
    } catch (_) {
      return out;
    }
    for (final e in entries) {
      if (isCancelled?.call() ?? false) break;
      if (e is Link) continue;
      final p = e.path;
      if (e is File) {
        try {
          final st = e.statSync();
          out.add((
            path: p,
            name: _basename(p),
            bytes: st.size,
            files: 1,
            mtime: st.modified.millisecondsSinceEpoch
          ));
          onProgress?.call(st.size, 1, null);
        } catch (_) {}
      } else if (e is Directory) {
        final m = _measureFast(p, onProgress: onProgress, isCancelled: isCancelled);
        out.add((
          path: p,
          name: _basename(p),
          bytes: m.bytes,
          files: m.files,
          mtime: _mtimeMs(e)
        ));
      }
    }
    out.sort((a, b) => b.bytes.compareTo(a.bytes));
    return out;
  }

  static String _basename(String path) {
    final i = path.lastIndexOf('/');
    return i < 0 ? path : path.substring(i + 1);
  }
}
