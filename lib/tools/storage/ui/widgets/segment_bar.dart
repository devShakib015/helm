import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';

class BarSegment {
  const BarSegment(this.value, this.color);
  final double value;
  final Color color;
}

/// macOS-style horizontal storage bar: proportional colour segments with hair
/// gaps, sweeping in from the left.
class SegmentBar extends StatelessWidget {
  const SegmentBar({
    super.key,
    required this.segments,
    this.height = 14,
    this.trackColor = const Color(0x14FFFFFF),
  });

  final List<BarSegment> segments;
  final double height;
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    final total = segments.fold<double>(0, (s, e) => s + e.value);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Motion.slow,
        curve: Motion.emphasized,
        builder: (context, t, _) {
          return Container(
            height: height,
            color: trackColor,
            child: total <= 0
                ? null
                : Row(
                    children: [
                      for (final seg in segments)
                        if (seg.value > 0)
                          Expanded(
                            flex: (seg.value / total * 10000 * t)
                                .clamp(0, 1 << 31)
                                .round()
                                .clamp(1, 1 << 31),
                            child: Padding(
                              padding: const EdgeInsets.only(right: 1.5),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: [
                                    seg.color.withValues(alpha: 0.85),
                                    seg.color,
                                  ]),
                                ),
                              ),
                            ),
                          ),
                      // Remaining free track.
                      Expanded(
                        flex: ((1 - t) * 10000).round().clamp(1, 1 << 31),
                        child: const SizedBox(),
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }
}
