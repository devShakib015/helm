import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/native_system.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/hoverable.dart';
import '../../core/widgets/page_header.dart';
import 'color_picker_controller.dart';

/// The Color Picker: opens the macOS screen eyedropper, copies the picked color
/// to the clipboard, shows it in every developer format, and keeps a history of
/// swatches.
class ColorPickerTool extends StatelessWidget {
  const ColorPickerTool({super.key});

  static const Color _accent = Color(0xFFEC4899);

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ColorPickerController>();
    final last = c.last;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          Insets.xxl, Insets.xl, Insets.xxl, Insets.xxl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Color Picker',
                subtitle: 'Pick any color from the screen',
                actions: [
                  _PickButton(
                    picking: c.picking,
                    accent: _accent,
                    onTap: () => _pick(context, c),
                  ),
                ],
              ),
              const SizedBox(height: Insets.xl),
              if (last == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Insets.xxl),
                  child: EmptyState(
                    icon: Icons.colorize_rounded,
                    accent: _accent,
                    title: 'No color picked yet',
                    message:
                        'Click “Pick Color” to open the magnifier, then click '
                        'anywhere on screen. The color is copied to your '
                        'clipboard automatically.',
                    action: _PickButton(
                      picking: c.picking,
                      accent: _accent,
                      onTap: () => _pick(context, c),
                    ),
                  ),
                )
              else
                _CurrentColor(hex: last.hex, accent: _accent),
              if (c.history.isNotEmpty) ...[
                const SizedBox(height: Insets.xl),
                _HistorySection(controller: c),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context, ColorPickerController c) async {
    final hex = await c.pick();
    if (hex != null && context.mounted) {
      _toast(context, 'Picked & copied $hex');
    }
  }
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message, style: AppType.body),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.glassStrong,
        duration: const Duration(milliseconds: 1400),
      ),
    );
}

/// The big swatch + every copyable representation of the current color.
class _CurrentColor extends StatelessWidget {
  const _CurrentColor({required this.hex, required this.accent});

  final String hex;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final color = colorFromHex(hex);
    final formats = colorFormats(hex);
    return GlassPanel(
      padding: const EdgeInsets.all(Insets.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(Radii.lg),
              border: Border.all(color: AppColors.strokeStrong),
              boxShadow: [
                BoxShadow(
                    color: color.withValues(alpha: 0.35),
                    blurRadius: 32,
                    spreadRadius: -8),
              ],
            ),
            alignment: Alignment.bottomLeft,
            padding: const EdgeInsets.all(Insets.md),
            child: Text(
              hex,
              style: AppType.bodyStrong.copyWith(
                color: _readableOn(color),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: Insets.xl),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < formats.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: AppColors.stroke.withValues(alpha: 0.6),
                    ),
                  _FormatRow(format: formats[i], accent: accent),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Black or white text, whichever reads better on [bg].
  Color _readableOn(Color bg) {
    // ignore: deprecated_member_use
    final luma = (0.299 * bg.red + 0.587 * bg.green + 0.114 * bg.blue) / 255;
    return luma > 0.6 ? const Color(0xFF0B0E15) : Colors.white;
  }
}

/// One label → value row with a copy affordance.
class _FormatRow extends StatelessWidget {
  const _FormatRow({required this.format, required this.accent});

  final ColorFormat format;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: () => _copy(context),
      builder: (context, hovered, _) => AnimatedContainer(
        duration: Motion.fast,
        padding: const EdgeInsets.symmetric(
            horizontal: Insets.sm, vertical: Insets.md),
        decoration: BoxDecoration(
          color: hovered ? AppColors.glass : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 96,
              child: Text(format.label.toUpperCase(), style: AppType.micro),
            ),
            Expanded(
              child: SelectableText(
                format.value,
                maxLines: 1,
                style: AppType.mono.copyWith(color: AppColors.textPrimary),
              ),
            ),
            const SizedBox(width: Insets.sm),
            Icon(
              hovered ? Icons.content_copy_rounded : Icons.copy_outlined,
              size: 15,
              color: hovered ? accent : AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copy(BuildContext context) async {
    // Write the exact representation to the clipboard. (The color itself is
    // already in the swatch history; format strings don't belong there.)
    await NativeSystem.pbWriteText(format.value);
    if (context.mounted) _toast(context, 'Copied ${format.label}');
  }
}

/// A wrapping grid of previously picked swatches.
class _HistorySection extends StatelessWidget {
  const _HistorySection({required this.controller});

  final ColorPickerController controller;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(Insets.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('RECENT', style: AppType.micro),
              const Spacer(),
              Hoverable(
                onTap: controller.clear,
                builder: (context, hovered, _) => Text(
                  'Clear',
                  style: AppType.caption.copyWith(
                    color:
                        hovered ? AppColors.danger : AppColors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.md),
          Wrap(
            spacing: Insets.sm,
            runSpacing: Insets.sm,
            children: [
              for (final c in controller.history)
                _Swatch(
                  hex: c.hex,
                  onTap: () async {
                    await controller.copy(c.hex);
                    if (context.mounted) _toast(context, 'Copied ${c.hex}');
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.hex, required this.onTap});

  final String hex;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: hex,
      waitDuration: const Duration(milliseconds: 400),
      child: Hoverable(
        onTap: onTap,
        builder: (context, hovered, _) => AnimatedContainer(
          duration: Motion.fast,
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: colorFromHex(hex),
            borderRadius: BorderRadius.circular(Radii.sm),
            border: Border.all(
              color: hovered ? AppColors.strokeStrong : AppColors.stroke,
              width: hovered ? 1.5 : 1,
            ),
          ),
        ),
      ),
    );
  }
}

/// The accent-gradient "Pick Color" button.
class _PickButton extends StatelessWidget {
  const _PickButton({
    required this.picking,
    required this.accent,
    required this.onTap,
  });

  final bool picking;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      onTap: picking ? null : onTap,
      builder: (context, hovered, _) => AnimatedContainer(
        duration: Motion.fast,
        padding: const EdgeInsets.symmetric(
            horizontal: Insets.lg, vertical: Insets.md),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: hovered ? 0.30 : 0.20),
          borderRadius: Radii.pill,
          border: Border.all(color: accent.withValues(alpha: 0.55)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(picking ? Icons.hourglass_top_rounded : Icons.colorize_rounded,
                size: 16, color: accent),
            const SizedBox(width: Insets.sm),
            Text(
              picking ? 'Picking…' : 'Pick Color',
              style: AppType.bodyStrong.copyWith(color: accent),
            ),
          ],
        ),
      ),
    );
  }
}
