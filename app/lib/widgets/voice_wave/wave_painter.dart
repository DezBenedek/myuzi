import 'dart:math';

import 'package:flutter/material.dart';

/// Shared painter for message bubbles and live recording preview.
class WavePainter extends CustomPainter {
  WavePainter({
    required this.bars,
    required this.progress,
    required this.idle,
    required this.active,
  });

  final List<double> bars;
  final double progress;
  final Color idle;
  final Color active;

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty || size.width <= 0 || size.height <= 0) return;

    const gap = 2.0;
    final count = bars.length;
    final barW = ((size.width - gap * (count - 1)) / count).clamp(1.5, 6.0);
    final totalW = count * barW + (count - 1) * gap;
    final startX = totalW >= size.width ? 0.0 : (size.width - totalW) / 2;
    final paint = Paint()..style = PaintingStyle.fill;
    final minH = min(3.0, size.height);
    final cursor = progress.clamp(0.0, 1.0) * count;

    for (var i = 0; i < count; i++) {
      final amp = bars[i].clamp(0.18, 1.0);
      final h = max(minH, amp * size.height);
      final x = startX + i * (barW + gap);
      final y = (size.height - h) / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barW, h),
        Radius.circular(barW / 2),
      );

      paint.color = idle;
      canvas.drawRRect(rect, paint);

      final local = cursor - i;
      if (local <= 0) continue;
      paint.color = active;
      if (local >= 1) {
        canvas.drawRRect(rect, paint);
      } else {
        canvas.save();
        canvas.clipRect(Rect.fromLTWH(x, y, barW * local, h));
        canvas.drawRRect(rect, paint);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant WavePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.idle != idle ||
        oldDelegate.active != active ||
        oldDelegate.bars != bars;
  }
}
