import 'dart:io';

import '../models/snapshot_info.dart';
import '../models/volume_info.dart';
import 'native_bridge.dart';

/// Reads volume capacity and APFS snapshots, and exposes a few Finder helpers.
class SystemInfoService {
  /// Capacity of the boot volume. Prefers the native bridge (accurate purgeable
  /// space) and falls back to parsing `df` if the channel is unavailable.
  Future<VolumeInfo> bootVolume() async {
    final native = await NativeBridge.volumeInfo('/');
    if (native != null) {
      final total = _int(native['total']);
      final available = _int(native['available']); // excludes purgeable
      final important = _int(native['importantAvailable']); // incl. purgeable
      final purgeable = (important - available).clamp(0, total);
      return VolumeInfo(
        name: (native['name'] as String?) ?? 'Macintosh HD',
        mountPoint: '/',
        fileSystem: (native['fileSystem'] as String?) ?? 'apfs',
        totalBytes: total,
        freeBytes: available,
        purgeableBytes: purgeable,
        deviceModel: native['model'] as String?,
        isInternal: (native['internal'] as bool?) ?? true,
      );
    }
    return _fromDf();
  }

  Future<VolumeInfo> _fromDf() async {
    try {
      final res = await Process.run('df', ['-k', '/']);
      final lines = (res.stdout as String).trim().split('\n');
      if (lines.length >= 2) {
        final parts = lines[1].split(RegExp(r'\s+'));
        // Filesystem 1024-blocks Used Available Capacity ...
        final total = (int.tryParse(parts[1]) ?? 0) * 1024;
        final used = (int.tryParse(parts[2]) ?? 0) * 1024;
        final avail = (int.tryParse(parts[3]) ?? 0) * 1024;
        return VolumeInfo(
          name: 'Macintosh HD',
          mountPoint: '/',
          fileSystem: 'apfs',
          totalBytes: total,
          freeBytes: avail,
          purgeableBytes: (total - used - avail).clamp(0, total),
        );
      }
    } catch (_) {}
    return VolumeInfo.empty;
  }

  /// APFS local Time Machine snapshots on `/`.
  Future<List<SnapshotInfo>> localSnapshots() async {
    try {
      final res = await Process.run('tmutil', ['listlocalsnapshots', '/']);
      final out = res.stdout as String;
      final snaps = <SnapshotInfo>[];
      for (final line in out.split('\n')) {
        final name = line.trim();
        if (!name.startsWith('com.apple.TimeMachine.')) continue;
        snaps.add(SnapshotInfo(name: name, dateMs: _parseSnapshotDate(name)));
      }
      return snaps;
    } catch (_) {
      return const [];
    }
  }

  /// Asks macOS to thin local snapshots, reclaiming up to ~`purgeBytes`.
  Future<bool> thinLocalSnapshots() async {
    try {
      final res = await Process.run(
        'tmutil',
        ['thinlocalsnapshots', '/', '999999999999', '4'],
      );
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<void> revealInFinder(String path) async {
    try {
      await Process.run('open', ['-R', path]);
    } catch (_) {}
  }

  Future<void> openPath(String path) async {
    try {
      await Process.run('open', [path]);
    } catch (_) {}
  }

  Future<void> openUrl(String url) async {
    try {
      await Process.run('open', [url]);
    } catch (_) {}
  }

  int? _parseSnapshotDate(String name) {
    // com.apple.TimeMachine.2026-06-28-114233.local
    final m = RegExp(r'(\d{4})-(\d{2})-(\d{2})-(\d{2})(\d{2})(\d{2})')
        .firstMatch(name);
    if (m == null) return null;
    try {
      return DateTime(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
        int.parse(m.group(4)!),
        int.parse(m.group(5)!),
        int.parse(m.group(6)!),
      ).millisecondsSinceEpoch;
    } catch (_) {
      return null;
    }
  }

  int _int(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);
}
