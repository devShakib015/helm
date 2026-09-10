@TestOn('mac-os')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helm/core/utils/mac_paths.dart';
import 'package:helm/core/utils/native_stat.dart';
import 'package:helm/tools/uninstaller/services/uninstaller_service.dart';

/// The Uninstaller offered `/Applications/Safari.app` at 0 B. It is a symlink
/// into the read-only Cryptex, so selecting it promised a removal that could
/// never happen. The name ending in `.app` was the only test being applied.
void main() {
  // Fixtures go in ~/Applications, because the scan roots are fixed and this
  // is the one Helm scans that a test may write to.
  final root = Directory(MacPaths.userApplications);
  final real = Directory('${root.path}/ZZProbeReal.app');
  final bare = Directory('${root.path}/ZZProbeBare.app');
  final link = Link('${root.path}/ZZProbeLink.app');

  void cleanup() {
    for (final e in [link, real, bare]) {
      try {
        if (e is Link ? e.existsSync() : (e as Directory).existsSync()) {
          e.deleteSync(recursive: e is Directory);
        }
      } catch (_) {}
    }
  }

  setUp(() {
    cleanup();
    root.createSync(recursive: true);

    // A genuine bundle: directory, with an Info.plist carrying a bundle id.
    Directory('${real.path}/Contents/MacOS').createSync(recursive: true);
    File('${real.path}/Contents/Info.plist').writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.example.zzprobereal</string>
</dict></plist>
''');

    // A folder that merely ends in .app — no Info.plist, so no bundle id, so
    // nothing can be matched to it.
    bare.createSync(recursive: true);

    // The Safari shape: a symlink whose name ends in .app.
    link.createSync(real.path);
  });

  tearDown(cleanup);

  test('Safari is not offered for uninstall', () async {
    final apps = await UninstallerService().listApps();
    final names = apps.map((a) => a.name).toList();
    final paths = apps.map((a) => a.path).toList();

    expect(names, isNot(contains('Safari')),
        reason: '/Applications/Safari.app is a SIP-restricted symlink into '
            '/System/Cryptexes — it cannot be removed by anyone');
    expect(paths, isNot(contains('/Applications/Safari.app')));
  });

  test('a symlink named .app is not an installed app', () async {
    final apps = await UninstallerService().listApps();
    expect(apps.map((a) => a.name), contains('ZZProbeReal'),
        reason: 'the real bundle must still be listed');
    expect(apps.map((a) => a.name), isNot(contains('ZZProbeLink')),
        reason: 'trashing a link removes the shortcut and leaves the app');
  });

  test('a folder that only ends in .app is not a bundle', () async {
    final apps = await UninstallerService().listApps();
    expect(apps.map((a) => a.name), isNot(contains('ZZProbeBare')));
  });

  test('nothing offered is a symlink, a non-bundle, or system-locked',
      () async {
    // The invariant, rather than the three instances of it.
    for (final app in await UninstallerService().listApps()) {
      expect(FileSystemEntity.isLinkSync(app.path), isFalse,
          reason: '${app.path} is a symlink');
      expect(File('${app.path}/Contents/Info.plist').existsSync(), isTrue,
          reason: '${app.path} has no Info.plist');
      final facts = factsFor(app.path);
      expect(facts?.isSystemLocked ?? false, isFalse,
          reason: '${app.path} is locked by the system');
    }
  });

  group('the flags that decide it', () {
    test('Safari really does carry SF_RESTRICTED', () {
      // If macOS ever stops marking it, this test says so rather than the
      // filter quietly resting on an assumption that has expired.
      final facts = factsFor('/Applications/Safari.app');
      expect(facts, isNotNull, reason: 'Safari.app exists on every Mac');
      expect(facts!.flags & sfRestricted, isNot(0));
      expect(facts.isSystemLocked, isTrue);
    });

    test('an ordinary app carries none of them', () {
      final facts = factsFor(real.path)!;
      expect(facts.flags & (sfImmutable | sfRestricted | sfNoUnlink), 0);
      expect(facts.isSystemLocked, isFalse);
    });

    test('a user-set immutable flag is not treated as system-locked', () {
      // `chflags uchg` is the user's own doing and the user can undo it, so it
      // must not hide an app from the list.
      Process.runSync('/usr/bin/chflags', ['uchg', real.path]);
      addTearDown(() => Process.runSync('/usr/bin/chflags', ['nouchg', real.path]));
      final facts = factsFor(real.path)!;
      expect(facts.flags & 0x2, isNot(0), reason: 'UF_IMMUTABLE is set');
      expect(facts.isSystemLocked, isFalse);
    });
  });
}
