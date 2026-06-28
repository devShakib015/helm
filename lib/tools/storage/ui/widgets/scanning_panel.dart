import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/byte_format.dart';
import '../../../../core/widgets/buttons.dart';
import '../../state/scan_state.dart';

/// Full-pane live scan state: a pulsing radar, running byte/file totals, the
/// path currently being read, and a cancel button.
class ScanningPanel extends StatefulWidget {
  const ScanningPanel({
    super.key,
    required this.progress,
    required this.title,
    required this.onCancel,
    this.accent = AppColors.accent,
  });

  final ScanProgress progress;
  final String title;
  final VoidCallback onCancel;
  final Color accent;

  @override
  State<ScanningPanel> createState() => _ScanningPanelState();
}

class _ScanningPanelState extends State<ScanningPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.progress;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) => CustomPaint(
              size: const Size(120, 120),
              painter: _RadarPainter(_c.value, widget.accent),
              child: SizedBox(
                width: 120,
                height: 120,
                child: Center(
                  child: Icon(Icons.radar_rounded,
                      size: 34, color: widget.accent),
                ),
              ),
            ),
          ),
          const SizedBox(height: Insets.xl),
          Text(widget.title, style: AppType.title),
          const SizedBox(height: Insets.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _stat(formatBytes(p.bytes), 'scanned'),
              Container(
                width: 1,
                height: 28,
                margin: const EdgeInsets.symmetric(horizontal: Insets.lg),
                color: AppColors.stroke,
              ),
              _stat(formatCount(p.files), 'files'),
            ],
          ),
          const SizedBox(height: Insets.lg),
          SizedBox(
            width: 460,
            child: Text(
              p.currentPath ?? 'Preparing…',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppType.caption.copyWith(
                color: AppColors.textTertiary,
                fontFeatures: const [],
              ),
            ),
          ),
          const SizedBox(height: Insets.xl),
          HelmButton(
            label: 'Cancel',
            kind: HelmButtonKind.ghost,
            icon: Icons.close_rounded,
            onPressed: widget.onCancel,
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) => Column(
        children: [
          Text(value,
              style: AppType.title.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
          Text(label, style: AppType.caption),
        ],
      );
}

class _RadarPainter extends CustomPainter {
  _RadarPainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = size.width / 2;
    // Expanding pulse rings.
    for (var i = 0; i < 3; i++) {
      final phase = (t + i / 3) % 1.0;
      final r = maxR * phase;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color.withValues(alpha: (1 - phase) * 0.4);
      canvas.drawCircle(center, r, paint);
    }
    // Sweeping arc.
    final sweep = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: 2 * math.pi,
        colors: [color.withValues(alpha: 0), color],
        transform: GradientRotation(t * 2 * math.pi),
      ).createShader(Rect.fromCircle(center: center, radius: maxR));
    canvas.drawCircle(center, maxR - 6, sweep);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) => old.t != t;
}
