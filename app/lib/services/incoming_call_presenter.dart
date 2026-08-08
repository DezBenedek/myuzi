import 'dart:async';

import 'package:flutter/widgets.dart';

import 'app_notify.dart';
import 'call_navigation.dart';
import 'pending_call_store.dart';

/// Single entry for presenting an incoming call (prevents double UI).
/// Prefer in-app full-screen `/incoming`. Push notification only as wake/fallback.
class IncomingCallPresenter {
  IncomingCallPresenter._();

  static String? _activeCallId;
  static Timer? _fallbackNotifyTimer;

  static String? get activeCallId => _activeCallId;

  static bool isPresenting(String callId) => _activeCallId == callId;

  static bool _isResumed() =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  static Future<void> present({
    required String callId,
    required String callerName,
    String callType = 'audio',
    String? conversationId,
    bool preferInApp = true,
  }) async {
    final id = callId.trim();
    if (id.isEmpty) return;
    if (_activeCallId == id) {
      // Re-queue ring so host can open /incoming after FSI wake.
      PendingCallAction.setRing(
        id,
        callerName: callerName.trim().isEmpty ? 'Családtag' : callerName.trim(),
        callType: callType,
        conversation: conversationId,
      );
      return;
    }
    _activeCallId = id;

    final name = callerName.trim().isEmpty ? 'Családtag' : callerName.trim();
    final video = callType == 'video';

    await PendingCallStore.saveRing(
      callId: id,
      callerName: name,
      callType: callType,
      conversationId: conversationId,
    );

    PendingCallAction.setRing(
      id,
      callerName: name,
      callType: callType,
      conversation: conversationId,
    );

    try {
      await AppNotify.startCallRingtone();
    } catch (_) {}

    final inForeground = preferInApp && _isResumed();
    if (inForeground) {
      // Full-screen /incoming via host — no heads-up push.
      _fallbackNotifyTimer?.cancel();
      _fallbackNotifyTimer = Timer(const Duration(seconds: 2), () async {
        if (_activeCallId != id) return;
        // If UI still not open (navigation failed), show push as fallback.
        try {
          await AppNotify.showIncomingCall(
            title: 'Bejövő hívás',
            body: '$name · ${video ? 'Videóhívás' : 'Hanghívás'}',
            callId: id,
            callType: callType,
            conversationId: conversationId,
            callerName: name,
          );
        } catch (_) {}
      });
      return;
    }

    // Background / locked: FSI notification wakes the app → host opens /incoming
    // and clears this notification so no duplicate dropdown remains.
    try {
      await AppNotify.ensureFullScreenIntentPermission();
      await AppNotify.showIncomingCall(
        title: 'Bejövő hívás',
        body: '$name · ${video ? 'Videóhívás' : 'Hanghívás'}',
        callId: id,
        callType: callType,
        conversationId: conversationId,
        callerName: name,
      );
    } catch (e) {
      debugPrint('[IncomingCallPresenter] notify failed: $e');
    }
  }

  /// Called when `/incoming` is actually on screen — cancel push UI.
  static Future<void> onFullScreenShown(String callId) async {
    if (_activeCallId != callId && _activeCallId != null) return;
    _fallbackNotifyTimer?.cancel();
    _fallbackNotifyTimer = null;
    await AppNotify.clearIncomingCall();
  }

  static Future<void> dismiss(String callId) async {
    if (_activeCallId == callId) _activeCallId = null;
    _fallbackNotifyTimer?.cancel();
    _fallbackNotifyTimer = null;
    await PendingCallStore.clear(callId);
    await AppNotify.stopCallRingtone();
  }

  static Future<void> dismissAll() async {
    _activeCallId = null;
    _fallbackNotifyTimer?.cancel();
    _fallbackNotifyTimer = null;
    await PendingCallStore.clear();
    await AppNotify.stopCallRingtone();
  }
}
