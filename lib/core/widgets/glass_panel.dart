import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// The building block of Helm's UI: a translucent, softly-bordered surface that
/// lets the window gradient/vibrancy read through.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Insets.lg),
    this.radius = Radii.lg,
    this.color,
    this.border,
    this.blur = false,
    this.gradient,
    this.glow,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final Color? border;
  final bool blur;
  final Gradient? gradient;
  final Color? glow;

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);
    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? AppColors.glass) : null,
        gradient: gradient,
        borderRadius: br,
        border: Border.all(color: border ?? AppColors.stroke, width: 1),
        boxShadow: glow != null
            ? [BoxShadow(color: glow!, blurRadius: 32, spreadRadius: -6)]
            : null,
      ),
      child: child,
    );

    if (blur) {
      content = ClipRRect(
        borderRadius: br,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: content,
        ),
      );
    }
    return content;
  }
}
