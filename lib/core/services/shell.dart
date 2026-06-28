import 'dart:async';
import 'dart:io';

/// Thin wrapper around running command-line tools. The new tools (Memory,
/// Battery, Network, …) read live system state by parsing the output of
/// standard macOS utilities (`vm_stat`, `pmset`, `netstat`, `system_profiler`).
class Shell {
  Shell._();

  static Future<({int code, String out, String err})> run(
    String exe,
    List<String> args, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    try {
      final r = await Process.run(exe, args).timeout(timeout);
      return (
        code: r.exitCode,
        out: (r.stdout is String) ? r.stdout as String : '',
        err: (r.stderr is String) ? r.stderr as String : '',
      );
    } on TimeoutException {
      return (code: -1, out: '', err: 'timed out');
    } catch (e) {
      return (code: -1, out: '', err: e.toString());
    }
  }

  /// Convenience: just the stdout (empty string on failure).
  static Future<String> out(
    String exe,
    List<String> args, {
    Duration timeout = const Duration(seconds: 20),
  }) async =>
      (await run(exe, args, timeout: timeout)).out;

  /// Runs a shell command requesting administrator privileges via a native
  /// macOS auth prompt. Used only for the few actions that genuinely need root
  /// (e.g. flushing the DNS cache). Returns true on success.
  static Future<bool> runAsAdmin(String command, {String? prompt}) async {
    final script =
        'do shell script "$command" with administrator privileges${prompt != null ? ' with prompt "$prompt"' : ''}';
    final r = await run('osascript', ['-e', script], timeout: const Duration(seconds: 120));
    return r.code == 0;
  }
}
