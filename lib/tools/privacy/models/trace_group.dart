import 'package:flutter/widgets.dart';

/// A single privacy trace the tool can clear — either a file or a folder. Sized
/// once at scan time so the UI never has to touch the disk again.
class TraceItem {
  TraceItem({
    required this.path,
    required this.name,
    required this.sizeBytes,
    this.selected = false,
  });

  final String path;
  final String name;
  final int sizeBytes;

  /// UI-mutable selection state.
  bool selected;
}

/// A named bundle of related traces (e.g. "Recent Items", "Safari history").
///
/// [caution] groups touch genuinely sensitive data (history, shell logs); their
/// items default to unselected so the user has to opt in deliberately, and the
/// card shows a "Sensitive" pill.
class TraceGroup {
  TraceGroup({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.caution,
    List<TraceItem>? items,
  }) : items = items ?? <TraceItem>[];

  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final bool caution;
  final List<TraceItem> items;

  int get totalBytes =>
      items.fold(0, (sum, item) => sum + item.sizeBytes);

  int get selectedBytes => items
      .where((i) => i.selected)
      .fold(0, (sum, item) => sum + item.sizeBytes);

  int get selectedCount => items.where((i) => i.selected).length;

  bool get isEmpty => items.isEmpty;
  bool get allSelected => items.isNotEmpty && items.every((i) => i.selected);
  bool get noneSelected => items.every((i) => !i.selected);

  void selectAll(bool value) {
    for (final item in items) {
      item.selected = value;
    }
  }
}
