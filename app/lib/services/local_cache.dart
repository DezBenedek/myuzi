import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'api_client.dart';

/// Disk + SharedPreferences cache for home list, message metadata, and audio files.
class LocalCache {
  LocalCache._();

  static const _homeKey = 'cache_home_v1';
  static String _messagesKey(String conversationId) => 'cache_msgs_v1_$conversationId';

  static Future<Directory> _avatarDir() async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/avatar_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<File> avatarFile(String userId) async {
    final dir = await _avatarDir();
    return File('${dir.path}/$userId.bin');
  }

  static Future<Uint8List?> loadAvatarBytes(String userId) async {
    final file = await avatarFile(userId);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  static Future<void> putAvatarBytes(String userId, Uint8List bytes) async {
    final file = await avatarFile(userId);
    await file.writeAsBytes(bytes, flush: true);
  }

  static Future<void> clearAvatar(String userId) async {
    final file = await avatarFile(userId);
    if (await file.exists()) await file.delete();
  }

  static Future<Directory> _audioDir() async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/voice_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<File> audioFile(String messageId) async {
    final dir = await _audioDir();
    return File('${dir.path}/$messageId.m4a');
  }

  static Future<bool> hasAudio(String messageId) async {
    return (await audioFile(messageId)).exists();
  }

  static Future<void> putAudio(String messageId, Uint8List bytes) async {
    final file = await audioFile(messageId);
    await file.writeAsBytes(bytes, flush: true);
  }

  static Future<Uint8List?> readAudio(String messageId) async {
    final file = await audioFile(messageId);
    if (!await file.exists()) return null;
    return file.readAsBytes();
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

  /// Download and store audio for the newest [keep] messages (files only).
  static Future<void> prefetchAudio(
    ApiClient api,
    List<VoiceMessage> messages, {
    int keep = 8,
  }) async {
    final newest = messages.length > keep ? messages.sublist(messages.length - keep) : messages;
    for (final m in newest.reversed) {
      try {
        if (await hasAudio(m.id)) continue;
        final bytes = await api.downloadAudio(m.url);
        await putAudio(m.id, bytes);
      } catch (_) {
        // Best-effort cache.
      }
    }
    await _trimAudioFiles(keepPerConversation: keep, recentIds: newest.map((m) => m.id).toSet());
  }

  static Future<void> _trimAudioFiles({
    required int keepPerConversation,
    required Set<String> recentIds,
  }) async {
    try {
      final dir = await _audioDir();
      final files = await dir.list().where((e) => e is File).cast<File>().toList();
      // Keep recent ids + newest files overall (cap disk use).
      files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      var kept = 0;
      for (final f in files) {
        final id = f.uri.pathSegments.last.replaceAll('.m4a', '');
        if (recentIds.contains(id) || kept < 40) {
          kept++;
          continue;
        }
        await f.delete();
      }
    } catch (_) {}
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
      };
}
