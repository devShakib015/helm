import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/native_system.dart';
import '../../core/services/shell.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/hoverable.dart';
import '../../core/widgets/page_header.dart';
import '../alert_metric.dart';
import '../app_info.dart';
import '../menu_metric.dart';
import '../settings_controller.dart';

/// The app's preferences screen. Everything here writes straight through to the
/// shared [SettingsController], so the menu bar and clipboard react live as the
/// user flips switches and chips.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          Insets.xxl, Insets.xl, Insets.xxl, Insets.xxl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PageHeader(
                title: 'Settings',
                subtitle: 'Customize Helm',
              ),
              const SizedBox(height: Insets.xl),

              // ---- Menu bar ----
              _SettingsSection(
                title: 'Menu Bar',
                children: [
                  _SettingRow(
                    title: 'Show in menu bar',
                    description: 'Live system metrics in the macOS menu bar',
                    trailing: _Toggle(
                      value: s.menuBarEnabled,
                      onChanged: s.setMenuBarEnabled,
                    ),
                  ),
                  _SettingRow(
                    title: 'Metrics',
                    description: 'Pick which readings to display',
                    trailing: _MetricChips(s: s),
                    stackTrailing: true,
                  ),
                  _SettingRow(
                    title: 'Colored values',
                    description: 'Tint each metric with its own color',
                    trailing: _Toggle(
                      value: s.menuColored,
                      onChanged: s.setMenuColored,
                    ),
                  ),
                  _SettingRow(
                    title: 'Update interval',
                    description: 'How often metrics refresh',
                    trailing: _Segmented<int>(
                      value: s.refreshSeconds,
                      options: const [
                        (value: 1, label: '1s'),
                        (value: 2, label: '2s'),
                        (value: 3, label: '3s'),
                        (value: 5, label: '5s'),
                      ],
                      onChanged: s.setRefreshSeconds,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Insets.lg),

              // ---- Clipboard ----
              _SettingsSection(
                title: 'Clipboard',
                children: [
                  _SettingRow(
                    title: 'Clipboard history',
                    description: 'Keep a searchable record of what you copy',
                    trailing: _Toggle(
                      value: s.clipboardEnabled,
                      onChanged: s.setClipboardEnabled,
                    ),
                  ),
                  _SettingRow(
                    title: 'History size',
                    description: 'Maximum number of items to remember',
                    trailing: _Segmented<int>(
                      value: s.clipboardHistorySize,
                      options: const [
                        (value: 50, label: '50'),
                        (value: 100, label: '100'),
                        (value: 200, label: '200'),
                        (value: 500, label: '500'),
                      ],
                      onChanged: s.setClipboardHistorySize,
                    ),
                  ),
                  _SettingRow(
                    title: 'Ignore passwords',
                    description: 'Skip items copied from password managers',
                    trailing: _Toggle(
                      value: s.clipboardIgnoreConcealed,
                      onChanged: s.setClipboardIgnoreConcealed,
                    ),
                  ),
                  _SettingRow(
                    title: 'Notify on copy',
                    description: 'Show a notification of what you just copied',
                    trailing: _Toggle(
                      value: s.clipboardNotify,
                      onChanged: s.setClipboardNotify,
                    ),
                  ),
                  _SettingRow(
                    title: 'Clear on quit',
                    description: 'Forget clipboard history when Helm closes',
                    trailing: _Toggle(
                      value: s.clipboardClearOnQuit,
                      onChanged: s.setClipboardClearOnQuit,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Insets.lg),

              // ---- Quick paste popup ----
              _SettingsSection(
                title: 'Quick Paste',
                children: [
                  _SettingRow(
                    title: 'Popup hotkey',
                    description:
                        'Press the hotkey anywhere to pick a recent clip at the cursor',
                    trailing: _Toggle(
                      value: s.clipPopupEnabled,
                      onChanged: s.setClipPopupEnabled,
                    ),
                  ),
                  _SettingRow(
                    title: 'Hotkey',
                    description: 'The global shortcut that opens the popup',
                    trailing: _Segmented<ClipHotkey>(
                      value: s.clipPopupHotkey,
                      options: [
                        for (final h in ClipHotkey.values)
                          (value: h, label: h.label),
                      ],
                      onChanged: s.setClipPopupHotkey,
                    ),
                  ),
                  _SettingRow(
                    title: 'Paste automatically',
                    description:
                        'Press ⌘V for you after picking — needs the Accessibility permission',
                    trailing: _Toggle(
                      value: s.clipAutoPaste,
                      onChanged: (v) async {
                        s.setClipAutoPaste(v);
                        if (v && !await NativeSystem.axTrusted()) {
                          Shell.run('open', [
                            'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility',
                          ]);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Insets.lg),

              // ---- Housekeeping ----
              _SettingsSection(
                title: 'Housekeeping',
                children: [
                  _SettingRow(
                    title: 'Trash size alert',
                    description: s.hkTrashEnabled
                        ? 'Notify when the Trash passes ${s.hkTrashGB} GB (checked every 15 min)'
                        : 'Off',
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ThresholdStepper(
                          value: s.hkTrashGB,
                          unit: ' GB',
                          color: const Color(0xFFF87171),
                          enabled: s.hkTrashEnabled,
                          onMinus: () => s.setHkTrashGB(s.hkTrashGB - 1),
                          onPlus: () => s.setHkTrashGB(s.hkTrashGB + 1),
                        ),
                        const SizedBox(width: Insets.md),
                        _Toggle(
                          value: s.hkTrashEnabled,
                          onChanged: s.setHkTrashEnabled,
                        ),
                      ],
                    ),
                  ),
                  _SettingRow(
                    title: 'Downloads size alert',
                    description: s.hkDownloadsEnabled
                        ? 'Notify when Downloads passes ${s.hkDownloadsGB} GB'
                        : 'Off',
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ThresholdStepper(
                          value: s.hkDownloadsGB,
                          unit: ' GB',
                          color: const Color(0xFF38BDF8),
                          enabled: s.hkDownloadsEnabled,
                          onMinus: () =>
                              s.setHkDownloadsGB(s.hkDownloadsGB - 1),
                          onPlus: () =>
                              s.setHkDownloadsGB(s.hkDownloadsGB + 1),
                        ),
                        const SizedBox(width: Insets.md),
                        _Toggle(
                          value: s.hkDownloadsEnabled,
                          onChanged: s.setHkDownloadsEnabled,
                        ),
                      ],
                    ),
                  ),
                  _SettingRow(
                    title: 'Login-item watchdog',
                    description:
                        'Notify the moment any app installs a new login item or launch agent',
                    trailing: _Toggle(
                      value: s.watchLoginItems,
                      onChanged: s.setWatchLoginItems,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Insets.lg),

              // ---- Alerts ----
              _SettingsSection(
                title: 'Alerts',
                children: [
                  for (final m in AlertMetric.values)
                    _AlertRow(metric: m, s: s),
                ],
              ),
              const SizedBox(height: Insets.lg),

              // ---- General ----
              _SettingsSection(
                title: 'General',
                children: [
                  _SettingRow(
                    title: 'Launch at login',
                    description: 'Open Helm automatically when you sign in',
                    trailing: _Toggle(
                      value: s.launchAtLogin,
                      onChanged: (v) => s.setLaunchAtLogin(v),
                    ),
                  ),
                  _SettingRow(
                    title: 'Keep running in menu bar',
                    description: 'Stay active after closing the window',
                    trailing: _Toggle(
                      value: s.residentInMenuBar,
                      onChanged: s.setResidentInMenuBar,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Insets.lg),

              // ---- About ----
              const _AboutPanel(),
            ],
          ),
        ),
      ),
    );
  }
}

/// A titled GlassPanel card grouping a set of [_SettingRow]s, divided by hair
/// lines.
class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.symmetric(
          horizontal: Insets.lg, vertical: Insets.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                0, Insets.md, 0, Insets.sm),
            child: Text(title.toUpperCase(), style: AppType.micro),
          ),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: AppColors.stroke.withValues(alpha: 0.6),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// One preference line: a title + description on the left, a control on the
/// right. When [stackTrailing] is set the control drops to its own line below
/// the labels (useful for the wrapping metric chips).
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.title,
    this.description,
    required this.trailing,
    this.stackTrailing = false,
  });

  final String title;
  final String? description;
  final Widget trailing;
  final bool stackTrailing;

  @override
  Widget build(BuildContext context) {
    final labels = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: AppType.body),
        if (description != null) ...[
          const SizedBox(height: 2),
          Text(
            description!,
            style: AppType.caption.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ],
    );

    if (stackTrailing) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Insets.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            labels,
            const SizedBox(height: Insets.md),
            trailing,
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Insets.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: labels),
          const SizedBox(width: Insets.lg),
          trailing,
        ],
      ),
    );
  }
}

/// A themed Material switch wrapper so every toggle in Settings looks the same.
class _Toggle extends StatelessWidget {
  const _Toggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Switch(
      value: value,
      onChanged: onChanged,
      // ignore: deprecated_member_use
      activeColor: AppColors.accent,
      activeTrackColor: AppColors.accent.withValues(alpha: 0.45),
      inactiveThumbColor: AppColors.textSecondary,
      inactiveTrackColor: AppColors.glassStrong,
      trackOutlineColor:
          WidgetStateProperty.all(AppColors.stroke.withValues(alpha: 0.6)),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

/// The wrapping set of selectable metric chips for the menu bar.
class _MetricChips extends StatelessWidget {
  const _MetricChips({required this.s});

  final SettingsController s;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Insets.sm,
      runSpacing: Insets.sm,
      children: [
        for (final m in MenuMetric.values)
          _MetricChip(
            info: metricInfo(m),
            selected: s.hasMetric(m),
            onTap: () => s.toggleMetric(m),
          ),
      ],
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.info,
    required this.selected,
    required this.onTap,
  });

  final MetricInfo info;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (context, hovered, pressed) {
        final color = info.color;
        final bg = selected
            ? color.withValues(alpha: 0.18)
            : (hovered ? AppColors.glassHover : AppColors.glass);
        final border = selected
            ? color.withValues(alpha: 0.55)
            : (hovered ? AppColors.strokeStrong : AppColors.stroke);
        final fg = selected ? color : AppColors.textSecondary;
        return AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.curve,
          padding: const EdgeInsets.symmetric(
              horizontal: Insets.md, vertical: Insets.sm),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: Radii.pill,
            border: Border.all(color: border, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(info.icon, size: 14, color: fg),
              const SizedBox(width: 6),
              Text(
                info.short,
                style: AppType.caption.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A compact pill-segmented selector for a fixed set of values.
class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final List<({T value, String label})> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.glass,
        borderRadius: Radii.pill,
        border: Border.all(color: AppColors.stroke, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final o in options)
            _SegmentPill(
              label: o.label,
              selected: o.value == value,
              onTap: () => onChanged(o.value),
            ),
        ],
      ),
    );
  }
}

class _SegmentPill extends StatelessWidget {
  const _SegmentPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: onTap,
      builder: (context, hovered, pressed) {
        final bg = selected
            ? AppColors.accent.withValues(alpha: 0.22)
            : (hovered ? AppColors.glassHover : Colors.transparent);
        final fg = selected ? AppColors.accent : AppColors.textSecondary;
        return AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.curve,
          padding: const EdgeInsets.symmetric(
              horizontal: Insets.md, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: Radii.pill,
            border: Border.all(
              color: selected
                  ? AppColors.accent.withValues(alpha: 0.45)
                  : Colors.transparent,
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: AppType.caption.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        );
      },
    );
  }
}

/// One alert metric: a toggle plus a threshold stepper. The description updates
/// live to read like a sentence ("Alert when above 90%").
class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.metric, required this.s});

  final AlertMetric metric;
  final SettingsController s;

  @override
  Widget build(BuildContext context) {
    final info = alertInfo(metric);
    final rule = s.alertRule(metric);
    final direction = info.below ? 'below' : 'above';
    return _SettingRow(
      title: info.label,
      description: rule.enabled
          ? 'Alert when $direction ${rule.threshold}${info.unit}'
          : 'Off',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ThresholdStepper(
            value: rule.threshold,
            unit: info.unit,
            color: info.color,
            enabled: rule.enabled,
            onMinus: () =>
                s.setAlertThreshold(metric, rule.threshold - info.step),
            onPlus: () =>
                s.setAlertThreshold(metric, rule.threshold + info.step),
          ),
          const SizedBox(width: Insets.md),
          _Toggle(
            value: rule.enabled,
            onChanged: (v) => s.setAlertEnabled(metric, v),
          ),
        ],
      ),
    );
  }
}

/// A compact "− value −" stepper for an alert threshold.
class _ThresholdStepper extends StatelessWidget {
  const _ThresholdStepper({
    required this.value,
    required this.unit,
    required this.color,
    required this.enabled,
    required this.onMinus,
    required this.onPlus,
  });

  final int value;
  final String unit;
  final Color color;
  final bool enabled;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    final fg = enabled ? color : AppColors.textTertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.glass,
        borderRadius: Radii.pill,
        border: Border.all(color: AppColors.stroke),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepButton(icon: Icons.remove_rounded, onTap: enabled ? onMinus : null),
          SizedBox(
            width: 46,
            child: Text(
              '$value$unit',
              textAlign: TextAlign.center,
              style: AppType.caption.copyWith(
                color: fg,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          _StepButton(icon: Icons.add_rounded, onTap: enabled ? onPlus : null),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    return Hoverable(
      enabled: on,
      onTap: onTap,
      builder: (context, hovered, _) => Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: hovered ? AppColors.glassHover : Colors.transparent,
        ),
        child: Icon(icon,
            size: 16,
            color: on ? AppColors.textSecondary : AppColors.textTertiary),
      ),
    );
  }
}

/// The footer card: logo, name, version and a one-line credit.
class _AboutPanel extends StatelessWidget {
  const _AboutPanel();

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(Insets.lg),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.md),
            child: Image.asset(
              'assets/helm_logo.png',
              width: 48,
              height: 48,
            ),
          ),
          const SizedBox(width: Insets.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Helm', style: AppType.headline),
                const SizedBox(height: 2),
                Text('Version ${AppInfo.version}', style: AppType.caption),
                const SizedBox(height: 4),
                Text(
                  'A premium macOS toolkit · MIT License · by Shakib',
                  style: AppType.caption.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
