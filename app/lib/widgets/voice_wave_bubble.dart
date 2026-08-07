import 'dart:math';

import 'package:flutter/material.dart';

/// Instagram-like voice bubble. Bars are ints 1–20 from the message (or fallback).
class VoiceWaveBubble extends StatelessWidget {
  const VoiceWaveBubble({
    super.key,
    required this.mine,
    required this.senderLabel,
    required this.durationMs,
    required this.messageId,
    required this.waveBars,
    required this.playing,
    required this.progress,
    required this.unread,
    required this.onTap,
    this.onLongPress,
  });

  final bool mine;
  final String senderLabel;
  final int durationMs;
  final String messageId;
  final List<int> waveBars;
  final bool playing;
  final double progress; // 0..1 while playing
  final bool unread;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  static const barCount = 32;

  /// Random heights 1–20, used when sending a new voice note.
  static List<int> generateBars({int count = barCount}) {
    final rng = Random();
    return List.generate(count, (_) => 1 + rng.nextInt(20));
  }

  /// Stable fallback for older messages without stored bars.
  static List<int> barsForId(String messageId, {int count = barCount}) {
    final rng = Random(messageId.hashCode);
    return List.generate(count, (_) => 1 + rng.nextInt(20));
  }

  List<double> get _normalizedBars {
    final raw = waveBars.length >= 8 ? waveBars : barsForId(messageId);
    return raw.map((n) => (n.clamp(1, 20)) / 20.0).toList();
  }

  String _fmt(int ms) {
    final total = (ms / 1000).ceil().clamp(1, 9999);
    final m = total ~/ 60;
    final s = total % 60;
    if (m == 0) return '0:${s.toString().padLeft(2, '0')}';
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final bg = mine ? const Color(0xFF0B6E4F) : const Color(0xFFEEF6F1);
    final fg = mine ? Colors.white : const Color(0xFF12261C);
    final barIdle = mine ? Colors.white.withValues(alpha: 0.45) : const Color(0xFF9BB5A8);
    final barActive = mine ? Colors.white : t.colorScheme.primary;
    final bars = _normalizedBars;

    return Material(
      color: bg,
      borderRadius: BorderRadius.only(
        topLeft: const Radius.circular(20),
        topRight: const Radius.circular(20),
        bottomLeft: Radius.circular(mine ? 20 : 6),
        bottomRight: Radius.circular(mine ? 6 : 20),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(mine ? 20 : 6),
          bottomRight: Radius.circular(mine ? 6 : 20),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
          // Force full width of parent ConstrainedBox — CustomPaint needs real width.
          child: SizedBox(
            width: double.infinity,
            child: Row(
              children: [
                if (unread && !mine)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: t.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: mine ? Colors.white.withValues(alpha: 0.18) : Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: mine ? Colors.white : t.colorScheme.primary,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        senderLabel,
                        style: t.textTheme.labelLarge?.copyWith(
                          color: fg,
                          fontWeight:
                              unread && !mine ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 28,
                        child: Row(
                          children: [
                            Expanded(
                              child: CustomPaint(
                                painter: _WavePainter(
                                  bars: bars,
                                  progress: playing ? progress.clamp(0.0, 1.0) : 0,
                                  idle: barIdle,
                                  active: barActive,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _fmt(durationMs),
                              style: t.textTheme.labelMedium?.copyWith(
                                color: fg.withValues(alpha: 0.85),
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({
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
    if (bars.isEmpty || size.width <= 0) return;
    final gap = 2.0;
    final barW = ((size.width - gap * (bars.length - 1)) / bars.length).clamp(1.5, 8.0);
    final paint = Paint()..style = PaintingStyle.fill;
    final totalW = bars.length * barW + (bars.length - 1) * gap;
    final startX = ((size.width - totalW) / 2).clamp(0.0, size.width);

    for (var i = 0; i < bars.length; i++) {
      final h = (bars[i] * size.height).clamp(4.0, size.height);
      final x = startX + i * (barW + gap);
      final y = (size.height - h) / 2;
      final filled = progress <= 0 ? false : ((i + 1) / bars.length) <= progress;
      paint.color = filled ? active : idle;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barW, h),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.idle != idle ||
        oldDelegate.active != active ||
        oldDelegate.bars != bars;
  }
}
