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
  static const _maxCachedConversations = 20;
  static const _maxAvatarBytes = 1024 * 1024;
  static const _maxAvatarFiles = 40;
  static const _maxAvatarCacheBytes = 32 * 1024 * 1024;
  static const _maxAudioFiles = 12;
  static const _maxAudioCacheBytes = 64 * 1024 * 1024;
  static const _maxAudioBytes = 20 * 1024 * 1024;
  static Future<void>? _prefetchInFlight;

  static Future<void> trimCaches() async {
    await Future.wait([_trimAvatarFiles(), _trimAudioFiles()]);
  }

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
    try {
      final file = await avatarFile(userId);
      if (!await file.exists()) return null;
      if (await file.length() > _maxAvatarBytes) {
        await file.delete();
        return null;
      }
      return file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  static Future<void> putAvatarBytes(String userId, Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > _maxAvatarBytes) return;
    final file = await avatarFile(userId);
    await file.writeAsBytes(bytes, flush: true);
    await _trimAvatarFiles();
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
    try {
      final file = await audioFile(messageId);
      if (!await file.exists()) return false;
      if (await file.length() > _maxAudioBytes) {
        await file.delete();
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> putAudio(String messageId, Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > _maxAudioBytes) return;
    final file = await audioFile(messageId);
    await file.writeAsBytes(bytes, flush: true);
    await _trimAudioFiles(recentIds: {messageId});
  }

  static Future<Uint8List?> readAudio(String messageId) async {
    try {
      final file = await audioFile(messageId);
      if (!await file.exists()) return null;
      if (await file.length() > _maxAudioBytes) {
        await file.delete();
        return null;
      }
      return file.readAsBytes();
    } catch (_) {
      return null;
    }
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

  /// Download and store audio for the newest [keep] messages (files only).
  static Future<void> prefetchAudio(
    ApiClient api,
    List<VoiceMessage> messages, {
    int keep = 3,
  }) {
    final active = _prefetchInFlight;
    if (active != null) return active;

    final future = _prefetchAudio(api, messages, keep: keep);
    _prefetchInFlight = future;
    future.then(
      (_) {
        if (identical(_prefetchInFlight, future)) _prefetchInFlight = null;
      },
      onError: (_, _) {
        if (identical(_prefetchInFlight, future)) _prefetchInFlight = null;
      },
    );
    return future;
  }

  static Future<void> _prefetchAudio(
    ApiClient api,
    List<VoiceMessage> messages, {
    required int keep,
  }) async {
    final newest = messages.length > keep ? messages.sublist(messages.length - keep) : messages;
    for (final m in newest.reversed) {
      try {
        if (m.isCall || m.url == null || m.url!.isEmpty) continue;
        if (await hasAudio(m.id)) continue;
        final bytes = await api.downloadAudio(m.url!);
        await putAudio(m.id, bytes);
      } catch (_) {
        // Best-effort cache.
      }
    }
    await _trimAudioFiles(recentIds: newest.map((m) => m.id).toSet());
  }

  static Future<void> _trimAvatarFiles() async {
    try {
      final dir = await _avatarDir();
      final files = await dir.list().where((e) => e is File).cast<File>().toList();
      final entries = <({File file, int bytes, DateTime modified})>[];
      for (final file in files) {
        final stat = await file.stat();
        entries.add((file: file, bytes: stat.size, modified: stat.modified));
      }
      entries.sort((a, b) => b.modified.compareTo(a.modified));

      var kept = 0;
      var total = 0;
      for (final entry in entries) {
        if (kept < _maxAvatarFiles &&
            total + entry.bytes <= _maxAvatarCacheBytes) {
          kept++;
          total += entry.bytes;
        } else {
          await entry.file.delete();
        }
      }
    } catch (_) {}
  }

  static Future<void> _trimAudioFiles({
    Set<String> recentIds = const {},
  }) async {
    try {
      final dir = await _audioDir();
      final files = await dir.list().where((e) => e is File).cast<File>().toList();
      final entries = <({File file, int bytes, DateTime modified})>[];
      for (final file in files) {
        final stat = await file.stat();
        entries.add((file: file, bytes: stat.size, modified: stat.modified));
      }
      entries.sort((a, b) => b.modified.compareTo(a.modified));

      var kept = 0;
      var total = 0;
      for (final entry in entries) {
        final id = entry.file.uri.pathSegments.last.replaceAll('.m4a', '');
        final keep = (recentIds.contains(id) && entry.bytes <= _maxAudioBytes) ||
            (kept < _maxAudioFiles &&
                total + entry.bytes <= _maxAudioCacheBytes);
        if (keep) {
          kept++;
          total += entry.bytes;
          continue;
        }
        await entry.file.delete();
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
        'kind': m.kind,
        'callId': m.callId,
        'callStatus': m.callStatus,
        'callType': m.callType,
      };
}
