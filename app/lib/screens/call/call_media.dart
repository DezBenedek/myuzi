import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show Helper;
import 'package:livekit_client/livekit_client.dart';

import '../../services/toast.dart';
import 'call_room_lifecycle.dart';

/// Mic / camera / screen-share controls for an active call.
mixin CallMediaControls on CallRoomLifecycle {
  Future<void> toggleMic() async {
    if (closing) return;
    final next = !micOn;
    try {
      await localParticipant?.setMicrophoneEnabled(next);
      if (mounted && !closing) setState(() => micOn = next);
    } catch (_) {}
  }

  Future<void> toggleCam() async {
    if (closing) return;
    final next = !camOn;
    try {
      await localParticipant?.setCameraEnabled(next);
      if (mounted && !closing) setState(() => camOn = next);
    } catch (_) {}
  }

  Future<void> switchCam() async {
    final activeRoom = room;
    if (activeRoom == null) return;
    try {
      final devices =
          await Hardware.instance.enumerateDevices(type: 'videoinput');
      if (devices.length < 2) return;
      final current = Hardware.instance.selectedVideoInput?.deviceId;
      final next = devices.firstWhere(
        (d) => d.deviceId != current,
        orElse: () => devices.first,
      );
      await activeRoom.setVideoInputDevice(next);
      if (mounted && !closing) setState(() {});
    } catch (e) {
      debugPrint('switch cam: $e');
    }
  }

  Future<bool> enableAndroidScreenShareService() async {
    try {
      const androidConfig = FlutterBackgroundAndroidConfig(
        notificationTitle: 'MyÜzi kijelzőmegosztás',
        notificationText: 'A hívás megosztja a kijelződet.',
        notificationImportance: AndroidNotificationImportance.normal,
        notificationIcon:
            AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
      );
      final hasPermissions =
          await FlutterBackground.initialize(androidConfig: androidConfig);
      if (hasPermissions && !FlutterBackground.isBackgroundExecutionEnabled) {
        await FlutterBackground.enableBackgroundExecution();
      }
      return hasPermissions;
    } catch (e) {
      debugPrint('android screen share service: $e');
      return false;
    }
  }

  Future<void> toggleScreen() async {
    if (kIsWeb || closing) return;
    final next = !screenShare;
    try {
      if (next && !kIsWeb && Platform.isAndroid) {
        final granted = await Helper.requestCapturePermission();
        if (!granted) return;
        final ok = await enableAndroidScreenShareService();
        if (!ok) {
          if (mounted) {
            showAppToast(context, 'Kijelzőmegosztáshoz engedély kell',
                error: true);
          }
          return;
        }
      }

      await localParticipant?.setScreenShareEnabled(next,
          captureScreenAudio: next);
      if (!next && !kIsWeb && Platform.isAndroid) {
        try {
          if (FlutterBackground.isBackgroundExecutionEnabled) {
            await FlutterBackground.disableBackgroundExecution();
          }
        } catch (_) {}
      }
      if (mounted && !closing) setState(() => screenShare = next);
    } catch (e) {
      debugPrint('screen share: $e');
      if (mounted) {
        showAppToast(context, 'Kijelzőmegosztás nem elérhető ezen a gépen',
            error: true);
      }
    }
  }
}
