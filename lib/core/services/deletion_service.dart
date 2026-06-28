import 'dart:io';
import 'dart:isolate';

import 'native_bridge.dart';

class DeletionResult {
  const DeletionResult({required this.removed, required this.failed});
  final List<String> removed;
  final List<String> failed;

  bool get allOk => failed.isEmpty;
  int get removedCount => removed.length;
}

/// Removes files and folders. The default everywhere in Helm is
/// [moveToTrash] — recoverable, matching the user's "delete is never
/// destructive" expectation. [deletePermanently] exists only for things that
/// are already disposable (emptying the Trash itself).
class DeletionService {
  /// Recoverable removal via the native Trash API.
  Future<DeletionResult> moveToTrash(List<String> paths) async {
    if (paths.isEmpty) return const DeletionResult(removed: [], failed: []);
    final res = await NativeBridge.moveToTrash(paths);
    return DeletionResult(removed: res.trashed, failed: res.failed);
  }

  /// Irreversible removal — used for emptying the Trash. Runs in a background
  /// isolate so recursive deletes never block the UI.
  Future<DeletionResult> deletePermanently(List<String> paths) async {
    if (paths.isEmpty) return const DeletionResult(removed: [], failed: []);
    return Isolate.run(() => _deleteAll(paths));
  }

  static DeletionResult _deleteAll(List<String> paths) {
    final removed = <String>[];
    final failed = <String>[];
    for (final p in paths) {
      try {
        final type = FileSystemEntity.typeSync(p, followLinks: false);
        switch (type) {
          case FileSystemEntityType.directory:
            Directory(p).deleteSync(recursive: true);
          case FileSystemEntityType.notFound:
            break; // already gone — count as success
          default:
            File(p).deleteSync();
        }
        removed.add(p);
      } catch (_) {
        failed.add(p);
      }
    }
    return DeletionResult(removed: removed, failed: failed);
  }
}
