import 'package:flutter_test/flutter_test.dart';
import 'package:helm/core/services/deletion_service.dart';
import 'package:helm/core/services/native_bridge.dart';
import 'package:helm/core/utils/mac_paths.dart';

/// These tests guard the single most dangerous thing Helm does: removing
/// files from a stranger's Mac. Every case here represents data loss if the
/// invariant ever regresses, so they are deliberately blunt and exhaustive.
void main() {
  final home = MacPaths.home;

  group('isDeletionForbidden — container roots are never removable', () {
    for (final p in <String>[
      '/',
      '/Users',
      '/Applications',
      '/Library',
      '/System',
      '/usr',
      '/private',
      '/Volumes',
      '/etc',
    ]) {
      test('refuses $p', () => expect(MacPaths.isDeletionForbidden(p), isTrue));
    }

    test('refuses the home folder itself', () {
      expect(MacPaths.isDeletionForbidden(home), isTrue);
    });

    for (final name in <String>[
      'Desktop', 'Documents', 'Downloads', 'Pictures', 'Music', 'Movies',
      'Library', 'Library/Caches', 'Library/Application Support',
      'Library/Preferences', '.Trash',
    ]) {
      test('refuses ~/$name wholesale', () {
        expect(MacPaths.isDeletionForbidden('$home/$name'), isTrue);
      });
    }
  });

  group('isDeletionForbidden — malformed input is refused', () {
    for (final p in <String>[
      '',
      '   ',
      'relative/path',
      '~/Library/Caches',            // unexpanded tilde is not absolute
      '/Users/x/../../etc',          // traversal
      '/Users/x/..',
    ]) {
      test('refuses ${p.isEmpty ? "(empty)" : p}',
          () => expect(MacPaths.isDeletionForbidden(p), isTrue));
    }

    test('cosmetic differences cannot defeat the guard', () {
      expect(MacPaths.isDeletionForbidden('$home/Library/Caches/'), isTrue);
      expect(MacPaths.isDeletionForbidden('$home//Library//Caches'), isTrue);
      expect(MacPaths.isDeletionForbidden('  $home/Library/Caches  '), isTrue);
    });
  });

  group('isDeletionForbidden — real cleanup targets stay allowed', () {
    for (final p in <String>[
      'Library/Caches/com.example.app',
      'Library/Logs/SomeApp',
      'Library/Developer/Xcode/DerivedData',
      '.Trash/old-file.zip',
      'Downloads/installer.dmg',
    ]) {
      test('allows ~/$p', () {
        expect(MacPaths.isDeletionForbidden('$home/$p'), isFalse);
      });
    }
  });

  group('isInsideTrash', () {
    test('accepts items inside the Trash', () {
      expect(MacPaths.isInsideTrash('$home/.Trash/thing.txt'), isTrue);
      expect(MacPaths.isInsideTrash('$home/.Trash/dir/nested.txt'), isTrue);
    });

    test('rejects the Trash folder itself and everything outside it', () {
      expect(MacPaths.isInsideTrash(MacPaths.userTrash), isFalse);
      expect(MacPaths.isInsideTrash('$home/Documents/thing.txt'), isFalse);
      expect(MacPaths.isInsideTrash('/tmp/thing.txt'), isFalse);
      // A sibling folder that merely starts with the same characters.
      expect(MacPaths.isInsideTrash('$home/.TrashBackup/x'), isFalse);
    });
  });

  group('DeletionService refuses unsafe work without touching the disk', () {
    final svc = DeletionService();

    test('permanent delete refuses anything outside the Trash', () async {
      final targets = [
        '$home/Documents/important.txt',
        '$home/Library/Caches/com.example.app',
        '/Applications',
        home,
      ];
      final r = await svc.deletePermanently(targets);
      expect(r.removed, isEmpty, reason: 'nothing outside the Trash may be destroyed');
      expect(r.failed.map((f) => f.path).toSet(), targets.toSet());
    });

    test('permanent delete refuses the Trash folder itself', () async {
      final r = await svc.deletePermanently([MacPaths.userTrash]);
      expect(r.removed, isEmpty);
      expect(r.failed.map((f) => f.path), [MacPaths.userTrash]);
    });

    test('move-to-trash refuses protected and container paths', () async {
      final targets = ['/System/Library', '/', home, '$home/Library'];
      final r = await svc.moveToTrash(targets);
      expect(r.removed, isEmpty);
      expect(r.failed.map((f) => f.path).toSet(), targets.toSet());
    });

    test('empty input is a no-op, not an error', () async {
      expect((await svc.moveToTrash([])).allOk, isTrue);
      expect((await svc.deletePermanently([])).allOk, isTrue);
    });
  });

  group('isSensitiveName — login/account state is never offered for cleanup', () {
    for (final n in <String>[
      'com.apple.accounts', 'com.apple.accountsd',
      'com.apple.ak', 'com.apple.akd',
      'com.apple.identityservices', 'com.apple.iCloudHelper',
      'com.apple.commerce', 'com.apple.storekitagent',
      'com.apple.amsaccountsd', 'com.apple.AppleMediaServices',
      'com.apple.itunescloudd', 'com.apple.passd',
      'com.apple.dt.Xcode', 'com.apple.mail', 'com.apple.Messages',
      'SomeApp.keychain', 'vendor-credentials', 'app.authtoken',
    ]) {
      test('protects $n', () => expect(MacPaths.isSensitiveName(n), isTrue));
    }

    test('ordinary caches remain cleanable', () {
      for (final n in <String>[
        'com.google.Chrome', 'Homebrew', 'CocoaPods', 'com.spotify.client',
      ]) {
        expect(MacPaths.isSensitiveName(n), isFalse, reason: n);
      }
    });
  });

  group('NativeBridge is the chokepoint every tool shares', () {
    // The Uninstaller, Privacy and Startup call NativeBridge directly rather
    // than going through DeletionService, so the guard has to live here or it
    // simply is not enforced for three of the four deletion paths.
    test('refuses forbidden paths without ever reaching the platform', () async {
      final targets = ['/', '/System/Library', home, '$home/Library', ''];
      final r = await NativeBridge.moveToTrash(targets);
      expect(r.trashed, isEmpty);
      expect(r.failed.map((f) => f.path).toSet(), targets.toSet());
    });

    test('an empty request is a no-op', () async {
      final r = await NativeBridge.moveToTrash([]);
      expect(r.trashed, isEmpty);
      expect(r.failed, isEmpty);
    });
  });
}
