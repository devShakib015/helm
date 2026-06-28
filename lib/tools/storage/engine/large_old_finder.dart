import 'dart:io';

import '../../../core/models/file_entry.dart';
import '../../../core/utils/mac_paths.dart';
import 'scan_session.dart';

/// Arguments for the large-files scan.
class LargeScanArgs {
  const LargeScanArgs({required this.roots, required this.minBytes, this.cap = 2000});
  final List<String> roots;
  final int minBytes;
  final int cap;
}

/// Isolate entry point: walks [roots] collecting every regular file at least
/// [minBytes] in size, returning the [cap] largest.
void largeScanEntry(ScanBoot<LargeScanArgs> boot) {
  final send = boot.sendPort;
  final args = boot.arg;
  final found = <FileEntry>[];

  var pendBytes = 0;
  var pendFiles = 0;
  String? pendPath;
  void flush({bool force = false}) {
    if (force || pendFiles >= 1500) {
      send.send(ScanTick(bytes: pendBytes, files: pendFiles, path: pendPath));
      pendBytes = 0;
      pendFiles = 0;
    }
  }

  final stack = <String>[...args.roots];
  while (stack.isNotEmpty) {
    final dir = stack.removeLast();
    if (MacPaths.isProtected(dir)) continue;
    pendPath = dir;
    List<FileSystemEntity> entries;
    try {
      entries = Directory(dir).listSync(followLinks: false);
    } catch (_) {
      continue;
    }
    for (final e in entries) {
      if (e is Link) continue;
      if (e is Directory) {
        // Don't descend into opaque bundles — they're single units elsewhere.
        if (_isBundle(e.path)) continue;
        stack.add(e.path);
      } else if (e is File) {
        try {
          final st = e.statSync();
          pendFiles += 1;
          if (st.size >= args.minBytes) {
            found.add(FileEntry(
              path: e.path,
              name: e.path.split('/').last,
              sizeBytes: st.size,
              modifiedMs: st.modified.millisecondsSinceEpoch,
            ));
            pendBytes += st.size;
          }
          flush();
        } catch (_) {}
      }
    }
  }

  found.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
  final result = found.length > args.cap ? found.sublist(0, args.cap) : found;
  send.send(ScanResultMsg(result));
}

bool _isBundle(String path) {
  const exts = ['.app', '.photoslibrary', '.musiclibrary', '.tvlibrary',
      '.imovielibrary', '.fcpbundle', '.framework'];
  for (final e in exts) {
    if (path.endsWith(e)) return true;
  }
  return false;
}

class LargeFileFinder {
  /// [minBytes] defaults to 100 MB.
  ScanSession<List<FileEntry>> start({
    List<String>? roots,
    int minBytes = 100 * 1000 * 1000,
  }) {
    return startScan<LargeScanArgs, List<FileEntry>>(
      largeScanEntry,
      LargeScanArgs(roots: roots ?? [MacPaths.home], minBytes: minBytes),
    );
  }
}
