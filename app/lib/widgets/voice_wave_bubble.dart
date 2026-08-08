import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Collects mic amplitudes while recording and always reduces to [barCount] bars.
///
/// Live UI uses a scrolling window ([liveScrollUnits]); the full take is
/// bucketed into exactly [barCount] bars via [toBars] when sending.
class WaveformCollector {
  WaveformCollector({
    this.barCount = VoiceWaveBubble.barCount,
    this.liveWindow = 56,
  });

  final int barCount;
  /// How many recent samples are visible in the scrolling live preview.
  final int liveWindow;
  final List<double> _samples = [];
  final List<double> _live = [];

  int get sampleCount => _samples.length;

  void reset() {
    _samples.clear();
    _live.clear();
  }

  /// [db] is dBFS from the recorder (typically ~-160…0).
  void addDb(double db) {
    final unit = _dbToUnit(db);
    _samples.add(unit);
    _live.add(unit);
    if (_live.length > liveWindow) {
      _live.removeRange(0, _live.length - liveWindow);
    }
  }

  static double _dbToUnit(double db) {
    // Speech/voice useful range; silence floors low, peaks near 0 dBFS.
    const minDb = -50.0;
    const maxDb = -2.0;
    if (db <= minDb) return 0.08;
    if (db >= maxDb) return 1.0;
    return ((db - minDb) / (maxDb - minDb)).clamp(0.08, 1.0);
  }

  /// Exactly [barCount] ints in 1…20 (peak per bucket) — for the saved message.
  List<int> toBars() {
    if (_samples.isEmpty) {
      return List<int>.filled(barCount, 3);
    }
    final out = List<int>.filled(barCount, 1);
    final n = _samples.length;
    for (var i = 0; i < barCount; i++) {
      final start = (i * n / barCount).floor();
      var end = ((i + 1) * n / barCount).ceil();
      if (end <= start) end = start + 1;
      if (end > n) end = n;
      var peak = 0.0;
      for (var j = start; j < end; j++) {
        final v = _samples[j];
        if (v > peak) peak = v;
      }
      out[i] = (1 + (peak * 19).round()).clamp(1, 20);
    }
    return out;
  }

  /// Newest on the right; oldest slides off the left.
  List<double> liveScrollUnits() => List<double>.from(_live);
}

/// Instagram-like voice bubble with playback scrub on the waveform.
class VoiceWaveBubble extends StatelessWidget {
  const VoiceWaveBubble({
    super.key,
    required this.mine,
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

  static List<int> barsForId(String messageId, {int count = barCount}) {
    final rng = Random(messageId.hashCode);
    return List.generate(count, (_) => 1 + rng.nextInt(20));
  }

  List<double> get _normalizedBars {
    final raw = waveBars.length >= 8 ? waveBars : barsForId(messageId);
    return raw.map((n) => n.clamp(1, 20) / 20.0).toList();
  }

  static String formatMs(int ms) {
    final total = (ms / 1000).round().clamp(0, 99999);
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String get _timeLabel {
    final total = formatMs(durationMs);
    if (playing) {
      final elapsed = formatMs((durationMs * progress.clamp(0.0, 1.0)).round());
      return '$elapsed/$total';
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final Color bg;
    final Color fg;
    final Color barIdle;
    final Color barActive;
    final Color playBg;
    final Color playIcon;

    if (mine) {
      bg = dark ? const Color(0xFF0F5C42) : const Color(0xFF0B6E4F);
      fg = Colors.white;
      barIdle = Colors.white.withValues(alpha: 0.28);
      barActive = Colors.white;
      playBg = Colors.white.withValues(alpha: 0.18);
      playIcon = Colors.white;
    } else if (unread) {
      // Unheard — yellow so it's obvious to listen.
      bg = dark ? AppTheme.unreadYellowDark : AppTheme.unreadYellow;
      fg = const Color(0xFF3A2E00);
      barIdle = const Color(0xFF8A7020).withValues(alpha: 0.45);
      barActive = const Color(0xFF5C4A00);
      playBg = Colors.white.withValues(alpha: 0.55);
      playIcon = const Color(0xFF5C4A00);
    } else {
      bg = dark ? const Color(0xFF24302A) : const Color(0xFFEEF6F1);
      fg = dark ? const Color(0xFFE6F2EC) : const Color(0xFF12261C);
      barIdle = dark ? const Color(0xFF5A7468) : const Color(0xFFB0C8BB);
      barActive = t.colorScheme.primary;
      playBg = dark ? const Color(0xFF1B2620) : Colors.white;
      playIcon = t.colorScheme.primary;
    }
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
          padding: const EdgeInsets.fromLTRB(10, 12, 14, 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: playBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: playIcon,
                  size: 26,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
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
                            painter: WavePainter(
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
                        color: fg.withValues(alpha: 0.9),
                        fontFeatures: const [FontFeature.tabularFigures()],
                        fontSize: 12,
                      ),
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
