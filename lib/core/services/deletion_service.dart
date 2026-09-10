import 'dart:io';
import 'dart:isolate';

import '../models/removal_failure.dart';
import '../utils/mac_paths.dart';
import 'native_bridge.dart';

class DeletionResult {
  const DeletionResult({required this.removed, required this.failed});
  final List<String> removed;

  /// Each refusal with the reason attached. A bare count here is what made
  /// "1 skipped" unanswerable — see [RemovalFailure].
  final List<RemovalFailure> failed;

  bool get allOk => failed.isEmpty;
  int get removedCount => removed.length;

  /// True when every refusal would have gone through with admin rights, which
  /// is the case the UI has something useful to say about.
  bool get allNeedAdmin =>
      failed.isNotEmpty && failed.every((f) => f.needsAdmin);
}

/// Removes files and folders. The default everywhere in Helm is
/// [moveToTrash] — recoverable, matching the user's "delete is never
/// destructive" expectation. [deletePermanently] exists only for things that
/// are already disposable (emptying the Trash itself).
///
/// Both methods re-check every path against [MacPaths] before touching it.
/// That is deliberately redundant with the scanners' filtering: the scanners
/// decide what to *show*, and a classification bug up there must never be able
/// to destroy data down here. Anything refused is reported in [failed] rather
/// than silently dropped.
class DeletionService {
  /// Recoverable removal via the native Trash API.
  Future<DeletionResult> moveToTrash(List<String> paths) async {
    if (paths.isEmpty) return const DeletionResult(removed: [], failed: []);

    final allowed = <String>[];
    final refused = <RemovalFailure>[];
    for (final p in paths) {
      if (MacPaths.isDeletionForbidden(p)) {
        refused.add(RemovalFailure.guarded(p));
      } else {
        allowed.add(p);
      }
    }
    if (allowed.isEmpty) {
      return DeletionResult(removed: const [], failed: refused);
    }

    final res = await NativeBridge.moveToTrash(allowed);
    return DeletionResult(
      removed: res.trashed,
      failed: [...res.failed, ...refused],
    );
  }

  /// Irreversible removal. Permitted ONLY inside the user's Trash — the one
  /// place where the contents are already discarded. Anything else is refused,
  /// no matter which code path asked. Runs in a background isolate so
  /// recursive deletes never block the UI.
  Future<DeletionResult> deletePermanently(List<String> paths) async {
    if (paths.isEmpty) return const DeletionResult(removed: [], failed: []);

    final allowed = <String>[];
    final refused = <RemovalFailure>[];
    for (final p in paths) {
      final ok = MacPaths.isInsideTrash(p) && !MacPaths.isDeletionForbidden(p);
      if (ok) {
        allowed.add(p);
      } else {
        refused.add(RemovalFailure.guarded(p));
      }
    }
    if (allowed.isEmpty) {
      return DeletionResult(removed: const [], failed: refused);
    }

    final res = await Isolate.run(() => _deleteAll(allowed));
    return DeletionResult(
      removed: res.removed,
      failed: [...res.failed, ...refused],
    );
  }

  static DeletionResult _deleteAll(List<String> paths) {
    final removed = <String>[];
    final failed = <RemovalFailure>[];
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
      } on FileSystemException catch (e) {
        // errno is the only honest source here: emptying the Trash trips over
        // items another user owns, and "skipped" without that is the same dead
        // end this whole change exists to remove.
        final errno = e.osError?.errorCode;
        failed.add(RemovalFailure(
          path: p,
          reason: switch (errno) {
            1 || 13 => RemovalReason.permission,
            2 => RemovalReason.notFound,
            16 || 30 => RemovalReason.inUse,
            _ => RemovalReason.unknown,
          },
          message: e.osError?.message ?? e.message,
        ));
      } catch (e) {
        failed.add(RemovalFailure(
          path: p,
          reason: RemovalReason.unknown,
          message: e.toString(),
        ));
      }
    }
    return DeletionResult(removed: removed, failed: failed);
  }
}
