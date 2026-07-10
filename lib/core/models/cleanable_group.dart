/// Categories of reclaimable "junk" the cleaner can scan for and remove.
enum CleanupKind {
  userCache,
  systemCache,
  userLogs,
  systemLogs,
  trash,
  downloads,
  savedAppState,
  developerJunk,
  browserCache,
  mailDownloads,
  appLeftovers,
  brokenLoginItems,
  languageFiles,
  oldUpdates,
}

/// How aggressive a cleanup is. Safe items are pre-selected; caution items are
/// shown unchecked so the user opts in deliberately.
enum CleanupRisk { safe, caution }

/// A single removable item (a file or a directory).
class CleanableItem {
  CleanableItem({
    required this.path,
    required this.name,
    required this.sizeBytes,
    this.modifiedMs,
    this.detail,
    bool? selected,
    this.risk = CleanupRisk.safe,
  }) : selected = selected ?? (risk == CleanupRisk.safe);

  final String path;
  final String name;
  final int sizeBytes;
  final int? modifiedMs;

  /// Optional sub-label, e.g. the owning app for a cache folder.
  final String? detail;

  final CleanupRisk risk;

  /// UI-mutable selection state.
  bool selected;

  DateTime? get modified =>
      modifiedMs == null ? null : DateTime.fromMillisecondsSinceEpoch(modifiedMs!);
}

/// A named group of cleanable items (e.g. "User Caches", "Xcode DerivedData").
class CleanableGroup {
  CleanableGroup({
    required this.kind,
    required this.title,
    required this.description,
    required this.risk,
    List<CleanableItem>? items,
  }) : items = items ?? <CleanableItem>[];

  final CleanupKind kind;
  final String title;
  final String description;
  final CleanupRisk risk;
  final List<CleanableItem> items;

  int get totalBytes =>
      items.fold(0, (sum, item) => sum + item.sizeBytes);

  int get selectedBytes => items
      .where((i) => i.selected)
      .fold(0, (sum, item) => sum + item.sizeBytes);

  int get selectedCount => items.where((i) => i.selected).length;

  bool get isEmpty => items.isEmpty;

  /// True only when literally every item is ticked — partial selections show
  /// as the checkbox's indeterminate state instead of a (dishonest) full tick.
  bool get allSelected => items.isNotEmpty && items.every((i) => i.selected);

  bool get noneSelected => items.every((i) => !i.selected);

  /// The group-header checkbox. Checking a MIXED group only ticks its SAFE
  /// items — caution items (release archives, simulators…) must be ticked
  /// individually so nothing risky rides along with a broad sweep. A group
  /// that is uniformly caution is different: ticking its header is already an
  /// explicit single-risk decision, so it selects everything. Unchecking
  /// always clears all.
  void selectAll(bool value) {
    if (!value) {
      for (final item in items) {
        item.selected = false;
      }
      return;
    }
    final hasSafe = items.any((i) => i.risk == CleanupRisk.safe);
    for (final item in items) {
      if (!hasSafe || item.risk == CleanupRisk.safe) item.selected = true;
    }
  }

  /// The "Select Safe" sweep: STRICTLY risk == safe items, never the
  /// uniform-caution fallback above — a broad "select everything safe" must
  /// not tick archives/simulators just because their group has no safe
  /// siblings on this machine.
  void selectSafeOnly() {
    for (final item in items) {
      item.selected = item.risk == CleanupRisk.safe;
    }
  }
}
