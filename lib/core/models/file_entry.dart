/// A single file surfaced by the large-files or duplicates scanners.
class FileEntry {
  const FileEntry({
    required this.path,
    required this.name,
    required this.sizeBytes,
    this.modifiedMs,
  });

  final String path;
  final String name;
  final int sizeBytes;
  final int? modifiedMs;

  DateTime? get modified =>
      modifiedMs == null ? null : DateTime.fromMillisecondsSinceEpoch(modifiedMs!);

  /// Lower-cased extension without the dot, e.g. `mov`, `zip`, `dmg`.
  String get ext {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  /// Parent directory path, for display.
  String get directory {
    final i = path.lastIndexOf('/');
    return i <= 0 ? '/' : path.substring(0, i);
  }
}
