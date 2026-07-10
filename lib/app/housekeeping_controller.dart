import 'dart:async';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/services/native_system.dart';
import '../core/utils/byte_format.dart';
import '../core/utils/mac_paths.dart';
import 'settings_controller.dart';

/// Background housekeeping watchers:
///
/// * **Trash / Downloads size** — measured every 15 minutes with `du`; when a
///   folder crosses the user's threshold a notification fires, at most once
///   per 24 h per rule (persisted, so restarts don't re-spam).
/// * **Login-item watchdog** — every 60 s the LaunchAgents/Daemons folders are
///   compared against a persisted baseline; anything NEW triggers an
///   immediate notification that deep-links to the Startup tool.
class HousekeepingController {
  HousekeepingController(this._settings) {
    _init();
  }

  final SettingsController _settings;
  SharedPreferences? _p;

  Timer? _sizeTimer;
  Timer? _watchTimer;
  bool _disposed = false;
  bool _measuring = false;

  static const Duration _sizeEvery = Duration(minutes: 15);
  static const Duration _watchEvery = Duration(seconds: 60);
  static const Duration _cooldown = Duration(hours: 24);

  static List<String> get _loginItemDirs => [
        '${MacPaths.home}/Library/LaunchAgents',
        '/Library/LaunchAgents',
        '/Library/LaunchDaemons',
      ];

  Future<void> _init() async {
    _p = await SharedPreferences.getInstance();
    // First size pass shortly after launch (let the app settle), then steady.
    Timer(const Duration(seconds: 45), _checkSizes);
    _sizeTimer = Timer.periodic(_sizeEvery, (_) => _checkSizes());
    await _watchLoginItems(notify: false); // build/refresh the baseline quietly
    _watchTimer = Timer.periodic(_watchEvery, (_) => _watchLoginItems());
  }

  // ---- Folder-size watchers ----

  Future<void> _checkSizes() async {
    if (_disposed || _measuring) return;
    _measuring = true;
    try {
      if (_settings.hkTrashEnabled) {
        await _checkFolder(
          key: 'trash',
          path: MacPaths.userTrash,
          label: 'Trash',
          thresholdGB: _settings.hkTrashGB,
          hint: 'Empty it from the Storage tool.',
        );
      }
      if (_disposed) return;
      if (_settings.hkDownloadsEnabled) {
        await _checkFolder(
          key: 'downloads',
          path: MacPaths.downloads,
          label: 'Downloads',
          thresholdGB: _settings.hkDownloadsGB,
          hint: 'Review old files in Storage ▸ Large & Old.',
        );
      }
    } finally {
      _measuring = false;
    }
  }

  Future<void> _checkFolder({
    required String key,
    required String path,
    required String label,
    required int thresholdGB,
    required String hint,
  }) async {
    final bytes = await _folderSize(path);
    if (_disposed || bytes == null) return;
    final threshold = thresholdGB * 1000 * 1000 * 1000;
    if (bytes < threshold) return;
    // Cooldown: at most one alert per 24 h per rule — but a THRESHOLD change
    // re-arms immediately (the user just reconfigured the alert; suppressing
    // the very crossing they asked about would look broken).
    final lastMs = _p?.getInt('hk_last_$key') ?? 0;
    final lastThreshold = _p?.getInt('hk_last_${key}_t');
    final last = DateTime.fromMillisecondsSinceEpoch(lastMs);
    if (lastThreshold == thresholdGB &&
        DateTime.now().difference(last) < _cooldown) {
      return;
    }
    _p?.setInt('hk_last_$key', DateTime.now().millisecondsSinceEpoch);
    _p?.setInt('hk_last_${key}_t', thresholdGB);
    NativeSystem.notify(
      '$label is using ${formatBytes(bytes)}',
      'That\'s over your $thresholdGB GB limit. $hint',
      tool: 'storage',
    );
  }

  /// Folder size via `du -sk` (KiB), run with a hard kill on timeout so slow
  /// walks can't pile up zombie processes tick after tick. A partial size
  /// (permission errors on some entries) is still returned — it undercounts,
  /// so a threshold crossing it reports is real. Null when nothing measurable.
  Future<int?> _folderSize(String path) async {
    if (!Directory(path).existsSync()) return null;
    Process? proc;
    Timer? killer;
    try {
      proc = await Process.start('du', ['-sk', path]);
      killer = Timer(const Duration(minutes: 2), () {
        proc?.kill(ProcessSignal.sigkill);
      });
      final out = await proc.stdout.transform(const SystemEncoding().decoder).join();
      proc.stderr.drain<void>();
      await proc.exitCode;
      final kb = int.tryParse(
          out.trim().split(RegExp(r'\s+')).firstOrNull ?? '');
      return kb == null ? null : kb * 1024;
    } catch (_) {
      return null;
    } finally {
      killer?.cancel();
    }
  }

  // ---- Login-item watchdog ----

  Future<void> _watchLoginItems({bool notify = true}) async {
    if (_disposed) return;
    final current = <String>{};
    for (final dir in _loginItemDirs) {
      final d = Directory(dir);
      if (!d.existsSync()) continue;
      try {
        for (final f in d.listSync(followLinks: false)) {
          if (f.path.endsWith('.plist')) current.add(f.path);
        }
      } catch (_) {}
    }
    // "Baseline exists" must be tracked separately from "baseline is empty":
    // on a clean machine the very first login item ever added would otherwise
    // be silently swallowed as "first scan".
    final hasBaseline = _p?.containsKey('watch_login_baseline') ?? false;
    final baseline = (_p?.getStringList('watch_login_baseline') ?? []).toSet();
    if (hasBaseline && notify && _settings.watchLoginItems) {
      final added = current.difference(baseline);
      if (added.length > 3) {
        // A batch install: one summary instead of a spray of banners, and
        // no item is silently dropped.
        NativeSystem.notify(
          '${added.length} new login items installed',
          'Several launch agents were just added. Review them in Startup.',
          sound: true,
          tool: 'startup',
        );
      } else {
        for (final path in added) {
          final name = path.split('/').last.replaceAll('.plist', '');
          final scope =
              path.startsWith('/Library') ? 'system-wide' : 'for your account';
          NativeSystem.notify(
            'New login item installed',
            '$name was added $scope. Review it in Startup.',
            sound: true,
            tool: 'startup',
          );
        }
      }
    }
    // Baseline always tracks reality — even while notifications are toggled
    // off — so re-enabling the watchdog never spams about items the user
    // installed themselves in the meantime.
    if (!hasBaseline ||
        current.length != baseline.length ||
        !current.containsAll(baseline)) {
      _p?.setStringList('watch_login_baseline', current.toList());
    }
  }

  void dispose() {
    _disposed = true;
    _sizeTimer?.cancel();
    _watchTimer?.cancel();
  }
}
