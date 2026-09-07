import 'package:flutter/services.dart';

import '../utils/mac_paths.dart';

/// Thin wrapper over the Swift `helm/native` MethodChannel. Only two things
/// genuinely need native code: moving items to the Trash (so they're
/// recoverable) and reading the volume's purgeable capacity (which only the
/// `URLResourceValues` API exposes accurately).
class NativeBridge {
  static const MethodChannel _channel = MethodChannel('helm/native');

  /// Moves [paths] to the macOS Trash. Returns which succeeded and which failed.
  /// Moves [paths] to the Trash.
  ///
  /// This is the single chokepoint every tool's removal goes through, so the
  /// safety guard lives HERE rather than in any one caller — the Uninstaller,
  /// Privacy and Startup all call this directly, and a guard placed further up
  /// would simply be bypassed. Refused paths come back in `failed`; they are
  /// never handed to the native API.
  static Future<({List<String> trashed, List<String> failed})> moveToTrash(
      List<String> paths) async {
    final allowed = <String>[];
    final refused = <String>[];
    for (final p in paths) {
      (MacPaths.isDeletionForbidden(p) ? refused : allowed).add(p);
    }
    if (allowed.isEmpty) {
      return (trashed: const <String>[], failed: refused);
    }
    try {
      final res = await _channel.invokeMethod<dynamic>('moveToTrash', {
        'paths': allowed,
      });
      final map = Map<String, dynamic>.from(res as Map);
      return (
        trashed: List<String>.from(map['trashed'] as List? ?? const []),
        failed: [
          ...List<String>.from(map['failed'] as List? ?? const []),
          ...refused,
        ],
      );
    } on PlatformException {
      return (trashed: const <String>[], failed: paths);
    } on MissingPluginException {
      return (trashed: const <String>[], failed: paths);
    }
  }

  /// Accurate capacity for the volume containing [path], including purgeable
  /// space (matches "About This Mac" ▸ Storage). Returns null if unavailable.
  static Future<Map<String, dynamic>?> volumeInfo(String path) async {
    try {
      final res = await _channel.invokeMethod<dynamic>('volumeInfo', {
        'path': path,
      });
      if (res == null) return null;
      return Map<String, dynamic>.from(res as Map);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
