/// A node in a scanned file-system tree.
///
/// Pure Dart (no Flutter imports) so it can be built inside a background
/// isolate and copied back to the UI isolate. The tree is strictly acyclic —
/// no parent back-references — which keeps isolate transfer cheap and safe.
class ScanNode {
  ScanNode({
    required this.path,
    required this.name,
    required this.isDirectory,
    this.sizeBytes = 0,
    this.fileCount = 0,
    this.modifiedMs,
    this.isSymlink = false,
    this.isApp = false,
    this.accessDenied = false,
    List<ScanNode>? children,
  }) : children = children ?? <ScanNode>[];

  final String path;
  final String name;
  final bool isDirectory;

  /// Aggregated size in bytes (sum of all descendants for a directory).
  int sizeBytes;

  /// Number of files contained (1 for a leaf file).
  int fileCount;

  /// Last-modified time as ms since epoch (null if unknown). Stored as int so
  /// it survives isolate copying without DateTime allocation overhead.
  int? modifiedMs;

  final bool isSymlink;

  /// True for `.app` bundles — treated as a single deletable unit in the UI.
  final bool isApp;

  /// True when the scanner couldn't read this directory (needs Full Disk
  /// Access). Its size is therefore a lower bound.
  bool accessDenied;

  final List<ScanNode> children;

  DateTime? get modified =>
      modifiedMs == null ? null : DateTime.fromMillisecondsSinceEpoch(modifiedMs!);

  bool get hasChildren => children.isNotEmpty;

  /// Sorts children (and optionally the whole subtree) by size, descending.
  void sortBySize({bool recursive = true}) {
    children.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    if (recursive) {
      for (final c in children) {
        c.sortBySize(recursive: true);
      }
    }
  }

  /// Trims the tree so only the [keep] largest children survive at each level,
  /// collapsing the remainder into a synthetic "Other" node. Keeps the UI
  /// responsive for directories with thousands of entries.
  void collapseSmall({int keep = 200}) {
    if (children.length > keep) {
      children.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
      final overflow = children.sublist(keep);
      final otherSize = overflow.fold<int>(0, (s, n) => s + n.sizeBytes);
      final otherCount = overflow.fold<int>(0, (s, n) => s + n.fileCount);
      children.removeRange(keep, children.length);
      if (otherSize > 0) {
        children.add(ScanNode(
          path: '$path/…',
          name: '${overflow.length} more items',
          isDirectory: true,
          sizeBytes: otherSize,
          fileCount: otherCount,
        ));
      }
    }
    for (final c in children) {
      c.collapseSmall(keep: keep);
    }
  }
}
