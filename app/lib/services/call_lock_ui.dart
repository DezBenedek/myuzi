import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Android lock-screen / turn-on for incoming calls.
/// Pref is set even from the FCM background isolate so MainActivity can
/// enable showWhenLocked *before* Flutter boots.
class CallLockUi {
  CallLockUi._();

  static const _channel = MethodChannel('hu.dezso.myuzi/call_lock');
  static const _prefKey = 'incoming_call_lock';

  /// Arm native lock-over UI (safe from background isolate — prefs only).
  static Future<void> armForIncoming() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, true);
    try {
      await _channel.invokeMethod('setIncomingCallUi', {'enabled': true});
    } catch (_) {}
  }

  static Future<void> setIncomingCallUi(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    if (enabled) {
      await prefs.setBool(_prefKey, true);
    } else {
      await prefs.remove(_prefKey);
    }
    try {
      await _channel.invokeMethod('setIncomingCallUi', {'enabled': enabled});
    } catch (_) {}
  }
}
