import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/permissions_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/byte_format.dart';
import '../../core/widgets/hoverable.dart';
import '../../tools/storage/state/storage_controller.dart';
import '../app_controller.dart';
import '../app_info.dart';
import '../tool_registry.dart';
import 'about_dialog.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

  static const double width = 234;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    return Container(
      width: width,
      decoration: const BoxDecoration(
        color: AppColors.sidebarTint,
        border: Border(right: BorderSide(color: AppColors.stroke)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 50), // clear the traffic lights
          const _Brand(),
          const SizedBox(height: Insets.xl),
          const _Label('TOOLS'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: Insets.md),
              children: [
                for (final tool in kTools) ...[
                  _ToolItem(
                    meta: tool,
                    active: app.current == tool.id,
                    onTap: () => app.select(tool.id),
                  ),
                  if (tool.id == ToolId.storage && app.current == ToolId.storage)
                    ...StorageSection.values.map(
                      (s) => _SectionItem(
                        section: s,
                        active: app.storageSection == s,
                        onTap: () => app.selectStorageSection(s),
                      ),
                    ),
                ],
              ],
            ),
          ),
          const _Footer(),
        ],
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.45),
                    blurRadius: 16,
                    spreadRadius: -3),
              ],
            ),
            child: Image.asset('assets/helm_logo.png', fit: BoxFit.cover),
          ),
          const SizedBox(width: Insets.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppInfo.name,
                  style: AppType.headline.copyWith(letterSpacing: -0.2)),
              Text('for macOS',
                  style: AppType.micro.copyWith(letterSpacing: 0.4)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.xl, 0, Insets.xl, Insets.sm),
      child: Text(text, style: AppType.micro),
    );
  }
}

class _ToolItem extends StatelessWidget {
  const _ToolItem({
    required this.meta,
    required this.active,
    required this.onTap,
  });

  final ToolMeta meta;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Hoverable(
        enabled: meta.available,
        onTap: onTap,
        builder: (context, hovered, _) => AnimatedContainer(
          duration: Motion.fast,
          padding: const EdgeInsets.symmetric(
              horizontal: Insets.sm, vertical: Insets.sm),
          decoration: BoxDecoration(
            color: active
                ? AppColors.glassStrong
                : (hovered ? AppColors.glass : Colors.transparent),
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: active ? AppColors.stroke : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: meta.accent.withValues(alpha: active ? 0.22 : 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(meta.icon,
                    size: 17,
                    color: meta.available
                        ? meta.accent
                        : AppColors.textTertiary),
              ),
              const SizedBox(width: Insets.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(meta.name,
                        style: AppType.bodyStrong.copyWith(
                          color: meta.available
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        )),
                    Text(meta.tagline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.micro.copyWith(letterSpacing: 0)),
                  ],
                ),
              ),
              if (!meta.available) const _SoonBadge(),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionItem extends StatelessWidget {
  const _SectionItem({
    required this.section,
    required this.active,
    required this.onTap,
  });

  final StorageSection section;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 22, bottom: 2),
      child: Hoverable(
        onTap: onTap,
        builder: (context, hovered, _) => AnimatedContainer(
          duration: Motion.fast,
          padding: const EdgeInsets.symmetric(
              horizontal: Insets.md, vertical: 7),
          decoration: BoxDecoration(
            color: active
                ? AppColors.accentSoft
                : (hovered ? AppColors.glass : Colors.transparent),
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: Row(
            children: [
              Icon(section.icon,
                  size: 15,
                  color: active ? AppColors.accent : AppColors.textTertiary),
              const SizedBox(width: Insets.md),
              Text(section.label,
                  style: AppType.body.copyWith(
                    color:
                        active ? AppColors.textPrimary : AppColors.textSecondary,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _SoonBadge extends StatelessWidget {
  const _SoonBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.glassStrong,
        borderRadius: Radii.pill,
        border: Border.all(color: AppColors.stroke),
      ),
      child: Text('Soon',
          style: AppType.micro.copyWith(
              color: AppColors.textTertiary, letterSpacing: 0.3)),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageController>();
    final granted = storage.fda == FdaStatus.granted;
    final v = storage.volume;
    return Container(
      padding: const EdgeInsets.all(Insets.lg),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.stroke)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (v.totalBytes > 0) ...[
            Text(
              '${formatBytes(v.freeBytes)} free of ${formatBytes(v.totalBytes)}',
              style: AppType.caption,
            ),
            const SizedBox(height: Insets.sm),
          ],
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: granted ? AppColors.success : AppColors.warning,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  granted ? 'Full Disk Access on' : 'Limited disk access',
                  style: AppType.caption,
                ),
              ),
              Hoverable(
                onTap: () => showAboutHelm(context),
                builder: (context, hovered, _) => Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color:
                      hovered ? AppColors.textPrimary : AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
