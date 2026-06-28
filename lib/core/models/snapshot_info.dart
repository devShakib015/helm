/// An APFS local Time Machine snapshot.
///
/// These can silently consume tens of gigabytes that show up as "purgeable".
/// Helm surfaces them and can ask `tmutil` to thin them.
class SnapshotInfo {
  const SnapshotInfo({
    required this.name,
    this.dateMs,
    this.sizeBytes,
  });

  /// e.g. `com.apple.TimeMachine.2026-06-28-114233.local`
  final String name;

  final int? dateMs;

  /// Reclaimable size if known (`tmutil` doesn't always report this).
  final int? sizeBytes;

  DateTime? get date =>
      dateMs == null ? null : DateTime.fromMillisecondsSinceEpoch(dateMs!);
}
