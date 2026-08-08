import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../call_navigation.dart';
import '../pending_call_store.dart';
import 'ringtone.dart';

typedef NotificationTapHandler = void Function(String? payload);

/// Local notifications (foreground) + looping ringtone for calls.
class AppNotify {
  AppNotify._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static final _ringtone = AudioPlayer();
  static bool _ready = false;
  static int _nextId = 200;
  static bool _ringing = false;
  static String? _ringtonePath;
  static NotificationTapHandler? onTap;

  static Future<void> init() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: android,
        iOS: darwin,
        macOS: darwin,
      ),
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    final launch = await _plugin.getNotificationAppLaunchDetails();
    final fromNotification = launch?.didNotificationLaunchApp == true;
    if (fromNotification) {
      _applyPayload(
        launch!.notificationResponse?.payload,
        actionId: launch.notificationResponse?.actionId,
      );
    }

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    // Permission prompts during cold start can yank focus / feel like a lock-screen bounce.
    // Ask quietly later when needed (incoming call), not on every app open.
    try {
      await androidPlugin?.requestNotificationsPermission();
    } catch (_) {}

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'messages',
        'Üzenetek',
        description: 'Új hangüzenetek',
        importance: Importance.high,
        playSound: true,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'incoming_calls',
        'Bejövő hívások',
        description: 'Csengő bejövő hívásoknál',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        // Helps OEMs treat this like a phone ring for full-screen intent.
        audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
      ),
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    // Normal launcher open: clear leftover ongoing call notification.
    // Keep it if FSI / lock-arm woke the app (killed → full-screen incoming).
    var armedForIncoming = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      armedForIncoming = prefs.getBool('incoming_call_lock') ?? false;
    } catch (_) {}
    if (!fromNotification && !armedForIncoming) {
      try {
        await _plugin.cancel(id: 42);
      } catch (_) {}
    }

    _ringtonePath = await ensureRingtoneFile();
    _ready = true;
  }

  /// Request Android 14+ full-screen intent permission only when ringing in background.
  static Future<void> ensureFullScreenIntentPermission() async {
    try {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestFullScreenIntentPermission();
    } catch (_) {}
  }

  static void _onNotificationResponse(NotificationResponse response) {
    _applyPayload(response.payload, actionId: response.actionId);
    onTap?.call(response.payload);
  }

  static void _applyPayload(String? payload, {String? actionId}) {
    if (payload == null || payload.isEmpty) return;
    try {
      final data = jsonDecode(payload);
      if (data is! Map) return;
      final map = Map<String, dynamic>.from(data);
      final type = map['type']?.toString();
      final callId = map['callId']?.toString();
      final conversationId = map['conversationId']?.toString();
      final callerName = map['fromName']?.toString() ?? 'Családtag';
      final callType = map['callType']?.toString() ?? 'audio';
      final callerUserId = map['fromUserId']?.toString();

      if ((type == 'incoming_call' || type == 'call') &&
          callId != null &&
          callId.isNotEmpty) {
        if (actionId == 'accept') {
          PendingCallAction.setAccept(callId, conversation: conversationId);
          unawaitedStore(
            callId: callId,
            callerName: callerName,
            callType: callType,
            conversationId: conversationId,
            callerUserId: callerUserId,
            action: 'accept',
          );
        } else if (actionId == 'decline') {
          PendingCallAction.setDecline(callId);
          unawaitedStore(
            callId: callId,
            callerName: callerName,
            callType: callType,
            conversationId: conversationId,
            callerUserId: callerUserId,
            action: 'decline',
          );
        } else {
          PendingCallAction.setRing(
            callId,
            callerName: callerName,
            callType: callType,
            conversation: conversationId,
            callerUserId: callerUserId,
          );
          unawaitedStore(
            callId: callId,
            callerName: callerName,
            callType: callType,
            conversationId: conversationId,
            callerUserId: callerUserId,
            action: 'ring',
          );
        }
      } else if (type == 'new_message' &&
          conversationId != null &&
          conversationId.isNotEmpty) {
        PendingCallAction.setMessage(conversationId: conversationId);
      }
    } catch (_) {}
  }

  static void unawaitedStore({
    required String callId,
    required String callerName,
    required String callType,
    String? conversationId,
    String? callerUserId,
    required String action,
  }) {
    // ignore: discarded_futures
    PendingCallStore.saveRing(
      callId: callId,
      callerName: callerName,
      callType: callType,
      conversationId: conversationId,
      callerUserId: callerUserId,
      action: action,
    );
  }

  static Future<void> showMessage({
    required String title,
    required String body,
    String? conversationId,
  }) async {
    if (!_ready) await init();
    final payload = jsonEncode({
      'type': 'new_message',
      if (conversationId != null) 'conversationId': conversationId,
    });
    await _plugin.show(
      id: _nextId++,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'messages',
          'Üzenetek',
          channelDescription: 'Új hangüzenetek',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }

  static Future<void> showIncomingCall({
    required String title,
    required String body,
    required String callId,
    String? callType,
    String? conversationId,
    String? callerName,
    String? callerUserId,
  }) async {
    if (!_ready) await init();
    final payload = jsonEncode({
      'type': 'incoming_call',
      'callId': callId,
      if (callType != null) 'callType': callType,
      if (conversationId != null) 'conversationId': conversationId,
      'fromName': callerName ?? title,
      if (callerUserId != null) 'fromUserId': callerUserId,
    });
    await _plugin.show(
      id: 42,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'incoming_calls',
          'Bejövő hívások',
          channelDescription: 'Csengő bejövő hívásoknál',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.call,
          fullScreenIntent: true,
          playSound: true,
          ongoing: true,
          autoCancel: false,
          visibility: NotificationVisibility.public,
          audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
          ticker: body,
          actions: <AndroidNotificationAction>[
            const AndroidNotificationAction(
              'decline',
              'Elutasítás',
              cancelNotification: true,
              showsUserInterface: false,
            ),
            const AndroidNotificationAction(
              'accept',
              'Fogadás',
              cancelNotification: true,
              showsUserInterface: true,
            ),
          ],
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
        macOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }

  static Future<void> clearIncomingCall() async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: 42);
    } catch (_) {}
  }

  static Future<void> startCallRingtone() async {
    if (_ringing) return;
    if (!_ready) await init();
    final path = _ringtonePath ?? await ensureRingtoneFile();
    _ringing = true;
    try {
      await _ringtone.stop();
      await _ringtone.setReleaseMode(ReleaseMode.loop);
      await _ringtone.setVolume(1.0);
      await _ringtone.play(DeviceFileSource(path));
    } catch (_) {
      _ringing = false;
    }
  }

  static Future<void> stopCallRingtone() async {
    if (_ringing) {
      _ringing = false;
      try {
        await _ringtone.stop();
      } catch (_) {}
    }
    await clearIncomingCall();
  }
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  // Persist so main isolate can drain after FSI / cold start.
  final payload = response.payload;
  if (payload == null || payload.isEmpty) return;
  try {
    final data = jsonDecode(payload);
    if (data is! Map) return;
    final map = Map<String, dynamic>.from(data);
    final callId = map['callId']?.toString();
    if (callId == null || callId.isEmpty) return;
    final actionId = response.actionId;
    final action = actionId == 'accept'
        ? 'accept'
        : actionId == 'decline'
            ? 'decline'
            : 'ring';
    // SharedPreferences is sync-safe enough from background callback via Future.
    // ignore: discarded_futures
    PendingCallStore.saveRing(
      callId: callId,
      callerName: map['fromName']?.toString() ?? 'Családtag',
      callType: map['callType']?.toString() ?? 'audio',
      conversationId: map['conversationId']?.toString(),
      action: action,
    );
  } catch (_) {}
}
