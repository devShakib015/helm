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

  // ---- Notifications ----
  static Future<void> notify(String title, String body,
      {bool sound = false}) async {
    try {
      await _ch.invokeMethod('notify', {
        'title': title,
        'body': body,
        'sound': sound,
      });
    } catch (_) {}
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
    bool caffeine = false,
  }) async {
    try {
      await _ch.invokeMethod('menuBarUpdate', {
        'segments': segments,
        'details': details,
        'clips': clips,
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
}
