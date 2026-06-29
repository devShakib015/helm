import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// A preset "keep awake" duration. `null` duration means indefinite.
class AwakeDuration {
  const AwakeDuration(this.label, this.duration);
  final String label;
  final Duration? duration;
}

const List<AwakeDuration> kAwakeDurations = [
  AwakeDuration('Indefinitely', null),
  AwakeDuration('15 minutes', Duration(minutes: 15)),
  AwakeDuration('30 minutes', Duration(minutes: 30)),
  AwakeDuration('1 hour', Duration(hours: 1)),
  AwakeDuration('2 hours', Duration(hours: 2)),
  AwakeDuration('5 hours', Duration(hours: 5)),
];

/// Keeps the Mac awake by holding a `caffeinate` process. Prevents display and
/// system idle sleep (and declares the user active) for either an indefinite
/// span or a chosen duration; when a timed session ends, `caffeinate` exits on
/// its own and we reflect that. The process is killed on deactivate / dispose,
/// so sleep is never blocked after Helm quits.
class KeepAwakeController extends ChangeNotifier {
  Process? _proc;
  Duration? _duration; // null → indefinite
  DateTime? _endsAt;
  Timer? _ticker;
  bool _disposed = false;

  bool get active => _proc != null;
  Duration? get duration => _duration;

  /// Remaining time for a timed session, or null when indefinite / inactive.
  Duration? get remaining {
    if (_endsAt == null) return null;
    final left = _endsAt!.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  Future<void> activate({Duration? duration}) async {
    await deactivate();
    final args = <String>['-disu']; // display + idle-system + system + user
    if (duration != null) {
      args.addAll(['-t', '${duration.inSeconds}']);
    }
    try {
      final proc = await Process.start('/usr/bin/caffeinate', args);
      _proc = proc;
      _duration = duration;
      _endsAt = duration == null ? null : DateTime.now().add(duration);
      // When caffeinate exits (timer elapsed or killed), clear our state.
      proc.exitCode.then((_) {
        if (_proc == proc) _reset();
      });
      if (duration != null) {
        _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
          if (!_disposed) notifyListeners();
        });
      }
    } catch (_) {
      _reset();
    }
    _safeNotify();
  }

  Future<void> deactivate() async {
    _ticker?.cancel();
    _ticker = null;
    final p = _proc;
    _proc = null;
    _duration = null;
    _endsAt = null;
    p?.kill();
    _safeNotify();
  }

  Future<void> toggle({Duration? duration}) =>
      active ? deactivate() : activate(duration: duration);

  void _reset() {
    _ticker?.cancel();
    _ticker = null;
    _proc = null;
    _duration = null;
    _endsAt = null;
    _safeNotify();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _proc?.kill();
    _proc = null;
    super.dispose();
  }
}
