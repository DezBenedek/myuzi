import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'call_navigation.dart';

/// Persists incoming-call ring across isolates (FCM background ↔ main).
class PendingCallStore {
  PendingCallStore._();

  static const _key = 'pending_incoming_call_v1';

  static Future<void> saveRing({
    required String callId,
    required String callerName,
    String callType = 'audio',
    String? conversationId,
    String? callerUserId,
    String? callerAvatarUrl,
    String action = 'ring',
  }) async {
    final id = callId.trim();
    if (id.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'callId': id,
        'callerName': callerName,
        'callType': callType,
        'conversationId': conversationId,
        'callerUserId': callerUserId,
        'callerAvatarUrl': callerAvatarUrl,
        'action': action,
        'at': DateTime.now().millisecondsSinceEpoch,
      }),
    );
  }

  static Future<void> clear([String? callId]) async {
    final prefs = await SharedPreferences.getInstance();
    if (callId == null) {
      await prefs.remove(_key);
      return;
    }
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      final map = jsonDecode(raw);
      if (map is Map && map['callId']?.toString() == callId) {
        await prefs.remove(_key);
      }
    } catch (_) {
      await prefs.remove(_key);
    }
  }

  static Future<bool> hydratePending() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return false;
    try {
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final callId = map['callId']?.toString() ?? '';
      if (callId.isEmpty) {
        await prefs.remove(_key);
        return false;
      }
      final at = map['at'] as int? ?? 0;
      if (at > 0 &&
          DateTime.now().millisecondsSinceEpoch - at > 90 * 1000) {
        await prefs.remove(_key);
        return false;
      }
      final action = map['action']?.toString() ?? 'ring';
      final name = map['callerName']?.toString() ?? 'Családtag';
      final callType = map['callType']?.toString() ?? 'audio';
      final conversationId = map['conversationId']?.toString();
      final callerUserId = map['callerUserId']?.toString();
      final callerAvatarUrl = map['callerAvatarUrl']?.toString();
      if (action == 'accept') {
        PendingCallAction.setAccept(callId, conversation: conversationId);
      } else if (action == 'decline') {
        PendingCallAction.setDecline(callId);
      } else {
        PendingCallAction.setRing(
          callId,
          callerName: name,
          callType: callType,
          conversation: conversationId,
          callerUserId: callerUserId,
          callerAvatarUrl: callerAvatarUrl,
        );
      }
      return true;
    } catch (_) {
      await prefs.remove(_key);
      return false;
    }
  }
}
