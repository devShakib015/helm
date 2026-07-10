import 'package:flutter/services.dart';

/// Dart wrapper over the Swift `helm/system` channel: live system stats, the
/// menu-bar status item, clipboard (pasteboard) access, and login-item control.
/// Every call degrades gracefully if the channel is unavailable.
class NativeSystem {
  static const MethodChannel _ch = MethodChannel('helm/system');

  /// Called when a color is picked from the menu-bar "Pick Color from Screen"
  /// item (native → Dart), so the Color Picker tool can record it.
  static void Function(String hex)? onColorPicked;

  /// Called when a menu-bar action fires (native → Dart), e.g. "toggleCaffeine".
  static void Function(String action)? onMenuAction;

  /// Called when a menu-bar clipboard item OR quick-paste popup entry is
  /// clicked (native → Dart) with the item's stable id (its dedupe key) —
  /// never a positional index, which could mis-target after the list shifts.
  /// [fromPopup] is true for the hotkey popup, where auto-paste may follow.
  static void Function(String id, bool fromPopup)? onClipCopy;

  /// Called when a clicked notification asks for a specific tool to open.
  static void Function(String tool)? onOpenTool;

  /// Wires the incoming (native → Dart) call handler. Safe to call once at
  /// startup; the Swift side keeps its own outbound handler on the same channel.
  static void registerHandlers() {
    _ch.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onColorPicked':
          final hex = call.arguments;
          if (hex is String) onColorPicked?.call(hex);
        case 'onMenuAction':
          final action = call.arguments;
          if (action is String) onMenuAction?.call(action);
        case 'onClipCopy':
          final args = call.arguments;
          if (args is Map) {
            final id = args['id'];
            if (id is String) {
              onClipCopy?.call(id, args['popup'] == true);
            }
          }
        case 'onOpenTool':
          final tool = call.arguments;
          if (tool is String) onOpenTool?.call(tool);
      }
      return null;
    });
  }

  static Future<Map<String, dynamic>?> systemStats() async {
    try {
      final r = await _ch.invokeMethod<dynamic>('systemStats');
      return r == null ? null : Map<String, dynamic>.from(r as Map);
    } catch (_) {
      return null;
    }
  }

  // ---- Clipboard (NSPasteboard) ----
  static Future<int> pbChangeCount() async {
    try {
      return await _ch.invokeMethod<int>('pbChangeCount') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<String?> pbReadText() async {
    try {
      return await _ch.invokeMethod<String>('pbReadText');
    } catch (_) {
      return null;
    }
  }

  static Future<bool> pbConcealed() async {
    try {
      return await _ch.invokeMethod<bool>('pbConcealed') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> pbWriteText(String text) async {
    try {
      return await _ch.invokeMethod<bool>('pbWriteText', {'text': text}) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Rich pasteboard read: `kind` is `file` (paths only — contents are never
  /// read), `image` (bounded PNG bytes + thumbnail), `text` (capped), or
  /// `none`.
  static Future<Map<String, dynamic>?> pbRead() async {
    try {
      final r = await _ch.invokeMethod<dynamic>('pbRead');
      return r == null ? null : Map<String, dynamic>.from(r as Map);
    } catch (_) {
      return null;
    }
  }

  /// Puts file references back on the pasteboard (pastes like a Finder copy).
  static Future<bool> pbWriteFiles(List<String> paths) async {
    try {
      return await _ch.invokeMethod<bool>('pbWriteFiles', {'paths': paths}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Puts an image (read from a PNG file on disk) back on the pasteboard.
  static Future<bool> pbWriteImage(String path) async {
    try {
      return await _ch.invokeMethod<bool>('pbWriteImage', {'path': path}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Puts in-memory PNG bytes back on the pasteboard (used by "clear on quit"
  /// mode, where images are never written to disk).
  static Future<bool> pbWriteImageData(Uint8List data) async {
    try {
      return await _ch.invokeMethod<bool>('pbWriteImageData', {'data': data}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  // ---- Notifications ----
  /// [tool]: a ToolId name; clicking the notification opens Helm on that tool.
  static Future<void> notify(String title, String body,
      {bool sound = false, String? tool}) async {
    try {
      await _ch.invokeMethod('notify', {
        'title': title,
        'body': body,
        'sound': sound,
        'tool': ?tool,
      });
    } catch (_) {}
  }

  // ---- Quick-paste popup (global hotkey) ----
  static Future<void> setClipHotkey(
      {required bool enabled, int keyCode = 9, int modifiers = 0}) async {
    try {
      await _ch.invokeMethod('setClipHotkey', {
        'enabled': enabled,
        'keyCode': keyCode,
        'modifiers': modifiers,
      });
    } catch (_) {}
  }

  /// Posts ⌘V to the frontmost app (no-op without the Accessibility grant).
  static Future<void> simulatePaste() async {
    try {
      await _ch.invokeMethod('simulatePaste');
    } catch (_) {}
  }

  /// Whether Helm holds the Accessibility grant (needed for auto-paste).
  static Future<bool> axTrusted() async {
    try {
      return await _ch.invokeMethod<bool>('axTrusted') ?? false;
    } catch (_) {
      return false;
    }
  }

  // ---- Color sampler (system eyedropper) ----
  /// Shows the macOS color sampler and returns the picked color as `#RRGGBB`,
  /// or null if the user cancelled.
  static Future<String?> sampleColor() async {
    try {
      return await _ch.invokeMethod<String>('sampleColor');
    } catch (_) {
      return null;
    }
  }

  // ---- Menu bar ----
  static Future<void> menuBarUpdate({
    required List<Map<String, String>> segments,
    List<String> details = const [],
    List<String> clips = const [],
    List<String> clipIds = const [],
    bool caffeine = false,
  }) async {
    try {
      await _ch.invokeMethod('menuBarUpdate', {
        'segments': segments,
        'details': details,
        'clips': clips,
        'clipIds': clipIds,
        'caffeine': caffeine,
      });
    } catch (_) {}
  }

  static Future<void> menuBarSetVisible(bool visible) async {
    try {
      await _ch.invokeMethod('menuBarSetVisible', {'visible': visible});
    } catch (_) {}
  }

  // ---- Lifecycle / login item ----
  static Future<void> setResident(bool resident) async {
    try {
      await _ch.invokeMethod('setResident', {'resident': resident});
    } catch (_) {}
  }

  static Future<bool> setLaunchAtLogin(bool enabled) async {
    try {
      return await _ch.invokeMethod<bool>('setLaunchAtLogin', {'enabled': enabled}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> getLaunchAtLogin() async {
    try {
      return await _ch.invokeMethod<bool>('getLaunchAtLogin') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> showWindow() async {
    try {
      await _ch.invokeMethod('showWindow');
    } catch (_) {}
  }

  /// Zooms the window (fills the screen / restores), like double-clicking a
  /// native title bar.
  static Future<void> zoomWindow() async {
    try {
      await _ch.invokeMethod('zoomWindow');
    } catch (_) {}
  }

  /// Spawns a fresh Helm instance and quits this one — needed for a new Full
  /// Disk Access grant to take effect.
  static Future<void> relaunchApp() async {
    try {
      await _ch.invokeMethod('relaunchApp');
    } catch (_) {}
  }
}
