import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Every tool Helm hosts. `settings` is special — rendered from the sidebar
/// footer rather than the main tool list.
enum ToolId {
  dashboard,
  storage,
  memory,
  cpu,
  gpu,
  sensors,
  battery,
  network,
  clipboard,
  colorPicker,
  keepAwake,
  quickActions,
  uninstaller,
  startup,
  privacy,
  settings,
}

/// Groupings used to organize the tool rail and the dashboard launcher.
/// Dashboard and Settings sit outside any category (pinned / footer).
enum ToolCategory { monitor, manage, utilities }

extension ToolCategoryX on ToolCategory {
  String get label => switch (this) {
        ToolCategory.monitor => 'Monitor',
        ToolCategory.manage => 'Manage',
        ToolCategory.utilities => 'Utilities',
      };

  IconData get icon => switch (this) {
        ToolCategory.monitor => Icons.insights_rounded,
        ToolCategory.manage => Icons.tune_rounded,
        ToolCategory.utilities => Icons.widgets_rounded,
      };
}

class ToolMeta {
  const ToolMeta({
    required this.id,
    required this.name,
    required this.tagline,
    required this.icon,
    required this.accent,
    required this.available,
    this.category,
  });

  final ToolId id;
  final String name;
  final String tagline;
  final IconData icon;
  final Color accent;
  final bool available;

  /// Which sidebar/dashboard group this tool belongs to. Null for Dashboard
  /// (pinned at the top) and Settings (in the footer).
  final ToolCategory? category;
}

const List<ToolMeta> kTools = [
  ToolMeta(
    id: ToolId.dashboard,
    name: 'Dashboard',
    tagline: 'Device & system overview',
    icon: Icons.dashboard_rounded,
    accent: AppColors.accent,
    available: true,
  ),
  ToolMeta(
    id: ToolId.storage,
    name: 'Storage',
    tagline: 'Analyze & reclaim disk space',
    icon: Icons.donut_large_rounded,
    accent: AppColors.accent,
    available: true,
    category: ToolCategory.manage,
  ),
  ToolMeta(
    id: ToolId.memory,
    name: 'Memory',
    tagline: 'Free up RAM',
    icon: Icons.memory_rounded,
    accent: Color(0xFFA78BFA),
    available: true,
    category: ToolCategory.monitor,
  ),
  ToolMeta(
    id: ToolId.cpu,
    name: 'CPU',
    tagline: 'Processor usage',
    icon: Icons.developer_board_rounded,
    accent: Color(0xFFFB5C5C),
    available: true,
    category: ToolCategory.monitor,
  ),
  ToolMeta(
    id: ToolId.gpu,
    name: 'GPU',
    tagline: 'Graphics activity',
    icon: Icons.auto_awesome_motion_rounded,
    accent: Color(0xFF22D3EE),
    available: true,
    category: ToolCategory.monitor,
  ),
  ToolMeta(
    id: ToolId.sensors,
    name: 'Sensors',
    tagline: 'Temperatures & fans',
    icon: Icons.thermostat_rounded,
    accent: Color(0xFFFBBF24),
    available: true,
    category: ToolCategory.monitor,
  ),
  ToolMeta(
    id: ToolId.battery,
    name: 'Battery',
    tagline: 'Health & power insights',
    icon: Icons.battery_charging_full_rounded,
    accent: Color(0xFF38BDF8),
    available: true,
    category: ToolCategory.monitor,
  ),
  ToolMeta(
    id: ToolId.network,
    name: 'Network',
    tagline: 'Live throughput & connections',
    icon: Icons.speed_rounded,
    accent: Color(0xFF5AC8FA),
    available: true,
    category: ToolCategory.monitor,
  ),
  ToolMeta(
    id: ToolId.clipboard,
    name: 'Clipboard',
    tagline: 'History & quick paste',
    icon: Icons.content_paste_rounded,
    accent: Color(0xFF34D8C8),
    available: true,
    category: ToolCategory.utilities,
  ),
  ToolMeta(
    id: ToolId.colorPicker,
    name: 'Color Picker',
    tagline: 'Pick colors from the screen',
    icon: Icons.colorize_rounded,
    accent: Color(0xFFEC4899),
    available: true,
    category: ToolCategory.utilities,
  ),
  ToolMeta(
    id: ToolId.keepAwake,
    name: 'Keep Awake',
    tagline: 'Prevent your Mac from sleeping',
    icon: Icons.local_cafe_rounded,
    accent: Color(0xFFF59E0B),
    available: true,
    category: ToolCategory.utilities,
  ),
  ToolMeta(
    id: ToolId.quickActions,
    name: 'Quick Actions',
    tagline: 'Tweaks & maintenance',
    icon: Icons.bolt_rounded,
    accent: Color(0xFF60A5FA),
    available: true,
    category: ToolCategory.utilities,
  ),
  ToolMeta(
    id: ToolId.uninstaller,
    name: 'Uninstaller',
    tagline: 'Remove apps completely',
    icon: Icons.auto_delete_rounded,
    accent: Color(0xFFFB7185),
    available: true,
    category: ToolCategory.manage,
  ),
  ToolMeta(
    id: ToolId.startup,
    name: 'Startup',
    tagline: 'Manage login items',
    icon: Icons.rocket_launch_rounded,
    accent: Color(0xFFFBBF24),
    available: true,
    category: ToolCategory.manage,
  ),
  ToolMeta(
    id: ToolId.privacy,
    name: 'Privacy',
    tagline: 'Clear traces & permissions',
    icon: Icons.shield_rounded,
    accent: Color(0xFF7B61FF),
    available: true,
    category: ToolCategory.manage,
  ),
  ToolMeta(
    id: ToolId.settings,
    name: 'Settings',
    tagline: 'Customize Helm',
    icon: Icons.settings_rounded,
    accent: Color(0xFF94A3B8),
    available: true,
  ),
];

/// Tools shown in the main sidebar list (everything except Settings).
List<ToolMeta> get kSidebarTools =>
    kTools.where((t) => t.id != ToolId.settings).toList();

/// The single tool pinned above the categories (Dashboard).
ToolMeta get kPinnedTool => toolMeta(ToolId.dashboard);

/// Tools belonging to [category], in registry order.
List<ToolMeta> toolsInCategory(ToolCategory category) =>
    kTools.where((t) => t.category == category).toList();

ToolMeta toolMeta(ToolId id) => kTools.firstWhere((t) => t.id == id);
