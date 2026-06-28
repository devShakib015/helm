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

/// Top-level navigation state: which tool is showing in the main pane, and —
/// for Storage — which section.
class AppController extends ChangeNotifier {
  ToolId _current = ToolId.storage;
  ToolId get current => _current;

  StorageSection _storageSection = StorageSection.overview;
  StorageSection get storageSection => _storageSection;

  void select(ToolId id) {
    if (!toolMeta(id).available) return; // coming-soon tools are inert
    if (_current == id) return;
    _current = id;
    notifyListeners();
  }

  void selectStorageSection(StorageSection section) {
    if (_storageSection == section) return;
    _storageSection = section;
    notifyListeners();
  }
}
