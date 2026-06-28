import 'package:flutter/services.dart';

/// Thin wrapper over the Swift `helm/native` MethodChannel. Only two things
/// genuinely need native code: moving items to the Trash (so they're
/// recoverable) and reading the volume's purgeable capacity (which only the
/// `URLResourceValues` API exposes accurately).
class NativeBridge {
  static const MethodChannel _channel = MethodChannel('helm/native');

  /// Moves [paths] to the macOS Trash. Returns which succeeded and which failed.
  static Future<({List<String> trashed, List<String> failed})> moveToTrash(
      List<String> paths) async {
    try {
      final res = await _channel.invokeMethod<dynamic>('moveToTrash', {
        'paths': paths,
      });
      final map = Map<String, dynamic>.from(res as Map);
      return (
        trashed: List<String>.from(map['trashed'] as List? ?? const []),
        failed: List<String>.from(map['failed'] as List? ?? const []),
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
