import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../firebase_options.dart';
import 'api_client.dart';
import 'app_notify.dart';

/// Top-level FCM background handler (killed / background isolate).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (_) {}
  await AppNotify.init();
  await _presentPush(message);
}

Future<void> _presentPush(RemoteMessage message) async {
  final data = message.data;
  final type = data['type'] ?? data['kind'];
  final title = data['title'] ?? message.notification?.title ?? 'MyÜzi';
  final body = data['body'] ?? message.notification?.body ?? '';

  if (type == 'incoming_call' || data['kind'] == 'call') {
    await AppNotify.showIncomingCall(
      title: title.isNotEmpty ? title : 'Bejövő hívás',
      body: body.isNotEmpty
          ? body
          : (data['fromName'] != null
              ? '${data['fromName']} hív'
              : (data['callType'] == 'video' ? 'Videóhívás' : 'Hanghívás')),
    );
    await AppNotify.startCallRingtone();
    return;
  }

  if (title.isNotEmpty || body.isNotEmpty) {
    await AppNotify.showMessage(
      title: title.isNotEmpty ? title : 'MyÜzi',
      body: body,
    );
  }
}

class PushService {
  PushService._();

  static bool _ready = false;
  static StreamSubscription<String>? _tokenRefreshSub;
  static StreamSubscription<RemoteMessage>? _fgSub;
  static ApiClient? _api;

  static Future<void> init() async {
    if (_ready || kIsWeb) return;
    // Only Android is registered via FlutterFire for now.
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

    _ready = true;
  }

  /// Register / refresh FCM token with the Worker while logged in.
  static Future<void> syncToken(ApiClient api) async {
    if (!_ready) await init();
    if (!_ready) return;
    _api = api;

    try {
      final messaging = FirebaseMessaging.instance;
      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await api.registerPushToken(
          token: token,
          platform: 'android',
        );
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
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }
}
