import 'dart:async';
import 'dart:isolate';

/// Incremental progress emitted by a running scan.
class ScanTick {
  const ScanTick({this.bytes = 0, this.files = 0, this.path});
  final int bytes;
  final int files;
  final String? path;
}

/// Boot payload handed to an isolate entry point: a port to report back on and
/// the scan's argument.
class ScanBoot<A> {
  const ScanBoot(this.sendPort, this.arg);
  final SendPort sendPort;
  final A arg;
}

/// Wrapper an isolate sends back to deliver its final result.
class ScanResultMsg {
  const ScanResultMsg(this.data);
  final Object? data;
}

/// Thrown into [ScanSession.result] when a scan is cancelled, so the awaiting
/// frame unwinds instead of hanging forever.
class ScanCancelled implements Exception {
  const ScanCancelled();
  @override
  String toString() => 'Scan cancelled';
}

/// A live scan: a stream of progress ticks plus a future that resolves with the
/// final result. Cancelling kills the isolate immediately AND completes
/// [result] with [ScanCancelled] so callers awaiting it don't leak.
class ScanSession<T> {
  ScanSession._(this._rp, this._ticks, this._completer, this._isolate);

  final ReceivePort _rp;
  final StreamController<ScanTick> _ticks;
  final Completer<T> _completer;
  final Future<Isolate> _isolate;

  Stream<ScanTick> get ticks => _ticks.stream;
  Future<T> get result => _completer.future;

  bool _closed = false;

  Future<void> cancel() async {
    if (_closed) return;
    _closed = true;
    if (!_completer.isCompleted) {
      _completer.completeError(const ScanCancelled());
    }
    try {
      (await _isolate).kill(priority: Isolate.immediate);
    } catch (_) {}
    _dispose();
  }

  void _dispose() {
    if (!_ticks.isClosed) _ticks.close();
    _rp.close();
  }
}

/// Spawns [entry] in a background isolate, wiring its messages into a
/// [ScanSession]. The entry must send [ScanTick]s for progress and exactly one
/// [ScanResultMsg] when done.
ScanSession<T> startScan<A, T>(
  void Function(ScanBoot<A>) entry,
  A arg,
) {
  final rp = ReceivePort();
  final ticks = StreamController<ScanTick>.broadcast();
  final completer = Completer<T>();

  final isolate = Isolate.spawn<ScanBoot<A>>(
    entry,
    ScanBoot<A>(rp.sendPort, arg),
    onError: rp.sendPort,
    errorsAreFatal: true,
    debugName: 'helm-scan',
  );

  late final ScanSession<T> session;

  rp.listen((dynamic msg) {
    if (msg is ScanTick) {
      if (!ticks.isClosed) ticks.add(msg);
    } else if (msg is ScanResultMsg) {
      if (!completer.isCompleted) completer.complete(msg.data as T);
      if (!ticks.isClosed) ticks.close();
      rp.close();
    } else if (msg is List) {
      // Uncaught isolate error arrives as [error, stackTrace].
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('Scan failed: ${msg.isNotEmpty ? msg.first : 'unknown'}'),
        );
      }
      if (!ticks.isClosed) ticks.close();
      rp.close();
    }
  });

  session = ScanSession<T>._(rp, ticks, completer, isolate);
  return session;
}
