import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Every tool Helm will host. Storage ships first; the rest are declared now so
/// the sidebar communicates the roadmap and the architecture stays multi-tool
/// from day one.
enum ToolId { storage, memory, uninstaller, startup, privacy, battery, network }

class ToolMeta {
  const ToolMeta({
    required this.id,
    required this.name,
    required this.tagline,
    required this.icon,
    required this.accent,
    required this.available,
  });

  final ToolId id;
  final String name;
  final String tagline;
  final IconData icon;
  final Color accent;
  final bool available;
}

const List<ToolMeta> kTools = [
  ToolMeta(
    id: ToolId.storage,
    name: 'Storage',
    tagline: 'Analyze & reclaim disk space',
    icon: Icons.donut_large_rounded,
    accent: AppColors.accent,
    available: true,
  ),
  ToolMeta(
    id: ToolId.memory,
    name: 'Memory',
    tagline: 'Free up RAM',
    icon: Icons.memory_rounded,
    accent: Color(0xFF34D399),
    available: true,
  ),
  ToolMeta(
    id: ToolId.uninstaller,
    name: 'Uninstaller',
    tagline: 'Remove apps completely',
    icon: Icons.auto_delete_rounded,
    accent: Color(0xFFFB7185),
    available: true,
  ),
  ToolMeta(
    id: ToolId.startup,
    name: 'Startup',
    tagline: 'Manage login items',
    icon: Icons.rocket_launch_rounded,
    accent: Color(0xFFFBBF24),
    available: true,
  ),
  ToolMeta(
    id: ToolId.privacy,
    name: 'Privacy',
    tagline: 'Clear traces & permissions',
    icon: Icons.shield_rounded,
    accent: Color(0xFF7B61FF),
    available: true,
  ),
  ToolMeta(
    id: ToolId.battery,
    name: 'Battery',
    tagline: 'Health & power insights',
    icon: Icons.battery_charging_full_rounded,
    accent: Color(0xFF38BDF8),
    available: true,
  ),
  ToolMeta(
    id: ToolId.network,
    name: 'Network',
    tagline: 'Monitor connections',
    icon: Icons.speed_rounded,
    accent: Color(0xFF22D3EE),
    available: true,
  ),
];

ToolMeta toolMeta(ToolId id) => kTools.firstWhere((t) => t.id == id);
