import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show Helper;
import 'package:livekit_client/livekit_client.dart';

import '../providers/providers.dart';
import '../services/toast.dart';

class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({
    super.key,
    required this.callId,
    required this.livekitUrl,
    required this.token,
    required this.callType,
    required this.title,
  });

  final String callId;
  final String livekitUrl;
  final String token;
  final String callType;
  final String title;

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  Room? _room;
  LocalParticipant? _local;
  bool _connecting = true;
  bool _micOn = true;
  bool _camOn = false;
  bool _screenShare = false;
  String? _error;
  EventsListener<RoomEvent>? _listener;

  bool get _isVideo => widget.callType == 'video';

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    try {
      final room = Room(
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          defaultAudioCaptureOptions: AudioCaptureOptions(),
          defaultCameraCaptureOptions: CameraCaptureOptions(
            maxFrameRate: 30,
          ),
        ),
      );
      _listener = room.createListener();
      _listener!
        ..on<RoomDisconnectedEvent>((_) {
          if (mounted) Navigator.of(context).maybePop();
        })
        ..on<ParticipantConnectedEvent>((_) {
          if (mounted) setState(() {});
        })
        ..on<TrackSubscribedEvent>((_) {
          if (mounted) setState(() {});
        })
        ..on<LocalTrackPublishedEvent>((_) {
          if (mounted) setState(() {});
        });

      await room.connect(widget.livekitUrl, widget.token);

      await room.localParticipant?.setMicrophoneEnabled(true);
      if (_isVideo) {
        await room.localParticipant?.setCameraEnabled(true);
        _camOn = true;
      }

      if (!mounted) return;
      setState(() {
        _room = room;
        _local = room.localParticipant;
        _connecting = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = 'Nem sikerült csatlakozni a híváshoz';
        });
      }
      debugPrint('LiveKit connect error: $e');
    }
  }

  Future<void> _hangUp() async {
    try {
      if (_screenShare && !kIsWeb && Platform.isAndroid) {
        try {
          if (FlutterBackground.isBackgroundExecutionEnabled) {
            await FlutterBackground.disableBackgroundExecution();
          }
        } catch (_) {}
      }
      await ref.read(apiProvider).endCall(widget.callId);
    } catch (_) {}
    await _room?.disconnect();
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _toggleMic() async {
    final next = !_micOn;
    await _local?.setMicrophoneEnabled(next);
    setState(() => _micOn = next);
  }

  Future<void> _toggleCam() async {
    final next = !_camOn;
    await _local?.setCameraEnabled(next);
    setState(() => _camOn = next);
  }

  Future<void> _switchCam() async {
    final room = _room;
    if (room == null) return;
    try {
      final devices = await Hardware.instance.enumerateDevices(type: 'videoinput');
      if (devices.length < 2) return;
      final current = Hardware.instance.selectedVideoInput?.deviceId;
      final next = devices.firstWhere(
        (d) => d.deviceId != current,
        orElse: () => devices.first,
      );
      await room.setVideoInputDevice(next);
      setState(() {});
    } catch (e) {
      debugPrint('switch cam: $e');
    }
  }

  Future<bool> _enableAndroidScreenShareService() async {
    try {
      var hasPermissions = await FlutterBackground.hasPermissions;
      const androidConfig = FlutterBackgroundAndroidConfig(
        notificationTitle: 'MyÜzi kijelzőmegosztás',
        notificationText: 'A hívás megosztja a kijelződet.',
        notificationImportance: AndroidNotificationImportance.normal,
        notificationIcon: AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
      );
      hasPermissions = await FlutterBackground.initialize(androidConfig: androidConfig);
      if (hasPermissions && !FlutterBackground.isBackgroundExecutionEnabled) {
        await FlutterBackground.enableBackgroundExecution();
      }
      return hasPermissions;
    } catch (e) {
      debugPrint('android screen share service: $e');
      return false;
    }
  }

  Future<void> _toggleScreen() async {
    if (kIsWeb) return;
    final next = !_screenShare;
    try {
      if (next && !kIsWeb && Platform.isAndroid) {
        final granted = await Helper.requestCapturePermission();
        if (!granted) return;
        final ok = await _enableAndroidScreenShareService();
        if (!ok) {
          if (mounted) showAppToast(context, 'Kijelzőmegosztáshoz engedély kell', error: true);
          return;
        }
      }

      await _local?.setScreenShareEnabled(next, captureScreenAudio: next);
      if (!next && !kIsWeb && Platform.isAndroid) {
        try {
          if (FlutterBackground.isBackgroundExecutionEnabled) {
            await FlutterBackground.disableBackgroundExecution();
          }
        } catch (_) {}
      }
      setState(() => _screenShare = next);
    } catch (e) {
      debugPrint('screen share: $e');
      if (mounted) {
        showAppToast(context, 'Kijelzőmegosztás nem elérhető ezen a gépen', error: true);
      }
    }
  }

  @override
  void dispose() {
    _listener?.dispose();
    _room?.disconnect();
    super.dispose();
  }

  List<VideoTrack> _remoteVideos() {
    final room = _room;
    if (room == null) return [];
    final tracks = <VideoTrack>[];
    for (final p in room.remoteParticipants.values) {
      for (final pub in p.videoTrackPublications) {
        final track = pub.track;
        if (track != null && pub.subscribed) tracks.add(track);
      }
    }
    return tracks;
  }

  VideoTrack? _localVideo() {
    final pubs = _local?.videoTrackPublications ?? [];
    for (final p in pubs) {
      if (p.track != null && !p.isScreenShare) return p.track as VideoTrack;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final remotes = _remoteVideos();
    final localVideo = _localVideo();

    return Scaffold(
      backgroundColor: const Color(0xFF0E1A14),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: t.textTheme.headlineMedium?.copyWith(color: Colors.white),
                    ),
                  ),
                  Text(
                    _isVideo ? 'Videó' : 'Hang',
                    style: t.textTheme.bodyMedium?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _connecting
                  ? const Center(child: CircularProgressIndicator(color: Colors.white))
                  : _error != null
                      ? Center(
                          child: Text(_error!, style: const TextStyle(color: Colors.white)),
                        )
                      : remotes.isNotEmpty
                          ? Stack(
                              children: [
                                Positioned.fill(
                                  child: VideoTrackRenderer(remotes.first),
                                ),
                                if (localVideo != null && _camOn)
                                  Positioned(
                                    right: 16,
                                    bottom: 16,
                                    width: 120,
                                    height: 160,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: VideoTrackRenderer(localVideo),
                                    ),
                                  ),
                              ],
                            )
                          : Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.person, size: 96, color: Colors.white70),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Várakozás a másik félre…',
                                    style: t.textTheme.titleLarge?.copyWith(color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  _RoundAction(
                    icon: _micOn ? Icons.mic : Icons.mic_off,
                    label: _micOn ? 'Mikrofon' : 'Némítva',
                    onTap: _toggleMic,
                  ),
                  if (_isVideo || _camOn)
                    _RoundAction(
                      icon: _camOn ? Icons.videocam : Icons.videocam_off,
                      label: 'Kamera',
                      onTap: _toggleCam,
                    ),
                  if (_camOn)
                    _RoundAction(
                      icon: Icons.cameraswitch,
                      label: 'Váltás',
                      onTap: _switchCam,
                    ),
                  _RoundAction(
                    icon: Icons.screen_share,
                    label: _screenShare ? 'Megosztás be' : 'Kijelző',
                    onTap: _toggleScreen,
                  ),
                  _RoundAction(
                    icon: Icons.call_end,
                    label: 'Bontás',
                    danger: true,
                    onTap: _hangUp,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: danger ? const Color(0xFFB42318) : Colors.white12,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 68,
              height: 68,
              child: Icon(icon, color: Colors.white, size: 30),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
      ],
    );
  }
}
