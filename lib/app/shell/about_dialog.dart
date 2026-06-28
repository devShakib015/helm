import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/glass_panel.dart';
import '../app_info.dart';

Future<void> showAboutHelm(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (context) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: GlassPanel(
          blur: true,
          color: const Color(0xF21A2030),
          border: AppColors.strokeStrong,
          padding: const EdgeInsets.all(Insets.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.4),
                        blurRadius: 24,
                        spreadRadius: -4),
                  ],
                ),
                child: Image.asset('assets/helm_logo.png', fit: BoxFit.cover),
              ),
              const SizedBox(height: Insets.lg),
              Text(AppInfo.name, style: AppType.title),
              const SizedBox(height: 2),
              Text('Version ${AppInfo.version}', style: AppType.caption),
              const SizedBox(height: Insets.md),
              Text(
                AppInfo.tagline,
                textAlign: TextAlign.center,
                style: AppType.secondary,
              ),
              const SizedBox(height: Insets.lg),
              const Divider(color: AppColors.stroke),
              const SizedBox(height: Insets.md),
              Text(
                '${AppInfo.copyright}\nReleased free under the MIT License.',
                textAlign: TextAlign.center,
                style: AppType.caption.copyWith(color: AppColors.textTertiary),
              ),
              const SizedBox(height: Insets.xl),
              HelmButton(
                label: 'Close',
                kind: HelmButtonKind.ghost,
                expand: true,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
