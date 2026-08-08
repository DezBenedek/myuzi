import 'dart:math';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'wave_painter.dart';

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
