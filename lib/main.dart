import 'package:flutter/widgets.dart';
import 'package:macos_window_utils/macos_window_utils.dart';
import 'package:provider/provider.dart';

import 'app/alert_controller.dart';
import 'app/app_controller.dart';
import 'app/helm_app.dart';
import 'app/menu_bar_driver.dart';
import 'app/settings_controller.dart';
import 'core/services/native_system.dart';
import 'tools/battery/state/battery_controller.dart';
import 'tools/clipboard/clipboard_controller.dart';
import 'tools/colorpicker/color_picker_controller.dart';
import 'tools/keepawake/keep_awake_controller.dart';
import 'tools/memory/state/memory_controller.dart';
import 'tools/network/state/network_controller.dart';
import 'tools/privacy/state/privacy_controller.dart';
import 'tools/quickactions/quick_actions_controller.dart';
import 'tools/startup/state/startup_controller.dart';
import 'tools/storage/state/cleaner_controller.dart';
import 'tools/storage/state/duplicates_controller.dart';
import 'tools/storage/state/large_files_controller.dart';
import 'tools/storage/state/storage_controller.dart';
import 'tools/system/state/stats_controller.dart';
import 'tools/uninstaller/state/uninstaller_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _configureWindow();

  // Bootstrap the always-on services before the first frame so the menu bar
  // and clipboard come alive immediately.
  final settings = SettingsController();
  await settings.load();
  final stats = StatsController()..start(intervalSec: settings.refreshSeconds);
  final clipboard = ClipboardController(settings);
  final keepAwake = KeepAwakeController();
  final colorPicker = ColorPickerController();

  // Native → Dart callbacks for the menu-bar quick actions.
  NativeSystem.registerHandlers();
  NativeSystem.onColorPicked = colorPicker.receivePick;
  NativeSystem.onMenuAction = (action) {
    if (action == 'toggleCaffeine') keepAwake.toggle();
  };

  // Registers listeners on stats + settings + clipboard + keepAwake (which keep
  // it alive), so it drives the native menu bar for the app's lifetime.
  MenuBarDriver(stats, settings, clipboard, keepAwake);
  // Watches stats against the user's thresholds and raises notifications.
  AlertController(stats, settings);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppController()),
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: stats),
        ChangeNotifierProvider.value(value: clipboard),
        ChangeNotifierProvider.value(value: keepAwake),
        ChangeNotifierProvider.value(value: colorPicker),
        ChangeNotifierProvider(create: (_) => QuickActionsController()),
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
