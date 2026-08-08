import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/models.dart';

/// SharedPreferences cache for home list and message metadata.
class PrefsCache {
  PrefsCache._();

  static const _homeKey = 'cache_home_v1';
  static const _userKey = 'cache_user_v1';
  static String _messagesKey(String conversationId) => 'cache_msgs_v1_$conversationId';
  static const _maxCachedConversations = 20;

  static Future<void> saveUser(User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(user.toJson()));
  }

  static Future<User?> loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_userKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return User.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
  }

  static Future<void> saveHome({
    required List<ConversationSummary> conversations,
    required List<FamilyMember> people,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _homeKey,
      jsonEncode({
        'conversations': conversations.map(_conversationJson).toList(),
        'people': people.map(_memberJson).toList(),
      }),
    );
  }

  static Future<({List<ConversationSummary> conversations, List<FamilyMember> people})?>
      loadHome() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_homeKey);
    if (raw == null) return null;
    try {
      final body = jsonDecode(raw) as Map<String, dynamic>;
      return (
        conversations: ((body['conversations'] as List?) ?? [])
            .map((e) => ConversationSummary.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        people: ((body['people'] as List?) ?? [])
            .map((e) => FamilyMember.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveMessages(String conversationId, List<VoiceMessage> messages) async {
    final prefs = await SharedPreferences.getInstance();
    // Keep newest 50 metadata entries.
    final trimmed = messages.length > 50 ? messages.sublist(messages.length - 50) : messages;
    await prefs.setString(
      _messagesKey(conversationId),
      jsonEncode(trimmed.map(_messageJson).toList()),
    );
    final messageKeys = prefs
        .getKeys()
        .where((key) => key.startsWith('cache_msgs_v1_'))
        .toList();
    if (messageKeys.length > _maxCachedConversations) {
      final removable = messageKeys
          .where((key) => key != _messagesKey(conversationId))
          .take(messageKeys.length - _maxCachedConversations);
      for (final key in removable) {
        await prefs.remove(key);
      }
    }
  }

  static Future<List<VoiceMessage>?> loadMessages(String conversationId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_messagesKey(conversationId));
    if (raw == null) return null;
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => VoiceMessage.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _memberJson(FamilyMember m) => {
        'id': m.id,
        'name': m.name,
        'email': m.email,
        'role': m.role,
        'avatarUrl': m.avatarUrl,
      };

  static Map<String, dynamic> _conversationJson(ConversationSummary c) => {
        'id': c.id,
        'type': c.type,
        'name': c.name,
        'memberCount': c.memberCount,
        'lastMessageAt': c.lastMessageAt,
        'lastSenderName': c.lastSenderName,
        'avatarUrl': c.avatarUrl,
        'pinned': c.pinned,
        'unreadCount': c.unreadCount,
        'members': c.members.map(_memberJson).toList(),
      };

  static Map<String, dynamic> _messageJson(VoiceMessage m) => {
        'id': m.id,
        'conversationId': m.conversationId,
        'senderId': m.senderId,
        'senderName': m.senderName,
        'durationMs': m.durationMs,
        'createdAt': m.createdAt,
        'url': m.url,
        'unread': m.unread,
        'waveBars': m.waveBars,
        'kind': m.kind,
        'callId': m.callId,
        'callStatus': m.callStatus,
        'callType': m.callType,
      };
}
