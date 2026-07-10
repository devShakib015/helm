import 'package:flutter/widgets.dart';
import 'package:macos_window_utils/macos_window_utils.dart';
import 'package:provider/provider.dart';

import 'app/alert_controller.dart';
import 'app/app_controller.dart';
import 'app/helm_app.dart';
import 'app/housekeeping_controller.dart';
import 'app/menu_bar_driver.dart';
import 'app/settings_controller.dart';
import 'app/tool_registry.dart';
import 'core/services/native_system.dart';
import 'tools/battery/state/battery_controller.dart';
import 'tools/battery/state/bt_devices_controller.dart';
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
import 'tools/system/state/processes_controller.dart';
import 'tools/system/state/stats_controller.dart';
import 'tools/system/state/stats_history.dart';
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

  final app = AppController();

  // Native → Dart callbacks for the menu-bar quick actions.
  NativeSystem.registerHandlers();
  NativeSystem.onColorPicked = colorPicker.receivePick;
  NativeSystem.onMenuAction = (action) {
    if (action == 'toggleCaffeine') keepAwake.toggle();
  };
  NativeSystem.onClipCopy = (id, fromPopup) async {
    await clipboard.copyById(id);
    // A popup pick optionally pastes straight into the frontmost app.
    if (fromPopup && settings.clipAutoPaste) {
      await NativeSystem.simulatePaste();
    }
  };
  // Notification clicks route to a specific tool (e.g. watchdog → Startup).
  NativeSystem.onOpenTool = (name) {
    for (final t in ToolId.values) {
      if (t.name == name) {
        app.select(t);
        break;
      }
    }
  };

  // Registers listeners on stats + settings + clipboard + keepAwake (which keep
  // it alive), so it drives the native menu bar for the app's lifetime.
  MenuBarDriver(stats, settings, clipboard, keepAwake);
  // Watches stats against the user's thresholds and raises notifications.
  AlertController(stats, settings);
  // Trash/Downloads size watchers + login-item watchdog.
  HousekeepingController(settings);
  // 24h telemetry ring buffer feeding the history charts.
  final history = StatsHistory(stats);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: app),
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: stats),
        ChangeNotifierProvider.value(value: history),
        ChangeNotifierProvider.value(value: clipboard),
        ChangeNotifierProvider.value(value: keepAwake),
        ChangeNotifierProvider.value(value: colorPicker),
        ChangeNotifierProvider(create: (_) => ProcessesController()),
        ChangeNotifierProvider(create: (_) => BtDevicesController()),
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
