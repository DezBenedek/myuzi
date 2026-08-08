import 'dart:io';
import 'dart:typed_data';

import '../../models/models.dart';
import '../api_client.dart';
import 'audio_cache.dart';
import 'avatar_cache.dart';
import 'prefs_cache.dart';

/// Disk + SharedPreferences cache for home list, message metadata, and audio files.
class LocalCache {
  LocalCache._();

  static Future<void> trimCaches() async {
    await Future.wait([AvatarCache.trim(), AudioCache.trim()]);
  }

  static Future<File> avatarFile(String userId) => AvatarCache.file(userId);

  static Future<Uint8List?> loadAvatarBytes(String userId) =>
      AvatarCache.loadBytes(userId);

  static Future<void> putAvatarBytes(String userId, Uint8List bytes) =>
      AvatarCache.putBytes(userId, bytes);

  static Future<void> clearAvatar(String userId) => AvatarCache.clear(userId);

  static Future<File> audioFile(String messageId) => AudioCache.file(messageId);

  static Future<bool> hasAudio(String messageId) => AudioCache.has(messageId);

  static Future<void> putAudio(String messageId, Uint8List bytes) =>
      AudioCache.put(messageId, bytes);

  static Future<Uint8List?> readAudio(String messageId) => AudioCache.read(messageId);

  static Future<void> saveHome({
    required List<ConversationSummary> conversations,
    required List<FamilyMember> people,
  }) =>
      PrefsCache.saveHome(conversations: conversations, people: people);

  static Future<({List<ConversationSummary> conversations, List<FamilyMember> people})?>
      loadHome() => PrefsCache.loadHome();

  static Future<void> saveMessages(String conversationId, List<VoiceMessage> messages) =>
      PrefsCache.saveMessages(conversationId, messages);

  static Future<List<VoiceMessage>?> loadMessages(String conversationId) =>
      PrefsCache.loadMessages(conversationId);

  static Future<void> saveUser(User user) => PrefsCache.saveUser(user);

  static Future<User?> loadUser() => PrefsCache.loadUser();

  static Future<void> clearUser() => PrefsCache.clearUser();

  /// Download and store audio for the newest [keep] messages (files only).
  static Future<void> prefetchAudio(
    ApiClient api,
    List<VoiceMessage> messages, {
    int keep = 3,
  }) =>
      AudioCache.prefetch(api, messages, keep: keep);
}
