import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/native_system.dart';
import '../../tools/battery/battery_tool.dart';
import '../../tools/clipboard/clipboard_tool.dart';
import '../../tools/colorpicker/color_picker_tool.dart';
import '../../tools/dashboard/dashboard_tool.dart';
import '../../tools/keepawake/keep_awake_tool.dart';
import '../../tools/memory/memory_tool.dart';
import '../../tools/network/network_tool.dart';
import '../../tools/privacy/privacy_tool.dart';
import '../../tools/quickactions/quick_actions_tool.dart';
import '../../tools/startup/startup_tool.dart';
import '../../tools/storage/storage_tool.dart';
import '../../tools/system/ui/cpu_tool.dart';
import '../../tools/system/ui/gpu_tool.dart';
import '../../tools/system/ui/sensors_tool.dart';
import '../../tools/uninstaller/uninstaller_tool.dart';
import '../app_controller.dart';
import '../settings/settings_page.dart';
import '../tool_registry.dart';
import 'sidebar.dart';

/// The window's root: a translucent dark gradient, the tool rail on the left,
/// and the active tool filling the rest. The top strip stays draggable (the
/// native title bar is transparent and full-size).
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    // A transparent Scaffold provides the Material ancestor (for ink, popups)
    // and the SnackBar host, while the gradient + vibrancy show through.
    return const Scaffold(
      backgroundColor: Colors.transparent,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xF20E121B), Color(0xF2080A10)],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Sidebar(),
                  _SidebarResizeHandle(),
                  Expanded(child: _Content()),
                ],
              ),
            ),
            // Double-click the title-bar strip to zoom (fill the screen), the
            // way a native title bar does — offset past the traffic lights.
            _TitleBarZone(),
          ],
        ),
      ),
    );
  }
}

/// A thin draggable gutter on the sidebar's edge. Invisible but shows the
/// column-resize cursor; dragging widens or narrows the rail.
class _SidebarResizeHandle extends StatelessWidget {
  const _SidebarResizeHandle();

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppController>();
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (d) =>
            app.setSidebarWidth(app.sidebarWidth + d.delta.dx),
        child: const SizedBox(width: 8),
      ),
    );
  }
}

/// Transparent strip across the top of the window. A double-click here zooms
/// the window (the native title-bar gesture, which a full-size content view
/// otherwise swallows). It uses a passive [Listener] so window dragging still
/// works. The left inset clears the traffic-light buttons.
class _TitleBarZone extends StatefulWidget {
  const _TitleBarZone();

  @override
  State<_TitleBarZone> createState() => _TitleBarZoneState();
}

class _TitleBarZoneState extends State<_TitleBarZone> {
  int _lastDownMs = 0;
  Offset? _lastDownPos;

  void _onPointerDown(PointerDownEvent e) {
    final now = e.timeStamp.inMilliseconds;
    final recent = _lastDownMs != 0 && now - _lastDownMs < 350;
    final near = _lastDownPos != null && (e.position - _lastDownPos!).distance < 8;
    if (recent && near) {
      NativeSystem.zoomWindow();
      _lastDownMs = 0;
      _lastDownPos = null;
    } else {
      _lastDownMs = now;
      _lastDownPos = e.position;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 78, // clear the traffic-light buttons
      right: 0,
      height: 28,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onPointerDown,
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content();

  @override
  Widget build(BuildContext context) {
    final current = context.watch<AppController>().current;
    final child = switch (current) {
      ToolId.dashboard => const DashboardTool(),
      ToolId.storage => const StorageTool(),
      ToolId.memory => const MemoryTool(),
      ToolId.cpu => const CpuTool(),
      ToolId.gpu => const GpuTool(),
      ToolId.sensors => const SensorsTool(),
      ToolId.battery => const BatteryTool(),
      ToolId.network => const NetworkTool(),
      ToolId.clipboard => const ClipboardTool(),
      ToolId.colorPicker => const ColorPickerTool(),
      ToolId.keepAwake => const KeepAwakeTool(),
      ToolId.quickActions => const QuickActionsTool(),
      ToolId.uninstaller => const UninstallerTool(),
      ToolId.startup => const StartupTool(),
      ToolId.privacy => const PrivacyTool(),
      ToolId.settings => const SettingsPage(),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
      child: KeyedSubtree(key: ValueKey(current), child: child),
    );
  }
}
