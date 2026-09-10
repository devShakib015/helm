import 'package:flutter_test/flutter_test.dart';
import 'package:helm/core/models/removal_failure.dart';
import 'package:helm/core/services/deletion_service.dart';
import 'package:helm/core/utils/mac_paths.dart';

/// Every case here is one the Uninstaller hit in practice and reported as the
/// single word "skipped". The codes are the ones macOS actually returns —
/// captured from `FileManager.trashItem` against a folder whose parent is not
/// writable, which is the shape of `/Library/LaunchAgents` on a stock Mac.
void main() {
  Map<Object?, Object?> native({
    required int code,
    String domain = 'NSCocoaErrorDomain',
    String message = 'something',
    int? underCode,
    String underDomain = 'NSPOSIXErrorDomain',
    String path = '/Library/LaunchAgents/com.example.plist',
  }) =>
      {
        'path': path,
        'code': code,
        'domain': domain,
        'message': message,
        if (underCode != null) ...{
          'underlyingCode': underCode,
          'underlyingDomain': underDomain,
        },
      };

  group('classification', () {
    test('513 is the permission case that made it "always skip"', () {
      final f = RemovalFailure.fromNative(native(
        code: 513,
        message: '“com.example.plist” couldn’t be moved to the trash because '
            'you don’t have permission to access it.',
      ));
      expect(f.reason, RemovalReason.permission);
      expect(f.needsAdmin, isTrue);
      // The OS's own words survive to the UI rather than being paraphrased.
      expect(f.message, contains('permission'));
    });

    test('257, the read-side permission error, is the same answer', () {
      expect(RemovalFailure.fromNative(native(code: 257)).reason,
          RemovalReason.permission);
    });

    test('a POSIX EACCES underneath an unmapped code still reads as permission',
        () {
      final f = RemovalFailure.fromNative(
          native(code: 512, underCode: 13)); // EACCES
      expect(f.reason, RemovalReason.permission);
      expect(f.needsAdmin, isTrue);
    });

    test('EPERM too', () {
      expect(RemovalFailure.fromNative(native(code: 512, underCode: 1)).reason,
          RemovalReason.permission);
    });

    test('a missing file is not a permission problem', () {
      final f = RemovalFailure.fromNative(native(code: 4));
      expect(f.reason, RemovalReason.notFound);
      expect(f.needsAdmin, isFalse);
    });

    test('a read-only volume is in-use, not permission', () {
      expect(RemovalFailure.fromNative(native(code: 640)).reason,
          RemovalReason.inUse);
      expect(RemovalFailure.fromNative(native(code: 512, underCode: 30)).reason,
          RemovalReason.inUse); // EROFS
      expect(RemovalFailure.fromNative(native(code: 512, underCode: 16)).reason,
          RemovalReason.inUse); // EBUSY
    });

    test('an unrecognised error keeps its message instead of inventing one',
        () {
      final f = RemovalFailure.fromNative(
          native(code: 99999, domain: 'SomeOtherDomain', message: 'odd thing'));
      expect(f.reason, RemovalReason.unknown);
      expect(f.message, 'odd thing');
    });

    test('an empty message becomes an honest placeholder, never a guess', () {
      final f = RemovalFailure.fromNative(native(code: 99999, message: '  '));
      expect(f.message, contains('without giving a reason'));
      expect(f.message, isNot(contains('Full Disk Access')));
    });

    test('name is the basename, for a dialog that has to fit', () {
      final f = RemovalFailure.fromNative(
          native(code: 513, path: '/Library/LaunchAgents/com.example.plist'));
      expect(f.name, 'com.example.plist');
    });
  });

  group('summary line', () {
    RemovalFailure perm(String p) => RemovalFailure(
        path: p, reason: RemovalReason.permission, message: 'no permission');
    RemovalFailure odd(String p) => RemovalFailure(
        path: p, reason: RemovalReason.unknown, message: 'something else');

    test('nothing failed, nothing to say', () {
      expect(summariseFailures(const []), '');
    });

    test('one admin refusal names the remedy, not the count', () {
      final s = summariseFailures([perm('/Library/LaunchAgents/a.plist')]);
      expect(s, '1 item needs an administrator to remove');
      // The old message. If this ever comes back, the bug is back.
      expect(s, isNot(contains('skipped')));
    });

    test('all admin refusals stay on the remedy', () {
      expect(summariseFailures([perm('/a'), perm('/b'), perm('/c')]),
          '3 items need an administrator to remove');
    });

    test('a mix says how many of them an admin would fix', () {
      expect(summariseFailures([perm('/a'), odd('/b')]),
          '2 items skipped · 1 need an administrator');
    });

    test('no admin cases at all fall back to the system message', () {
      expect(summariseFailures([odd('/a')]), contains('something else'));
    });
  });

  group('the guard reports itself', () {
    test('a refused path says who refused it and why', () {
      final f = RemovalFailure.guarded('/Users');
      expect(f.reason, RemovalReason.guarded);
      expect(f.needsAdmin, isFalse);
      expect(f.message, contains('safety guard'));
    });

    test('DeletionService turns guarded paths into explained failures', () async {
      // Container roots the guard must always refuse — and must now explain.
      final res = await DeletionService().moveToTrash(['/', '/Users', MacPaths.home]);
      expect(res.removed, isEmpty);
      expect(res.failed.length, 3);
      expect(res.failed.every((f) => f.reason == RemovalReason.guarded), isTrue);
      expect(res.allNeedAdmin, isFalse,
          reason: 'an admin password would not make deleting / a good idea');
    });

    test('deletePermanently outside the Trash is refused, with a reason',
        () async {
      final res = await DeletionService()
          .deletePermanently(['${MacPaths.home}/Documents/whatever']);
      expect(res.removed, isEmpty);
      expect(res.failed.single.reason, RemovalReason.guarded);
    });
  });
}
