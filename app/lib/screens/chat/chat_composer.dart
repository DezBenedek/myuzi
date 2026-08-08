import 'package:flutter/material.dart';

import '../../widgets/voice_wave_bubble.dart';
import '../../widgets/widgets.dart';

String formatRecordElapsed(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

class ChatComposer extends StatelessWidget {
  const ChatComposer({
    super.key,
    required this.recording,
    required this.sending,
    required this.recordElapsed,
    required this.waveSamples,
    required this.onToggleRecord,
  });

  final bool recording;
  final bool sending;
  final Duration recordElapsed;
  final List<double> waveSamples;
  final VoidCallback? onToggleRecord;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          children: [
            if (recording)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  children: [
                    Text(
                      'Felvétel · ${formatRecordElapsed(recordElapsed)}',
                      style: t.textTheme.titleLarge?.copyWith(
                        color: t.colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 10),
                    LiveScrollWave(
                      samples: waveSamples,
                      height: 44,
                    ),
                  ],
                ),
              ),
            BigButton(
              label: sending
                  ? 'Küldés…'
                  : recording
                      ? 'Küldés'
                      : 'Hangüzenet',
              icon: recording ? Icons.stop : Icons.mic,
              onPressed: onToggleRecord,
            ),
          ],
        ),
      ),
    );
  }
}
