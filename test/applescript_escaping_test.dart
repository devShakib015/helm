import 'package:flutter_test/flutter_test.dart';
import 'package:helm/tools/startup/services/startup_service.dart';

/// Login-item names come from installed apps and get embedded in an
/// AppleScript string. Anything that can terminate that string early can run
/// arbitrary AppleScript, so the escaping is pinned down here.
void main() {
  String esc(String v) => StartupService.escapeAppleScript(v);

  test('ordinary names are untouched', () {
    expect(esc('Dropbox'), 'Dropbox');
    expect(esc('Google Drive'), 'Google Drive');
  });

  test('quotes are escaped', () {
    expect(esc('My "App"'), r'My \"App\"');
  });

  test('backslashes are escaped BEFORE quotes', () {
    // The bug: escaping only quotes turns  a\"  into  a\\"  which closes the
    // string. Backslash-first keeps it inert.
    expect(esc(r'a\'), r'a\\');
    expect(esc('a\\"'), r'a\\\"');
  });

  test('a crafted name cannot break out of the string literal', () {
    const attack = r'x" & (do shell script "touch /tmp/pwned") & "';
    final out = esc(attack);
    // Every quote in the result must be backslash-escaped.
    for (var i = 0; i < out.length; i++) {
      if (out[i] == '"') {
        expect(i > 0 && out[i - 1] == r'\', isTrue,
            reason: 'unescaped quote at $i in: $out');
      }
    }
  });
}
