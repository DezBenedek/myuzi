import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Keeps the Android process alive so the realtime WebSocket can ring
/// when the UI is backgrounded (Messenger-like while logged in).
class CallStandby {
  CallStandby._();

  static bool _inited = false;
  static bool _running = false;

  static Future<void> init() async {
    if (_inited || kIsWeb || !Platform.isAndroid) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'myuzi_standby',
        channelName: 'Hívás készenlét',
        channelDescription: 'Bejövő hívások fogadásához a háttérben',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(30000),
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
        stopWithTask: false,
      ),
    );
    _inited = true;
  }

  static Future<void> start() async {
    if (kIsWeb || !Platform.isAndroid) return;
    await init();
    if (_running) return;
    final permission = await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    try {
      final result = await FlutterForegroundTask.startService(
        serviceId: 256,
        serviceTypes: [ForegroundServiceTypes.dataSync],
        notificationTitle: 'MyÜzi',
        notificationText: 'Készen áll a bejövő hívásokra',
        callback: _standbyCallback,
      );
      _running = result is ServiceRequestSuccess;
    } catch (e) {
      debugPrint('[CallStandby] start failed: $e');
      _running = false;
    }
  }

  static Future<void> stop() async {
    if (kIsWeb || !Platform.isAndroid) return;
    if (!_running) {
      try {
        await FlutterForegroundTask.stopService();
      } catch (_) {}
      return;
    }
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
    _running = false;
  }
}

@pragma('vm:entry-point')
void _standbyCallback() {
  FlutterForegroundTask.setTaskHandler(_StandbyTaskHandler());
}

class _StandbyTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
