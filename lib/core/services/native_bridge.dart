import 'package:flutter/services.dart';

import '../models/removal_failure.dart';
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
  static Future<({List<String> trashed, List<RemovalFailure> failed})>
      moveToTrash(List<String> paths) async {
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
      return (trashed: const <String>[], failed: refused);
    }
    try {
      final res = await _channel.invokeMethod<dynamic>('moveToTrash', {
        'paths': allowed,
      });
      final map = Map<String, dynamic>.from(res as Map);
      final raw = map['failures'] as List? ?? const [];
      return (
        trashed: List<String>.from(map['trashed'] as List? ?? const []),
        failed: [
          for (final f in raw)
            RemovalFailure.fromNative(Map<Object?, Object?>.from(f as Map)),
          ...refused,
        ],
      );
    } on PlatformException catch (e) {
      return (trashed: const <String>[], failed: _allFailed(paths, e.message));
    } on MissingPluginException {
      return (
        trashed: const <String>[],
        failed: _allFailed(paths, 'The native removal channel is unavailable.'),
      );
    }
  }

  /// Every path failed for the same reason — the channel itself broke, so the
  /// OS never got a chance to give a per-path answer.
  static List<RemovalFailure> _allFailed(List<String> paths, String? message) => [
        for (final p in paths)
          RemovalFailure(
            path: p,
            reason: RemovalReason.unknown,
            message: message?.trim().isNotEmpty == true
                ? message!.trim()
                : 'The removal could not be carried out.',
          ),
      ];

  /// Whether this app's own bundle still validates against its signature.
  ///
  /// A bundle that does not validate cannot hold a Full Disk Access grant:
  /// macOS establishes identity from the signature before applying a TCC
  /// grant, so the switch reads ON and every protected path stays refused.
  /// Returns true when the answer is unavailable — refusing to guess is the
  /// point, and a false "your signature is broken" would be worse than saying
  /// nothing.
  static Future<bool> codeSignatureValid() async {
    try {
      final res = await _channel.invokeMethod<bool>('codeSignatureValid');
      return res ?? true;
    } on PlatformException {
      return true;
    } on MissingPluginException {
      return true;
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
