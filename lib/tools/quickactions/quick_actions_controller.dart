import 'package:flutter/foundation.dart';

import '../../core/services/shell.dart';

/// Power-user toggles and one-shot maintenance actions, all driven by standard
/// macOS tools (`defaults`, `killall`, `osascript`, `pmset`). Toggle state is
/// read on demand so the switches reflect the system's real settings.
class QuickActionsController extends ChangeNotifier {
  QuickActionsController() {
    refresh();
  }

  bool loaded = false;
  bool _disposed = false;

  // Live toggle states.
  bool hiddenFiles = false; // Finder shows dotfiles
  bool desktopIcons = true; // Finder draws desktop icons
  bool dockAutohide = false; // Dock auto-hides
  bool darkMode = true; // system appearance

  /// Reads the current value of every toggle from the system.
  Future<void> refresh() async {
    hiddenFiles = await _readBool('com.apple.finder', 'AppleShowAllFiles',
        fallback: false);
    desktopIcons = await _readBool('com.apple.finder', 'CreateDesktop',
        fallback: true);
    dockAutohide =
        await _readBool('com.apple.dock', 'autohide', fallback: false);
    darkMode = await _readDarkMode();
    loaded = true;
    _safeNotify();
  }

  // ---- Toggles ----
  Future<void> setHiddenFiles(bool v) async {
    hiddenFiles = v;
    _safeNotify();
    await Shell.run('defaults',
        ['write', 'com.apple.finder', 'AppleShowAllFiles', '-bool', '$v']);
    await Shell.run('killall', ['Finder']);
  }

  Future<void> setDesktopIcons(bool v) async {
    desktopIcons = v;
    _safeNotify();
    await Shell.run('defaults',
        ['write', 'com.apple.finder', 'CreateDesktop', '-bool', '$v']);
    await Shell.run('killall', ['Finder']);
  }

  Future<void> setDockAutohide(bool v) async {
    dockAutohide = v;
    _safeNotify();
    await Shell.run(
        'defaults', ['write', 'com.apple.dock', 'autohide', '-bool', '$v']);
    await Shell.run('killall', ['Dock']);
  }

  Future<void> setDarkMode(bool v) async {
    darkMode = v;
    _safeNotify();
    await Shell.run('osascript', [
      '-e',
      'tell application "System Events" to tell appearance preferences to set dark mode to $v',
    ]);
  }

  // ---- One-shot actions ----
  Future<bool> restartFinder() => _killall('Finder');
  Future<bool> restartDock() => _killall('Dock');
  Future<bool> restartMenuBar() => _killall('SystemUIServer');

  Future<bool> sleepDisplay() async {
    final r = await Shell.run('pmset', ['displaysleepnow']);
    return r.code == 0;
  }

  /// Empties the Trash (permanent). The caller must confirm with the user first.
  Future<bool> emptyTrash() async {
    final r = await Shell.run('osascript', [
      '-e',
      'tell application "Finder" to empty trash',
    ]);
    return r.code == 0;
  }

  Future<bool> _killall(String process) async {
    final r = await Shell.run('killall', [process]);
    return r.code == 0;
  }

  Future<bool> _readBool(String domain, String key,
      {required bool fallback}) async {
    final r = await Shell.run('defaults', ['read', domain, key]);
    if (r.code != 0) return fallback; // key unset → system default
    final v = r.out.trim().toLowerCase();
    return v == '1' || v == 'yes' || v == 'true';
  }

  Future<bool> _readDarkMode() async {
    final r = await Shell.run('defaults', ['read', '-g', 'AppleInterfaceStyle']);
    // The key exists (== "Dark") only in dark mode; missing → light.
    return r.code == 0 && r.out.trim().toLowerCase().contains('dark');
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
