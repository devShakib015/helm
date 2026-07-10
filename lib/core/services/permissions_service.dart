import 'dart:io';

import '../utils/mac_paths.dart';

enum FdaStatus {
  /// Helm can read TCC-protected locations — full results.
  granted,

  /// Protected locations are blocked. Most of the user's own files are still
  /// scannable, but Mail / Messages / Safari / other app containers will be
  /// undercounted.
  denied,

  /// Couldn't determine (no probe path present). Treated like [denied] in the
  /// UI but with softer wording.
  unknown,
}

/// Detects and helps the user grant Full Disk Access. Done entirely in Dart by
/// probing whether TCC-protected paths are actually *readable* (stat succeeds
/// without FDA; opening/listing does not).
class PermissionsService {
  /// Tries EVERY probe path instead of judging from the first one: macOS gates
  /// them all behind the same FDA switch, so access to any single one proves
  /// the grant. Judging from one path alone caused false "denied" readings
  /// when that particular probe was missing or failed for unrelated reasons.
  Future<FdaStatus> checkFullDiskAccess() async {
    var sawBlocked = false;
    for (final p in MacPaths.fdaProbePaths) {
      final type = FileSystemEntity.typeSync(p, followLinks: false);
      if (type == FileSystemEntityType.notFound) continue;
      try {
        if (type == FileSystemEntityType.directory) {
          Directory(p).listSync(followLinks: false).take(1).toList();
        } else {
          final raf = File(p).openSync();
          raf.closeSync();
        }
        return FdaStatus.granted; // any readable probe proves the grant
      } catch (_) {
        sawBlocked = true; // exists but unreadable — keep trying the rest
      }
    }
    return sawBlocked ? FdaStatus.denied : FdaStatus.unknown;
  }

  /// Opens System Settings ▸ Privacy & Security ▸ Full Disk Access.
  Future<void> openFullDiskAccessSettings() async {
    try {
      await Process.run('open', [
        'x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles',
      ]);
    } catch (_) {}
  }
}
