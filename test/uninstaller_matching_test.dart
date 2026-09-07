import 'package:flutter_test/flutter_test.dart';
import 'package:helm/tools/uninstaller/services/uninstaller_service.dart';

/// The Uninstaller removes an app *and everything it can find belonging to it*.
/// A matching mistake here deletes a DIFFERENT app's data, so the rules that
/// decide ownership are pinned down explicitly.
void main() {
  group('bundlePrefix — ownership requires a segment boundary', () {
    test('an app owns itself and its own helpers', () {
      expect(UninstallerService.bundlePrefix(
          'com.acme.app', 'com.acme.app'), isTrue);
      expect(UninstallerService.bundlePrefix(
          'com.acme.app.helper', 'com.acme.app'), isTrue);
      expect(UninstallerService.bundlePrefix(
          'com.acme.app-launcher', 'com.acme.app'), isTrue);
    });

    test('it never owns a different app that merely shares a prefix', () {
      // These are the real-world pairs that used to collide.
      expect(UninstallerService.bundlePrefix(
          'com.acme.applesauce', 'com.acme.app'), isFalse);
      expect(
          UninstallerService.bundlePrefix(
              'com.microsoft.vscodeinsiders', 'com.microsoft.vscode'),
          isFalse,
          reason: 'uninstalling VS Code must not claim VS Code Insiders');
      expect(
          UninstallerService.bundlePrefix(
              'org.mozilla.firefoxdeveloperedition', 'org.mozilla.firefox'),
          isFalse,
          reason: 'uninstalling Firefox must not claim Developer Edition');
    });
  });

  group('usableBundleId — degenerate ids are rejected', () {
    test('a stub id cannot be used as a match key', () {
      // "com" would prefix-match essentially the whole Library.
      for (final bad in ['com', 'a', 'com.', '', '   ', 'noDots']) {
        expect(UninstallerService.usableBundleId(bad), '',
            reason: 'must not match on $bad');
      }
    });

    test('a real reverse-DNS id is kept, lowercased', () {
      expect(UninstallerService.usableBundleId('com.google.Chrome'),
          'com.google.chrome');
      expect(UninstallerService.usableBundleId('  com.acme.App  '),
          'com.acme.app');
    });
  });

  group('the sibling-app rule (most specific installed app wins)', () {
    // Mirrors the ownership test findLeftovers performs.
    bool claimedBy(String folder, String me, List<String> others) {
      if (!UninstallerService.bundlePrefix(folder, me)) return false;
      for (final o in others) {
        if (o.length > me.length && UninstallerService.bundlePrefix(folder, o)) {
          return false;
        }
      }
      return true;
    }

    test('Chrome does NOT claim Chrome Beta while Beta is installed', () {
      expect(
        claimedBy('com.google.chrome.beta', 'com.google.chrome',
            ['com.google.chrome.beta']),
        isFalse,
      );
    });

    test('Chrome still claims its own helper', () {
      expect(
        claimedBy('com.google.chrome.helper', 'com.google.chrome',
            ['com.google.chrome.beta']),
        isTrue,
      );
    });

    test('Chrome claims its own folder', () {
      expect(claimedBy('com.google.chrome', 'com.google.chrome', []), isTrue);
    });
  });
}
