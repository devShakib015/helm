import 'package:flutter/material.dart';

/// A compact, smooth area sparkline. Plots a list of [samples] (oldest first,
/// newest last) as a Catmull-Rom-smoothed line with a soft gradient fill
/// beneath it. Self-scales to the largest sample so the curve always uses the
/// full height. Degrades gracefully to an empty canvas when there's no data.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.samples,
    required this.color,
    this.height = 56,
    this.strokeWidth = 2,
  });

  final List<double> samples;
  final Color color;
  final double height;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparklinePainter(
          samples: samples,
          color: color,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.samples,
    required this.color,
    required this.strokeWidth,
  });

  final List<double> samples;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2 || size.width <= 0 || size.height <= 0) return;

    final w = size.width;
    final h = size.height;

    // Scale to the peak value, with a small headroom so the line never kisses
    // the top edge. A floor avoids divide-by-zero on a flat-zero series.
    var peak = 0.0;
    for (final v in samples) {
      if (v > peak) peak = v;
    }
    if (peak <= 0) peak = 1;
    final maxY = peak * 1.15;

    final n = samples.length;
    final dx = w / (n - 1);
    const padTop = 1.0;
    final usable = h - strokeWidth - padTop;

    final points = <Offset>[];
    for (var i = 0; i < n; i++) {
      final norm = (samples[i] / maxY).clamp(0.0, 1.0);
      final x = i * dx;
      final y = padTop + (1 - norm) * usable;
      points.add(Offset(x, y));
    }

    // Build a smooth path through the points using Catmull-Rom -> cubic Bézier.
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 0; i < n - 1; i++) {
      final p0 = points[i == 0 ? 0 : i - 1];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = points[i + 2 < n ? i + 2 : n - 1];

      final c1 = Offset(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
      );
      final c2 = Offset(
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
      );
      line.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }

    // Area fill: close the line path down to the baseline.
    final area = Path.from(line)
      ..lineTo(points.last.dx, h)
      ..lineTo(points.first.dx, h)
      ..close();

    canvas.drawPath(
      area,
      Paint()
        ..style = PaintingStyle.fill
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.28),
            color.withValues(alpha: 0.02),
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );

    // A bright dot on the newest sample.
    canvas.drawCircle(
      points.last,
      strokeWidth + 1.2,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.samples != samples ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}
