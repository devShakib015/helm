import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../../core/models/duplicate_set.dart';
import '../../../core/models/file_entry.dart';
import '../../../core/utils/mac_paths.dart';
import 'scan_session.dart';

class DuplicateScanArgs {
  const DuplicateScanArgs({required this.roots, required this.minBytes});
  final List<String> roots;
  final int minBytes;
}

class _Candidate {
  _Candidate(this.path, this.mtime);
  final String path;
  final int? mtime;
}

/// Minimal [Sink] to capture the digest from a chunked hash conversion without
/// pulling in crypto's internal AccumulatorSink.
class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

/// Quick fingerprint: MD5 of the first 64 KB. Cheap pre-filter before a full
/// hash, so we only fully read files that already collide on size + head.
String? _quickHash(String path) {
  try {
    final raf = File(path).openSync();
    try {
      final head = raf.readSync(64 * 1024);
      return md5.convert(head).toString();
    } finally {
      raf.closeSync();
    }
  } catch (_) {
    return null;
  }
}

/// Full streaming MD5 — reads the file in 1 MB chunks so even huge files don't
/// blow up memory.
String? _fullHash(String path) {
  RandomAccessFile? raf;
  try {
    raf = File(path).openSync();
    final sink = _DigestSink();
    final input = md5.startChunkedConversion(sink);
    final buffer = Uint8List(1024 * 1024);
    while (true) {
      final n = raf.readIntoSync(buffer);
      if (n <= 0) break;
      input.add(n == buffer.length ? buffer : Uint8List.sublistView(buffer, 0, n));
    }
    input.close();
    return sink.value?.toString();
  } catch (_) {
    return null;
  } finally {
    raf?.closeSync();
  }
}

/// Isolate entry point for duplicate detection.
void duplicateScanEntry(ScanBoot<DuplicateScanArgs> boot) {
  final send = boot.sendPort;
  final args = boot.arg;

  var pendBytes = 0;
  var pendFiles = 0;
  String? pendPath;
  void flush({bool force = false}) {
    if (force || pendFiles >= 1000) {
      send.send(ScanTick(bytes: pendBytes, files: pendFiles, path: pendPath));
      pendBytes = 0;
      pendFiles = 0;
    }
  }

  // Phase 1 — bucket candidate files by exact size.
  final bySize = <int, List<_Candidate>>{};
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
        if (_isBundle(e.path)) continue;
        stack.add(e.path);
      } else if (e is File) {
        try {
          final st = e.statSync();
          pendFiles += 1;
          if (st.size >= args.minBytes) {
            bySize
                .putIfAbsent(st.size, () => <_Candidate>[])
                .add(_Candidate(e.path, st.modified.millisecondsSinceEpoch));
          }
          flush();
        } catch (_) {}
      }
    }
  }
  flush(force: true);

  // Phase 2 — confirm duplicates within each same-size bucket.
  final sets = <DuplicateSet>[];
  for (final entry in bySize.entries) {
    final size = entry.key;
    final group = entry.value;
    if (group.length < 2) continue;

    final byQuick = <String, List<_Candidate>>{};
    for (final c in group) {
      final q = _quickHash(c.path);
      pendFiles += 1;
      if (q == null) continue;
      byQuick.putIfAbsent(q, () => <_Candidate>[]).add(c);
    }
    flush();

    for (final quickGroup in byQuick.values) {
      if (quickGroup.length < 2) continue;
      final byFull = <String, List<_Candidate>>{};
      for (final c in quickGroup) {
        final h = _fullHash(c.path);
        pendBytes += size;
        pendFiles += 1;
        if (h == null) continue;
        byFull.putIfAbsent(h, () => <_Candidate>[]).add(c);
      }
      flush();
      for (final fullGroup in byFull.entries) {
        if (fullGroup.value.length < 2) continue;
        sets.add(DuplicateSet(
          hash: fullGroup.key,
          sizeBytes: size,
          files: [
            for (final c in fullGroup.value)
              FileEntry(
                path: c.path,
                name: c.path.split('/').last,
                sizeBytes: size,
                modifiedMs: c.mtime,
              )
          ],
        ));
      }
    }
  }

  sets.sort((a, b) => b.reclaimableBytes.compareTo(a.reclaimableBytes));
  send.send(ScanResultMsg(sets));
}

bool _isBundle(String path) {
  const exts = ['.app', '.photoslibrary', '.musiclibrary', '.tvlibrary',
      '.imovielibrary', '.fcpbundle', '.framework'];
  for (final e in exts) {
    if (path.endsWith(e)) return true;
  }
  return false;
}

class DuplicateFinder {
  /// [minBytes] defaults to 1 MB — below that, dedupe rarely pays off.
  ScanSession<List<DuplicateSet>> start({
    List<String>? roots,
    int minBytes = 1000 * 1000,
  }) {
    return startScan<DuplicateScanArgs, List<DuplicateSet>>(
      duplicateScanEntry,
      DuplicateScanArgs(roots: roots ?? [MacPaths.home], minBytes: minBytes),
    );
  }
}
