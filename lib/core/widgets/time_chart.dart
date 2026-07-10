import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// A timestamped value for [TimeChart].
class TimePoint {
  const TimePoint(this.tMs, this.value);
  final int tMs;
  final double value;
}

/// Smooth filled line chart over a trailing time window — the 24 h history
/// view on the monitor pages. Auto-scales the y-axis unless [maxY] pins it
/// (e.g. 100 for percentages), draws soft horizontal gridlines and start/mid/
/// end time labels, and annotates the peak.
class TimeChart extends StatelessWidget {
  const TimeChart({
    super.key,
    required this.points,
    required this.window,
    required this.color,
    this.maxY,
    this.height = 150,
    this.formatValue,
  });

  final List<TimePoint> points;
  final Duration window;
  final Color color;
  final double? maxY;
  final double height;
  final String Function(double v)? formatValue;

  String _fmt(double v) =>
      formatValue?.call(v) ?? '${v.toStringAsFixed(0)}%';

  String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = now.subtract(window);
    final mid = now.subtract(window ~/ 2);
    final peak = points.isEmpty
        ? 0.0
        : points.map((p) => p.value).reduce(math.max);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: points.length < 2
              ? Center(
                  child: Text(
                    'Collecting history…',
                    style: AppType.caption
                        .copyWith(color: AppColors.textTertiary),
                  ),
                )
              : CustomPaint(
                  painter: _TimeChartPainter(
                    points: points,
                    startMs: start.millisecondsSinceEpoch,
                    endMs: now.millisecondsSinceEpoch,
                    color: color,
                    maxY: maxY,
                  ),
                ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(_clock(start), style: AppType.micro),
            const Spacer(),
            Text(_clock(mid), style: AppType.micro),
            const Spacer(),
            if (points.isNotEmpty)
              Text('peak ${_fmt(peak)} · ', style: AppType.micro),
            Text('now', style: AppType.micro),
          ],
        ),
      ],
    );
  }
}

class _TimeChartPainter extends CustomPainter {
  _TimeChartPainter({
    required this.points,
    required this.startMs,
    required this.endMs,
    required this.color,
    this.maxY,
  });

  final List<TimePoint> points;
  final int startMs;
  final int endMs;
  final Color color;
  final double? maxY;

  @override
  void paint(Canvas canvas, Size size) {
    // Gridlines at 1/4, 1/2, 3/4.
    final grid = Paint()
      ..color = AppColors.stroke.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (final f in [0.25, 0.5, 0.75]) {
      final y = size.height * f;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (points.length < 2 || endMs <= startMs) return;

    final top = maxY ??
        math.max(points.map((p) => p.value).reduce(math.max) * 1.15, 1);
    final span = (endMs - startMs).toDouble();

    Offset toOffset(TimePoint p) => Offset(
          ((p.tMs - startMs) / span).clamp(0.0, 1.0) * size.width,
          size.height - (p.value / top).clamp(0.0, 1.0) * size.height,
        );

    // Split into contiguous segments: a big gap between samples (restart,
    // sleep) must show as a gap, not a fabricated straight line across hours.
    const gapMs = 5 * 60 * 1000;
    final segments = <List<Offset>>[];
    var current = <Offset>[toOffset(points.first)];
    for (var i = 1; i < points.length; i++) {
      if (points[i].tMs - points[i - 1].tMs > gapMs) {
        segments.add(current);
        current = <Offset>[];
      }
      current.add(toOffset(points[i]));
    }
    segments.add(current);

    final areaPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(0, size.height),
        [color.withValues(alpha: 0.28), color.withValues(alpha: 0.02)],
      );
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    for (final seg in segments) {
      if (seg.isEmpty) continue;
      if (seg.length == 1) {
        canvas.drawCircle(seg.first, 2, Paint()..color = color);
        continue;
      }
      final line = Path()..moveTo(seg.first.dx, seg.first.dy);
      for (final o in seg.skip(1)) {
        line.lineTo(o.dx, o.dy);
      }
      final area = Path.from(line)
        ..lineTo(seg.last.dx, size.height)
        ..lineTo(seg.first.dx, size.height)
        ..close();
      canvas.drawPath(area, areaPaint);
      canvas.drawPath(line, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TimeChartPainter old) =>
      old.points != points || old.endMs != endMs || old.color != color;
}
