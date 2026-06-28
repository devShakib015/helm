import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

class DonutSegment {
  const DonutSegment(this.value, this.color, {this.label});
  final double value;
  final Color color;
  final String? label;
}

/// Animated donut/ring. Sweeps in once on build; the [center] widget sits in
/// the hole.
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.segments,
    this.size = 200,
    this.thickness = 18,
    this.center,
    this.gapDegrees = 2,
  });

  final List<DonutSegment> segments;
  final double size;
  final double thickness;
  final Widget? center;
  final double gapDegrees;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.slow,
      curve: Motion.emphasized,
      builder: (context, t, _) {
        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _DonutPainter(
              segments: segments,
              thickness: thickness,
              gap: gapDegrees * math.pi / 180,
              progress: t,
            ),
            child: center == null ? null : Center(child: center),
          ),
        );
      },
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.segments,
    required this.thickness,
    required this.gap,
    required this.progress,
  });

  final List<DonutSegment> segments;
  final double thickness;
  final double gap;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (math.min(size.width, size.height) - thickness) / 2;
    final ring = Rect.fromCircle(center: center, radius: radius);

    // Track.
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..color = const Color(0x14FFFFFF);
    canvas.drawCircle(center, radius, track);

    final total = segments.fold<double>(0, (s, e) => s + e.value);
    if (total <= 0) return;

    const start = -math.pi / 2;
    var angle = start;
    final visible = segments.where((s) => s.value > 0).toList();
    for (var i = 0; i < visible.length; i++) {
      final seg = visible[i];
      final fraction = seg.value / total;
      final fullSweep = fraction * 2 * math.pi;
      final sweep = fullSweep * progress;
      final useGap = visible.length > 1 ? gap : 0.0;
      final drawSweep = (sweep - useGap).clamp(0.0, 2 * math.pi);

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: angle,
          endAngle: angle + fullSweep,
          colors: [seg.color.withValues(alpha: 0.85), seg.color],
        ).createShader(ring);

      if (drawSweep > 0) {
        canvas.drawArc(ring, angle + useGap / 2, drawSweep, false, paint);
      }
      angle += fullSweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.progress != progress || old.segments != segments;
}

/// Convenience: build donut segments from category-like data plus a free slice.
List<DonutSegment> usageSegments({
  required int used,
  required int purgeable,
  required int free,
}) =>
    [
      DonutSegment(used.toDouble(), AppColors.accent, label: 'Used'),
      DonutSegment(purgeable.toDouble(), AppColors.purgeable, label: 'Purgeable'),
      DonutSegment(free.toDouble(), AppColors.free, label: 'Free'),
    ];
