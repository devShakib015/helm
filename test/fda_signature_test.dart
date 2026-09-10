import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helm/core/services/native_bridge.dart';
import 'package:helm/core/services/permissions_service.dart';

/// Helm told people to relaunch when Full Disk Access read as denied. For one
/// whole class of cause that is advice you can follow forever without effect:
/// if the app's own signature does not validate, macOS has no identity to
/// attach the grant to, and the switch in System Settings can read ON while
/// every protected path stays refused.
///
/// The contract that matters here is which way the check fails. Accusing a
/// perfectly good app of being broken is worse than saying nothing, so anything
/// short of a clear "invalid" answer must come back true.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('helm/native');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void answer(Future<Object?>? Function(MethodCall) handler) =>
      messenger.setMockMethodCallHandler(channel, handler);

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('a valid signature reports as able to hold the grant', () async {
    answer((call) async {
      expect(call.method, 'codeSignatureValid');
      return true;
    });
    expect(await NativeBridge.codeSignatureValid(), isTrue);
    expect(await PermissionsService().canHoldGrant(), isTrue);
  });

  test('an invalid signature is reported, not swallowed', () async {
    answer((call) async => false);
    expect(await NativeBridge.codeSignatureValid(), isFalse);
    expect(await PermissionsService().canHoldGrant(), isFalse);
  });

  test('a null answer is treated as fine, not as broken', () async {
    answer((call) async => null);
    expect(await NativeBridge.codeSignatureValid(), isTrue);
  });

  test('a platform error is treated as fine, not as broken', () async {
    answer((call) async => throw PlatformException(code: 'boom'));
    expect(await NativeBridge.codeSignatureValid(), isTrue);
  });

  test('a missing plugin is treated as fine, not as broken', () async {
    answer((call) async => throw MissingPluginException('no channel'));
    expect(await NativeBridge.codeSignatureValid(), isTrue);
  });
}
