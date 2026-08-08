import '../../models/models.dart';

String conversationPreview(ConversationSummary c) {
  if (c.unreadCount > 0) {
    if (c.lastSenderName != null && c.lastSenderName!.isNotEmpty) {
      return c.unreadCount == 1
          ? '${c.lastSenderName}: új hangüzenet'
          : '${c.lastSenderName}: ${c.unreadCount} új hangüzenet';
    }
    return c.unreadCount == 1 ? 'Új hangüzenet' : '${c.unreadCount} új hangüzenet';
  }
  if (c.lastMessageAt != null) {
    if (c.lastSenderName != null && c.lastSenderName!.isNotEmpty) {
      return '${c.lastSenderName}: hangüzenet';
    }
    return 'Hangüzenet';
  }
  return 'Nincs még üzenet';
}
