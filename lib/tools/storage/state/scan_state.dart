import '../engine/scan_session.dart';

enum ScanState { idle, scanning, done, error, cancelled }

/// Accumulated progress for a running scan. Immutable — controllers swap in a
/// new instance on each tick so `notifyListeners` has something to diff.
class ScanProgress {
  const ScanProgress({
    this.bytes = 0,
    this.files = 0,
    this.currentPath,
    this.startedAt,
    this.finishedAt,
  });

  final int bytes;
  final int files;
  final String? currentPath;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  static ScanProgress start() => ScanProgress(startedAt: DateTime.now());

  ScanProgress add(ScanTick tick) => ScanProgress(
        bytes: bytes + tick.bytes,
        files: files + tick.files,
        currentPath: tick.path ?? currentPath,
        startedAt: startedAt,
        finishedAt: finishedAt,
      );

  ScanProgress finish() => ScanProgress(
        bytes: bytes,
        files: files,
        currentPath: null,
        startedAt: startedAt,
        finishedAt: DateTime.now(),
      );

  Duration get elapsed {
    if (startedAt == null) return Duration.zero;
    return (finishedAt ?? DateTime.now()).difference(startedAt!);
  }
}
