import 'dart:math';

import 'package:flutter/material.dart';

/// Instagram-like voice bubble with playback scrub on the waveform.
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
  static const waveHeight = 28.0;

  static List<int> generateBars({int count = barCount}) {
    final rng = Random();
    return List.generate(count, (_) => 1 + rng.nextInt(20));
  }

  static List<int> barsForId(String messageId, {int count = barCount}) {
    final rng = Random(messageId.hashCode);
    return List.generate(count, (_) => 1 + rng.nextInt(20));
  }

  List<double> get _normalizedBars {
    final raw = waveBars.length >= 8 ? waveBars : barsForId(messageId);
    return raw.map((n) => n.clamp(1, 20) / 20.0).toList();
  }

  String _fmt(int ms) {
    final total = (ms / 1000).ceil().clamp(1, 9999);
    final m = total ~/ 60;
    final s = total % 60;
    if (m == 0) return '0:${s.toString().padLeft(2, '0')}';
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// Elapsed while playing, otherwise full duration.
  String get _timeLabel {
    if (playing && progress > 0 && durationMs > 0) {
      return _fmt((durationMs * progress).round());
    }
    return _fmt(durationMs);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final bg = mine ? const Color(0xFF0B6E4F) : const Color(0xFFEEF6F1);
    final fg = mine ? Colors.white : const Color(0xFF12261C);
    // Strong contrast so scrub is obvious (Instagram-like).
    final barIdle = mine
        ? Colors.white.withValues(alpha: 0.28)
        : const Color(0xFFB0C8BB);
    final barActive = mine ? Colors.white : t.colorScheme.primary;
    final bars = _normalizedBars;
    final p = playing ? progress.clamp(0.0, 1.0) : 0.0;

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
                  mainAxisSize: MainAxisSize.min,
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
                    Row(
                      children: [
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final w = constraints.maxWidth;
                              if (w <= 0) {
                                return const SizedBox(height: waveHeight);
                              }
                              return CustomPaint(
                                size: Size(w, waveHeight),
                                painter: _WavePainter(
                                  bars: bars,
                                  progress: p,
                                  idle: barIdle,
                                  active: barActive,
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _timeLabel,
                          style: t.textTheme.labelMedium?.copyWith(
                            color: fg.withValues(alpha: 0.85),
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
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

      // Always draw idle base.
      paint.color = idle;
      canvas.drawRRect(rect, paint);

      // Instagram-style: fill played portion, including partial current bar.
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
  bool shouldRepaint(covariant _WavePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.idle != idle ||
        oldDelegate.active != active ||
        oldDelegate.bars != bars;
  }
}
