import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/widgets.dart';
import 'conversation_preview.dart';

class ConversationTile extends StatelessWidget {
  const ConversationTile({
    super.key,
    required this.conversation,
    required this.onLongPress,
  });

  final ConversationSummary conversation;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = conversation;
    final unread = c.unreadCount > 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SoftCard(
        onTap: () => context.push('/chat/${c.id}'),
        onLongPress: onLongPress,
        child: Row(
          children: [
            Stack(
              children: [
                UserAvatar(
                  name: c.name,
                  avatarUrl: c.avatarUrl,
                  radius: 28,
                  highlight: unread,
                ),
                if (c.pinned)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: t.colorScheme.surface,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.push_pin,
                        size: 14,
                        color: t.colorScheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.name,
                    style: t.textTheme.titleLarge?.copyWith(
                      fontWeight: unread ? FontWeight.w800 : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    conversationPreview(c),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.bodyMedium?.copyWith(
                      fontWeight: unread ? FontWeight.w700 : FontWeight.w400,
                      color: unread
                          ? t.colorScheme.primary
                          : t.colorScheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),
            if (unread)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: t.colorScheme.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${c.unreadCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
