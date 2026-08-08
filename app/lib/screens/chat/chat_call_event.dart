import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../services/api_client.dart';
import '../../services/call_navigation.dart';
import '../../services/toast.dart';

String formatCallDuration(int ms) {
  final total = (ms / 1000).round().clamp(0, 24 * 60 * 60);
  final m = total ~/ 60;
  final s = total % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

String callEventLabel(VoiceMessage m) {
  final video = m.callType == 'video';
  final kind = video ? 'Videóhívás' : 'Hanghívás';
  switch (m.callStatus) {
    case 'ringing':
      return 'Csengő ${video ? 'videó' : 'hang'}hívás — koppints a csatlakozáshoz';
    case 'active':
      return 'Folyamatban lévő ${video ? 'videó' : 'hang'}hívás — koppints a csatlakozáshoz';
    case 'missed':
      return 'Nem fogadott ${video ? 'videó' : 'hang'}hívás';
    case 'ended':
      return '$kind · ${formatCallDuration(m.durationMs)}';
    default:
      return kind;
  }
}

IconData callEventIcon(VoiceMessage m) {
  switch (m.callStatus) {
    case 'missed':
      return Icons.call_missed_outgoing;
    case 'ended':
      return Icons.call_end;
    case 'active':
      return Icons.phone_in_talk;
    default:
      return m.callType == 'video' ? Icons.videocam : Icons.call;
  }
}

/// Join a ringing/active call from a chat call-event bubble.
Future<void> joinCallFromChatEvent({
  required BuildContext context,
  required ApiClient api,
  required GoRouter router,
  required VoiceMessage message,
  required String title,
}) async {
  final callId = message.callId;
  if (callId == null || callId.isEmpty) return;
  final status = message.callStatus;
  if (status != 'ringing' && status != 'active') {
    if (context.mounted) {
      showAppToast(
        context,
        status == 'missed' ? 'Ez a hívás már lejárt' : 'A hívás véget ért',
      );
    }
    return;
  }
  try {
    await joinAndOpenCall(
      api: api,
      router: router,
      callId: callId,
      title: title,
    );
  } on ApiException catch (e) {
    if (context.mounted) showAppToast(context, e.message, error: true);
  } catch (_) {
    if (context.mounted) {
      showAppToast(context, 'A hívás nem érhető el', error: true);
    }
  }
}

class ChatCallEventBubble extends StatelessWidget {
  const ChatCallEventBubble({
    super.key,
    required this.message,
    required this.mine,
    this.onTap,
  });

  final VoiceMessage message;
  final bool mine;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final missed = message.callStatus == 'missed';
    final joinable =
        message.callStatus == 'ringing' || message.callStatus == 'active';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.9,
          ),
          child: Material(
            color: t.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: joinable ? onTap : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      callEventIcon(message),
                      size: 20,
                      color: missed
                          ? t.colorScheme.error
                          : t.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '${mine ? 'Te' : message.senderName} · ${callEventLabel(message)}',
                        textAlign: TextAlign.center,
                        style: t.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: missed
                              ? t.colorScheme.error
                              : t.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
