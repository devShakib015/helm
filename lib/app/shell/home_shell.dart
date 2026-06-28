import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../tools/battery/battery_tool.dart';
import '../../tools/memory/memory_tool.dart';
import '../../tools/network/network_tool.dart';
import '../../tools/privacy/privacy_tool.dart';
import '../../tools/startup/startup_tool.dart';
import '../../tools/storage/storage_tool.dart';
import '../../tools/uninstaller/uninstaller_tool.dart';
import '../app_controller.dart';
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Sidebar(),
            Expanded(child: _Content()),
          ],
        ),
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
      ToolId.storage => const StorageTool(),
      ToolId.memory => const MemoryTool(),
      ToolId.uninstaller => const UninstallerTool(),
      ToolId.startup => const StartupTool(),
      ToolId.privacy => const PrivacyTool(),
      ToolId.battery => const BatteryTool(),
      ToolId.network => const NetworkTool(),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
      child: KeyedSubtree(key: ValueKey(current), child: child),
    );
  }
}
