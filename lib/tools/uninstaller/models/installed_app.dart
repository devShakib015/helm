/// A user-facing application discovered under `/Applications` or
/// `~/Applications`, together with its bundle identifier and on-disk size.
class InstalledApp {
  InstalledApp({
    required this.name,
    required this.path,
    required this.bundleId,
    required this.sizeBytes,
  });

  /// Display name (the `.app` bundle's base name, without the extension).
  final String name;

  /// Absolute path to the `.app` bundle.
  final String path;

  /// `CFBundleIdentifier` from the bundle's `Info.plist` (may be empty if the
  /// app has no readable identifier).
  final String bundleId;

  /// Size of the `.app` bundle itself, in bytes.
  final int sizeBytes;
}

/// A leftover file or folder associated with an app — a cache, preference,
/// container, saved state, log, and so on — that an uninstall would normally
/// leave behind. Each leftover carries its own selection flag so the user can
/// pick exactly what to remove.
class Leftover {
  Leftover({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.category,
    this.selected = true,
  });

  /// Absolute path to the leftover item.
  final String path;

  /// Display name (the item's base name).
  final String name;

  /// Size on disk, in bytes.
  final int sizeBytes;

  /// Human-readable bucket: `Support`, `Caches`, `Preferences`, `Container`,
  /// `Saved State`, `Logs`, and friends.
  final String category;

  /// Whether the user has this leftover queued for removal.
  bool selected;
}
