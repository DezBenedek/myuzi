import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/voice_wave_bubble.dart';
import 'chat_call_event.dart';

/// Readers whose read cursor sits on this message (Messenger-style).
List<MemberRead> readersAtMessage({
  required List<VoiceMessage> messages,
  required List<MemberRead> memberReads,
  required int index,
  required String meId,
}) {
  final msg = messages[index];
  final nextCreated =
      index + 1 < messages.length ? messages[index + 1].createdAt : null;
  return memberReads.where((r) {
    if (r.userId == meId) return false;
    final at = r.lastReadAt;
    if (at == null || at.isEmpty) return false;
    if (at.compareTo(msg.createdAt) < 0) return false;
    if (nextCreated != null && at.compareTo(nextCreated) >= 0) return false;
    return true;
  }).toList();
}

class ChatMessageList extends StatelessWidget {
  const ChatMessageList({
    super.key,
    required this.messages,
    required this.memberReads,
    required this.scrollController,
    required this.meId,
    required this.playingId,
    required this.playProgress,
    required this.onPlay,
    required this.onMessageActions,
    required this.onCallEventTap,
  });

  final List<VoiceMessage> messages;
  final List<MemberRead> memberReads;
  final ScrollController scrollController;
  final String meId;
  final String? playingId;
  final double playProgress;
  final ValueChanged<VoiceMessage> onPlay;
  final void Function(VoiceMessage msg, {required bool mine}) onMessageActions;
  final ValueChanged<VoiceMessage> onCallEventTap;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      itemCount: messages.length,
      itemBuilder: (context, i) {
        final m = messages[i];
        final mine = m.senderId == meId;
        if (m.isCall) {
          return ChatCallEventBubble(
            message: m,
            mine: mine,
            onTap: () => onCallEventTap(m),
          );
        }
        final readers = readersAtMessage(
          messages: messages,
          memberReads: memberReads,
          index: i,
          meId: meId,
        );
        return ChatVoiceBubble(
          message: m,
          mine: mine,
          readers: readers,
          playing: playingId == m.id,
          progress: playingId == m.id ? playProgress : 0,
          onPlay: () => onPlay(m),
          onLongPress: () => onMessageActions(m, mine: mine),
        );
      },
    );
  }
}

class ChatVoiceBubble extends StatelessWidget {
  const ChatVoiceBubble({
    super.key,
    required this.message,
    required this.mine,
    required this.readers,
    required this.playing,
    required this.progress,
    required this.onPlay,
    required this.onLongPress,
  });

  final VoiceMessage message;
  final bool mine;
  final List<MemberRead> readers;
  final bool playing;
  final double progress;
  final VoidCallback onPlay;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.82,
            minWidth: 160,
          ),
          child: Column(
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(
                  left: mine ? 0 : 4,
                  right: mine ? 4 : 0,
                  bottom: 4,
                ),
                child: Text(
                  mine ? 'Te' : message.senderName,
                  style: t.textTheme.labelMedium?.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: t.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ),
              VoiceWaveBubble(
                mine: mine,
                durationMs: message.durationMs,
                messageId: message.id,
                waveBars: message.waveBars,
                playing: playing,
                progress: progress,
                unread: message.unread && !mine,
                onTap: onPlay,
                onLongPress: onLongPress,
              ),
              if (readers.isNotEmpty) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: EdgeInsets.only(
                    left: mine ? 0 : 6,
                    right: mine ? 6 : 0,
                  ),
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    alignment:
                        mine ? WrapAlignment.end : WrapAlignment.start,
                    children: readers
                        .map(
                          (r) => Tooltip(
                            message: r.name,
                            child: UserAvatar(
                              name: r.name,
                              avatarUrl: r.avatarUrl,
                              userId: r.userId,
                              radius: 10,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
