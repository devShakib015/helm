import 'package:flutter/material.dart';

import 'tool_registry.dart';

/// Sub-sections within the Storage tool, shown as nested sidebar items.
enum StorageSection { overview, categories, cleaner, largeFiles, duplicates }

extension StorageSectionX on StorageSection {
  String get label => switch (this) {
        StorageSection.overview => 'Overview',
        StorageSection.categories => 'Categories',
        StorageSection.cleaner => 'System Junk',
        StorageSection.largeFiles => 'Large & Old',
        StorageSection.duplicates => 'Duplicates',
      };

  IconData get icon => switch (this) {
        StorageSection.overview => Icons.dashboard_rounded,
        StorageSection.categories => Icons.donut_small_rounded,
        StorageSection.cleaner => Icons.cleaning_services_rounded,
        StorageSection.largeFiles => Icons.inventory_2_rounded,
        StorageSection.duplicates => Icons.content_copy_rounded,
      };
}

/// Top-level navigation state: which tool is showing in the main pane, which
/// sidebar categories are expanded, the (drag-resizable) sidebar width, and —
/// for Storage — which section.
class AppController extends ChangeNotifier {
  ToolId _current = ToolId.dashboard;
  ToolId get current => _current;

  StorageSection _storageSection = StorageSection.overview;
  StorageSection get storageSection => _storageSection;

  // ---- Sidebar layout ----
  static const double minSidebarWidth = 208;
  static const double maxSidebarWidth = 380;
  double _sidebarWidth = 248;
  double get sidebarWidth => _sidebarWidth;

  void setSidebarWidth(double width) {
    final clamped = width.clamp(minSidebarWidth, maxSidebarWidth);
    if (clamped == _sidebarWidth) return;
    _sidebarWidth = clamped;
    notifyListeners();
  }

  // ---- Category expand / collapse ----
  // Start with Monitor open; the rest collapse so the rail stays tidy.
  final Set<ToolCategory> _expanded = {ToolCategory.monitor};

  bool isExpanded(ToolCategory c) => _expanded.contains(c);

  void toggleCategory(ToolCategory c) {
    if (!_expanded.remove(c)) _expanded.add(c);
    notifyListeners();
  }

  void select(ToolId id) {
    if (!toolMeta(id).available) return; // coming-soon tools are inert
    // Make sure the chosen tool's category is open so it's visible in the rail.
    final cat = toolMeta(id).category;
    final expandedChanged = cat != null && _expanded.add(cat);
    if (_current == id) {
      if (expandedChanged) notifyListeners();
      return;
    }
    _current = id;
    notifyListeners();
  }

  void selectStorageSection(StorageSection section) {
    if (_storageSection == section) return;
    _storageSection = section;
    notifyListeners();
  }
}
