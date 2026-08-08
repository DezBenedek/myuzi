import 'dart:async';

import 'package:flutter/widgets.dart';

import 'app_notify.dart';
import 'call_lock_ui.dart';
import 'call_navigation.dart';
import 'pending_call_store.dart';

/// Single entry for presenting an incoming call.
/// Always queues `/incoming` (green full-screen). Push/FSI wakes when backgrounded.
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
    String? callerUserId,
    String? callerAvatarUrl,
    bool preferInApp = true,
  }) async {
    final id = callId.trim();
    if (id.isEmpty) return;

    final name = callerName.trim().isEmpty ? 'Családtag' : callerName.trim();
    final video = callType == 'video';

    // Always (re)queue ring so host opens /incoming — even if already presenting.
    await PendingCallStore.saveRing(
      callId: id,
      callerName: name,
      callType: callType,
      conversationId: conversationId,
      callerUserId: callerUserId,
      callerAvatarUrl: callerAvatarUrl,
    );
    PendingCallAction.setRing(
      id,
      callerName: name,
      callType: callType,
      conversation: conversationId,
      callerUserId: callerUserId,
      callerAvatarUrl: callerAvatarUrl,
    );

    // So MainActivity can show over lock before Flutter boots (killed app + FSI).
    await CallLockUi.armForIncoming();

    if (_activeCallId == id) {
      try {
        await AppNotify.startCallRingtone();
      } catch (_) {}
      return;
    }
    _activeCallId = id;

    try {
      await AppNotify.startCallRingtone();
    } catch (_) {}

    final inForeground = preferInApp && _isResumed();
    if (inForeground) {
      // Host drains → /incoming. Soft fallback if navigation stalls.
      _fallbackNotifyTimer?.cancel();
      _fallbackNotifyTimer = Timer(const Duration(seconds: 2), () async {
        if (_activeCallId != id) return;
        try {
          await AppNotify.showIncomingCall(
            title: name,
            body: video ? 'Bejövő videóhívás' : 'Bejövő hanghívás',
            callId: id,
            callType: callType,
            conversationId: conversationId,
            callerName: name,
            callerUserId: callerUserId,
          );
        } catch (_) {}
      });
      return;
    }

    // App backgrounded / killed: full-screen intent must open MainActivity.
    try {
      await AppNotify.ensureFullScreenIntentPermission();
      await AppNotify.showIncomingCall(
        title: name,
        body: video ? 'Bejövő videóhívás' : 'Bejövő hanghívás',
        callId: id,
        callType: callType,
        conversationId: conversationId,
        callerName: name,
        callerUserId: callerUserId,
      );
    } catch (e) {
      debugPrint('[IncomingCallPresenter] notify failed: $e');
    }
  }

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
    await CallLockUi.setIncomingCallUi(false);
    await AppNotify.stopCallRingtone();
  }

  static Future<void> dismissAll() async {
    _activeCallId = null;
    _fallbackNotifyTimer?.cancel();
    _fallbackNotifyTimer = null;
    await PendingCallStore.clear();
    await CallLockUi.setIncomingCallUi(false);
    await AppNotify.stopCallRingtone();
  }
}
