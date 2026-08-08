import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../firebase_options.dart';
import 'api_client.dart';
import 'app_notify.dart';
import 'call_navigation.dart';
import 'incoming_call_presenter.dart';

/// Top-level FCM background handler (killed / background isolate).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (_) {}
  await AppNotify.init();
  await _presentPush(message, fromBackground: true);
}

Future<void> _presentPush(
  RemoteMessage message, {
  bool fromBackground = false,
}) async {
  final data = message.data;
  final type = data['type'] ?? data['kind'];
  final title = data['title'] ?? message.notification?.title ?? 'MyÜzi';
  final body = data['body'] ?? message.notification?.body ?? '';
  final callId = data['callId']?.toString();
  final callType = data['callType']?.toString() ?? 'audio';
  final fromName = data['fromName']?.toString() ?? '';
  final conversationId = data['conversationId']?.toString();

  if (type == 'incoming_call' || data['kind'] == 'call') {
    if (callId == null || callId.isEmpty) return;
    await IncomingCallPresenter.present(
      callId: callId,
      callerName: fromName.isNotEmpty ? fromName : 'Bejövő hívás',
      callType: callType,
      conversationId: conversationId,
      preferInApp: !fromBackground,
    );
    return;
  }

  if (title.isNotEmpty || body.isNotEmpty) {
    await AppNotify.showMessage(
      title: title.isNotEmpty ? title : 'MyÜzi',
      body: body,
      conversationId: conversationId,
    );
  }
}

void _queueFromRemoteMessage(RemoteMessage message) {
  final data = message.data;
  final type = data['type'] ?? data['kind'];
  final callId = data['callId']?.toString();
  final conversationId = data['conversationId']?.toString();
  final callType = data['callType']?.toString() ?? 'audio';
  final fromName = data['fromName']?.toString() ?? 'Családtag';
  if ((type == 'incoming_call' || type == 'call') &&
      callId != null &&
      callId.isNotEmpty) {
    // Notification tap → open accept screen (not auto-join).
    PendingCallAction.setRing(
      callId,
      callerName: fromName,
      callType: callType,
      conversation: conversationId,
    );
  } else if (type == 'new_message' &&
      conversationId != null &&
      conversationId.isNotEmpty) {
    PendingCallAction.setMessage(conversationId: conversationId);
  }
}

class PushService {
  PushService._();

  static bool _ready = false;
  static StreamSubscription<String>? _tokenRefreshSub;
  static StreamSubscription<RemoteMessage>? _fgSub;
  static StreamSubscription<RemoteMessage>? _openSub;
  static ApiClient? _api;

  static Future<void> init() async {
    if (_ready || kIsWeb) return;
    if (!Platform.isAndroid) return;

    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    } catch (e) {
      debugPrint('[PushService] Firebase init failed: $e');
      return;
    }

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    _fgSub?.cancel();
    _fgSub = FirebaseMessaging.onMessage.listen((message) async {
      await AppNotify.init();
      await _presentPush(message);
    });

    _openSub?.cancel();
    _openSub = FirebaseMessaging.onMessageOpenedApp.listen(_queueFromRemoteMessage);

    final initial = await messaging.getInitialMessage();
    if (initial != null) _queueFromRemoteMessage(initial);

    _ready = true;
  }

  static Future<void> syncToken(ApiClient api) async {
    if (!_ready) await init();
    if (!_ready) return;
    _api = api;

    try {
      final messaging = FirebaseMessaging.instance;
      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await api.registerPushToken(token: token, platform: 'android');
      }

      _tokenRefreshSub?.cancel();
      _tokenRefreshSub = messaging.onTokenRefresh.listen((newToken) async {
        try {
          await (_api ?? api).registerPushToken(
            token: newToken,
            platform: 'android',
          );
        } catch (e) {
          debugPrint('[PushService] token refresh register failed: $e');
        }
      });
    } catch (e) {
      debugPrint('[PushService] syncToken failed: $e');
    }
  }

  static Future<void> clear() async {
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    _api = null;
    PendingCallAction.clear();
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }
}
