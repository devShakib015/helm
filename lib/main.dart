import 'package:flutter/widgets.dart';
import 'package:macos_window_utils/macos_window_utils.dart';
import 'package:provider/provider.dart';

import 'app/app_controller.dart';
import 'app/helm_app.dart';
import 'tools/battery/state/battery_controller.dart';
import 'tools/memory/state/memory_controller.dart';
import 'tools/network/state/network_controller.dart';
import 'tools/privacy/state/privacy_controller.dart';
import 'tools/startup/state/startup_controller.dart';
import 'tools/storage/state/cleaner_controller.dart';
import 'tools/storage/state/duplicates_controller.dart';
import 'tools/storage/state/large_files_controller.dart';
import 'tools/storage/state/storage_controller.dart';
import 'tools/uninstaller/state/uninstaller_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _configureWindow();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppController()),
        ChangeNotifierProvider(create: (_) => StorageController()),
        ChangeNotifierProvider(
          create: (ctx) => CleanerController(ctx.read<StorageController>()),
        ),
        ChangeNotifierProvider(
          create: (ctx) => LargeFilesController(ctx.read<StorageController>()),
        ),
        ChangeNotifierProvider(
          create: (ctx) => DuplicatesController(ctx.read<StorageController>()),
        ),
        // Other tools — lazily created (and their timers started) only when the
        // user first opens them.
        ChangeNotifierProvider(create: (_) => MemoryController()),
        ChangeNotifierProvider(create: (_) => BatteryController()),
        ChangeNotifierProvider(create: (_) => NetworkController()),
        ChangeNotifierProvider(create: (_) => UninstallerController()),
        ChangeNotifierProvider(create: (_) => StartupController()),
        ChangeNotifierProvider(create: (_) => PrivacyController()),
      ],
      child: const HelmApp(),
    ),
  );
}

/// Frameless dark-glass window: transparent full-size title bar with the
/// traffic lights overlaid on the content, plus subtle macOS vibrancy behind
/// the translucent UI. Wrapped defensively so a window-styling hiccup never
/// stops the app from launching.
Future<void> _configureWindow() async {
  try {
    await WindowManipulator.initialize(enableWindowDelegate: true);
    await WindowManipulator.setMaterial(
        NSVisualEffectViewMaterial.underWindowBackground);
    WindowManipulator.makeTitlebarTransparent();
    WindowManipulator.enableFullSizeContentView();
    WindowManipulator.hideTitle();
  } catch (_) {
    // Fall back to a standard window.
  }
}
