import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';

/// Local notifications (foreground/poll) + looping ringtone for calls.
class AppNotify {
  AppNotify._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static final _ringtone = AudioPlayer();
  static bool _ready = false;
  static int _nextId = 200;
  static bool _ringing = false;
  static String? _ringtonePath;

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

    _ringtonePath = await _ensureRingtoneFile();
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
    if (!_ready) await init();
    final path = _ringtonePath ?? await _ensureRingtoneFile();
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
    if (!_ringing) return;
    _ringing = false;
    try {
      await _ringtone.stop();
    } catch (_) {}
  }

  static Future<String> _ensureRingtoneFile() async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/myuzi_ringtone.wav');
    if (!await file.exists()) {
      await file.writeAsBytes(_buildRingtoneWav(), flush: true);
    }
    return file.path;
  }

  /// Short dual-tone loop (~1.2s) so ReleaseMode.loop sounds like a ring.
  static Uint8List _buildRingtoneWav() {
    const sampleRate = 22050;
    const durationSec = 1.2;
    final total = (sampleRate * durationSec).round();
    final data = BytesBuilder();
    // WAV header (PCM 16-bit mono)
    final dataSize = total * 2;
    final fileSize = 36 + dataSize;
    final header = ByteData(44);
    void writeString(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        header.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    writeString(0, 'RIFF');
    header.setUint32(4, fileSize, Endian.little);
    writeString(8, 'WAVE');
    writeString(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little); // PCM
    header.setUint16(22, 1, Endian.little); // mono
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * 2, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    writeString(36, 'data');
    header.setUint32(40, dataSize, Endian.little);
    data.add(header.buffer.asUint8List());

    for (var i = 0; i < total; i++) {
      final t = i / sampleRate;
      // Two beeps with a short gap — phone-like cadence.
      double amp = 0;
      if (t < 0.35 || (t > 0.45 && t < 0.8)) {
        final env = (t < 0.35)
            ? (t / 0.05).clamp(0.0, 1.0) * ((0.35 - t) / 0.05).clamp(0.0, 1.0)
            : ((t - 0.45) / 0.05).clamp(0.0, 1.0) * ((0.8 - t) / 0.05).clamp(0.0, 1.0);
        amp = 0.35 * env * (sin(2 * pi * 880 * t) + 0.5 * sin(2 * pi * 1174 * t));
      }
      final sample = (amp * 32767).round().clamp(-32768, 32767);
      data.add([sample & 0xff, (sample >> 8) & 0xff]);
    }
    return data.toBytes();
  }
}
