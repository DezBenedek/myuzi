import 'package:flutter/material.dart';

import '../../widgets/widgets.dart';

class CallRoundAction extends StatelessWidget {
  const CallRoundAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: danger ? const Color(0xFFB42318) : Colors.white12,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 68,
              height: 68,
              child: Icon(icon, color: Colors.white, size: 30),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// Returns `'leave'`, `'end'`, or `null` if cancelled.
Future<String?> showCallHangUpSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    backgroundColor: const Color(0xFF1A2A22),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Kilépés a hívásból',
                style: Theme.of(ctx)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                'A többiek folytathatják, vagy mindenki számára bontod.',
                style: Theme.of(ctx)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              BigButton(
                label: 'Csak én lépek ki',
                icon: Icons.logout,
                onPressed: () => Navigator.pop(ctx, 'leave'),
              ),
              const SizedBox(height: 8),
              BigButton(
                label: 'Mindenki számára bontás',
                icon: Icons.call_end,
                danger: true,
                onPressed: () => Navigator.pop(ctx, 'end'),
              ),
              const SizedBox(height: 8),
              BigButton(
                label: 'Mégse',
                outlined: true,
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
        ),
      );
    },
  );
}
