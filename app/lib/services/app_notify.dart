import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

/// Local notifications (foreground/poll) + system ringtone for calls.
class AppNotify {
  AppNotify._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static final _ringtone = FlutterRingtonePlayer();
  static bool _ready = false;
  static int _nextId = 200;
  static bool _ringing = false;

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
    );

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
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
      ),
    );

    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    _ready = true;
  }

  static Future<void> showMessage({
    required String title,
    required String body,
  }) async {
    if (!_ready) await init();
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
    );
  }

  static Future<void> startCallRingtone() async {
    if (_ringing) return;
    _ringing = true;
    try {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        await _ringtone.play(
          android: AndroidSounds.ringtone,
          ios: IosSounds.electronic,
          looping: true,
          volume: 1.0,
          asAlarm: true,
        );
      } else {
        await _ringtone.playNotification(looping: true, volume: 1.0);
      }
    } catch (_) {
      try {
        await _ringtone.playRingtone(looping: true, asAlarm: true);
      } catch (_) {}
    }
  }

  static Future<void> stopCallRingtone() async {
    if (!_ringing) return;
    _ringing = false;
    try {
      await _ringtone.stop();
    } catch (_) {}
  }
}
