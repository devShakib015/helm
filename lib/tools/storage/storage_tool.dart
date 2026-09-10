import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_controller.dart';
import '../../core/services/permissions_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import 'state/storage_controller.dart';
import 'ui/views/categories_view.dart';
import 'ui/views/cleaner_view.dart';
import 'ui/views/duplicates_view.dart';
import 'ui/views/large_files_view.dart';
import 'ui/views/overview_view.dart';
import 'ui/widgets/page_chrome.dart';

/// Hosts the Storage tool: the Full Disk Access banner plus the active section.
class StorageTool extends StatefulWidget {
  const StorageTool({super.key});

  @override
  State<StorageTool> createState() => _StorageToolState();
}

class _StorageToolState extends State<StorageTool> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StorageController>().init();
    });
  }

  Widget _sectionFor(StorageSection section) {
    switch (section) {
      case StorageSection.overview:
        return const OverviewView(key: ValueKey('overview'));
      case StorageSection.categories:
        return const CategoriesView(key: ValueKey('categories'));
      case StorageSection.cleaner:
        return const CleanerView(key: ValueKey('cleaner'));
      case StorageSection.largeFiles:
        return const LargeFilesView(key: ValueKey('large'));
      case StorageSection.duplicates:
        return const DuplicatesView(key: ValueKey('duplicates'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final section = context.watch<AppController>().storageSection;
    final storage = context.watch<StorageController>();
    final showFda = storage.fda != FdaStatus.granted && !storage.fdaDismissed;

    return Column(
      children: [
        if (showFda)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Insets.xxl, Insets.lg, Insets.xxl, 0),
            child: storage.canHoldGrant
                ? NoticeBanner(
                    icon: Icons.lock_outline_rounded,
                    title: 'Grant Full Disk Access for complete results',
                    message:
                        'Turn Helm on in System Settings, then relaunch — macOS '
                        'applies the permission when the app starts.',
                    accent: AppColors.warning,
                    primaryLabel: 'Open Settings',
                    onPrimary: storage.openFdaSettings,
                    secondaryLabel: 'Relaunch Helm',
                    onSecondary: storage.relaunchApp,
                    onDismiss: storage.dismissFdaBanner,
                  )
                // The banner used to end with "Already granted but still seeing
                // this? Relaunch Helm." — which sent anyone in this state round
                // the same loop forever, because relaunching cannot fix it.
                // macOS reads an app's identity from its signature before
                // matching a Full Disk Access grant to it, so a copy of Helm
                // whose signature does not validate can be switched ON and
                // still be refused everything.
                : NoticeBanner(
                    icon: Icons.gpp_maybe_outlined,
                    title: 'Full Disk Access cannot apply to this copy of Helm',
                    message:
                        'Helm’s own signature does not validate, so macOS has '
                        'no identity to attach the permission to — the switch '
                        'can read ON in System Settings and every protected '
                        'folder will still be refused. Relaunching will not '
                        'change it. Reinstall from a fresh download, then grant '
                        'access again.',
                    accent: AppColors.danger,
                    primaryLabel: 'Open Settings',
                    onPrimary: storage.openFdaSettings,
                    onDismiss: storage.dismissFdaBanner,
                  ),
          ),
        Expanded(
          child: AnimatedSwitcher(
            duration: Motion.medium,
            switchInCurve: Motion.curve,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.012),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: _sectionFor(section),
          ),
        ),
      ],
    );
  }
}
