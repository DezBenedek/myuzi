import 'dart:math';

import 'package:flutter/material.dart';

/// Scrolling live waveform: newest bars enter on the right, oldest slide off left.
class LiveScrollWave extends StatelessWidget {
  const LiveScrollWave({
    super.key,
    required this.samples,
    this.height = 40,
  });

  final List<double> samples;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final idle = dark
        ? t.colorScheme.primary.withValues(alpha: 0.25)
        : t.colorScheme.primary.withValues(alpha: 0.28);
    final active = t.colorScheme.primary;
    final track = dark ? const Color(0xFF1B2620) : const Color(0xFFE8F2EC);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: track,
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _LiveScrollPainter(
              samples: samples,
              idle: idle,
              active: active,
              track: track,
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveScrollPainter extends CustomPainter {
  _LiveScrollPainter({
    required this.samples,
    required this.idle,
    required this.active,
    required this.track,
  });

  final List<double> samples;
  final Color idle;
  final Color active;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    const gap = 2.0;
    const barW = 3.5;
    final step = barW + gap;
    final capacity = max(1, ((size.width + gap) / step).floor());
    final paint = Paint()..style = PaintingStyle.fill;
    final minH = min(3.0, size.height);

    // Pad left with near-silence so the wave grows in from the right.
    final visible = <double>[
      ...List<double>.filled(max(0, capacity - samples.length), 0.05),
      ...samples.length > capacity
          ? samples.sublist(samples.length - capacity)
          : samples,
    ];

    // Flush to the right so as new samples arrive, the ribbon scrolls left.
    final totalW = visible.length * barW + max(0, visible.length - 1) * gap;
    final startX = size.width - totalW;

    for (var i = 0; i < visible.length; i++) {
      final amp = visible[i].clamp(0.05, 1.0);
      final h = max(minH, amp * size.height * 0.92);
      final y = (size.height - h) / 2;
      final age = visible.length == 1 ? 1.0 : i / (visible.length - 1);
      paint.color = Color.lerp(idle, active, 0.25 + 0.75 * age)!;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(startX + i * step, y, barW, h),
          const Radius.circular(1.5),
        ),
        paint,
      );
    }

    // Left edge fade — looks like bars are sliding out of frame.
    final fadeW = min(36.0, size.width * 0.2);
    final fadePaint = Paint()
      ..shader = LinearGradient(
        colors: [track, track.withValues(alpha: 0)],
      ).createShader(Rect.fromLTWH(0, 0, fadeW, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, fadeW, size.height), fadePaint);
  }

  @override
  bool shouldRepaint(covariant _LiveScrollPainter oldDelegate) {
    if (oldDelegate.idle != idle ||
        oldDelegate.active != active ||
        oldDelegate.track != track) {
      return true;
    }
    if (oldDelegate.samples.length != samples.length) return true;
    // Compare last few samples (enough for live feel).
    final n = min(8, samples.length);
    for (var i = 1; i <= n; i++) {
      if (oldDelegate.samples[oldDelegate.samples.length - i] !=
          samples[samples.length - i]) {
        return true;
      }
    }
    return false;
  }
}
