import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// A circular progress gauge with a soft track, a rounded sweeping arc, and a
/// widget in the middle. Used for battery charge, memory pressure, etc.
class RingGauge extends StatelessWidget {
  const RingGauge({
    super.key,
    required this.value,
    this.size = 168,
    this.thickness = 14,
    this.color = AppColors.accent,
    this.trackColor = const Color(0x14FFFFFF),
    this.center,
    this.startAt = -0.5, // top, in turns
  });

  /// 0..1.
  final double value;
  final double size;
  final double thickness;
  final Color color;
  final Color trackColor;
  final Widget? center;

  /// Start angle in turns (-0.25 = right, -0.5 = top).
  final double startAt;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
      duration: Motion.slow,
      curve: Motion.emphasized,
      builder: (context, v, _) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _GaugePainter(
            value: v,
            thickness: thickness,
            color: color,
            trackColor: trackColor,
            start: startAt * 2 * math.pi,
          ),
          child: center == null ? null : Center(child: center),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.value,
    required this.thickness,
    required this.color,
    required this.trackColor,
    required this.start,
  });

  final double value;
  final double thickness;
  final Color color;
  final Color trackColor;
  final double start;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (math.min(size.width, size.height) - thickness) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness
        ..color = trackColor,
    );

    if (value <= 0) return;
    final sweep = 2 * math.pi * value.clamp(0.0, 1.0);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: start,
        endAngle: start + 2 * math.pi,
        colors: [color.withValues(alpha: 0.75), color],
        transform: GradientRotation(start),
      ).createShader(rect);
    canvas.drawArc(rect, start, sweep, false, paint);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.value != value || old.color != color;
}
