import 'scan_node.dart';

/// The top-level buckets Helm groups disk usage into — modelled on the
/// breakdown macOS itself shows in System Settings ▸ Storage, plus a few that
/// Apple lumps into the opaque "System Data" slice.
enum CategoryKind {
  applications,
  documents,
  desktop,
  downloads,
  photos,
  music,
  movies,
  mail,
  messages,
  developer,
  caches,
  systemData,
  trash,
  other,
}

/// A computed category: how much space it uses and (optionally) the detailed
/// tree behind it for drill-down.
class StorageCategory {
  StorageCategory({
    required this.kind,
    required this.sizeBytes,
    required this.itemCount,
    required this.paths,
    this.root,
    this.accessDenied = false,
  });

  final CategoryKind kind;
  int sizeBytes;
  int itemCount;

  /// Source paths that were scanned to produce this category.
  final List<String> paths;

  /// Detailed tree, lazily attached for drill-down (null until requested).
  ScanNode? root;

  /// True if any source path was unreadable (size is a lower bound).
  bool accessDenied;
}
