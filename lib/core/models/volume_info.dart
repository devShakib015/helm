/// Snapshot of a mounted volume's capacity, as reported by the OS.
class VolumeInfo {
  const VolumeInfo({
    required this.name,
    required this.mountPoint,
    required this.fileSystem,
    required this.totalBytes,
    required this.freeBytes,
    required this.purgeableBytes,
    this.deviceModel,
    this.isInternal = true,
  });

  final String name;
  final String mountPoint;
  final String fileSystem;

  /// Total capacity of the volume.
  final int totalBytes;

  /// Space currently available to the user (after purgeable is reclaimed).
  final int freeBytes;

  /// Space macOS can reclaim on demand (caches, local snapshots, etc.).
  final int purgeableBytes;

  final String? deviceModel;
  final bool isInternal;

  /// "Real" used space = everything not free and not purgeable. This is what
  /// macOS shows as "Used" in About This Mac.
  int get usedBytes {
    final used = totalBytes - freeBytes - purgeableBytes;
    return used < 0 ? 0 : used;
  }

  /// Everything occupying the disk that isn't free space — i.e. used **plus**
  /// purgeable. This is the basis Helm's file scanners measure on (they sum
  /// real on-disk sizes, including cache/snapshot bytes macOS calls purgeable),
  /// so category totals must be reconciled against this, not [usedBytes].
  int get occupiedBytes {
    final occ = totalBytes - freeBytes;
    return occ < 0 ? 0 : occ;
  }

  double get usedFraction =>
      totalBytes <= 0 ? 0 : usedBytes / totalBytes;

  double get purgeableFraction =>
      totalBytes <= 0 ? 0 : purgeableBytes / totalBytes;

  double get freeFraction =>
      totalBytes <= 0 ? 0 : freeBytes / totalBytes;

  static const VolumeInfo empty = VolumeInfo(
    name: 'Macintosh HD',
    mountPoint: '/',
    fileSystem: 'apfs',
    totalBytes: 0,
    freeBytes: 0,
    purgeableBytes: 0,
  );
}
