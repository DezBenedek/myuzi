import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../providers/providers.dart';
import '../../providers/realtime_provider.dart';
import '../../router.dart';
import '../../services/call_navigation.dart';
import '../../services/incoming_call_presenter.dart';
import 'call_screen.dart';

/// LiveKit room connection and leave/end lifecycle.
mixin CallRoomLifecycle on ConsumerState<CallScreen> {
  Room? room;
  LocalParticipant? localParticipant;
  bool connecting = true;
  bool micOn = true;
  bool camOn = false;
  bool screenShare = false;
  String? error;
  EventsListener<RoomEvent>? listener;
  bool closing = false;
  StreamSubscription? _rtSub;
  Timer? _aloneTimer;

  /// Shared with [SpeakerFocusMixin] — initial focus is the local participant.
  String? focusId;
  DateTime? focusSince;

  Timer? talkTimer;
  DateTime? talkStartedAt;
  Duration talkElapsed = Duration.zero;

  bool get isVideo => widget.callType == 'video';
  String? _modeOverride;
  bool get isDirect =>
      (_modeOverride ?? widget.mode) == 'direct';

  /// Implemented by [SpeakerFocusMixin].
  void onActiveSpeakers(ActiveSpeakersChangedEvent event);

  /// Implemented by [SpeakerFocusMixin].
  void clearFocusIfParticipant(String identity);

  void attachRealtimeCallEnd() {
    _rtSub?.cancel();
    _rtSub = ref.read(realtimeProvider).events.listen((event) {
      if (event['type'] != 'call_ended') return;
      if (event['callId']?.toString() != widget.callId) return;
      if (closing) return;
      unawaited(_forceCloseLocal());
    });
  }

  Future<void> connect() async {
    attachRealtimeCallEnd();
    try {
      var url = widget.livekitUrl;
      var token = widget.token;
      var callType = widget.callType;

      if (url.isEmpty || token.isEmpty) {
        final session = await ref.read(apiProvider).joinCall(widget.callId);
        url = session.livekitUrl;
        token = session.token;
        callType = session.callType;
        _modeOverride = session.isDirect ? 'direct' : 'group';
      } else if (widget.mode == 'direct') {
        _modeOverride = 'direct';
      }

      final nextRoom = Room(
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          defaultAudioCaptureOptions: AudioCaptureOptions(),
          defaultCameraCaptureOptions: CameraCaptureOptions(
            maxFrameRate: 20,
            params: VideoParametersPresets.h360_169,
          ),
        ),
      );
      room = nextRoom;
      listener = nextRoom.createListener();
      listener!
        ..on<RoomDisconnectedEvent>((_) {
          unawaited(_onRoomDisconnected());
        })
        ..on<ParticipantConnectedEvent>((e) {
          _aloneTimer?.cancel();
          maybeStartTalkTimer();
          // 1:1: spotlight the remote peer, not a duplicate of self.
          if (isDirect && mounted) {
            setState(() {
              focusId = e.participant.identity;
              focusSince = DateTime.now();
            });
          } else if (mounted) {
            setState(() {});
          }
        })
        ..on<ParticipantDisconnectedEvent>((e) {
          clearFocusIfParticipant(e.participant.identity);
          if (mounted) setState(() {});
          _onRemoteLeft();
        })
        ..on<TrackSubscribedEvent>((_) {
          if (mounted) setState(() {});
        })
        ..on<TrackUnsubscribedEvent>((_) {
          if (mounted) setState(() {});
        })
        ..on<LocalTrackPublishedEvent>((_) {
          if (mounted) setState(() {});
        })
        ..on<LocalTrackUnpublishedEvent>((_) {
          if (mounted) setState(() {});
        })
        ..on<ActiveSpeakersChangedEvent>(onActiveSpeakers);

      await nextRoom.connect(url, token);

      if (!mounted || closing) {
        await nextRoom.disconnect();
        return;
      }
      await nextRoom.localParticipant?.setMicrophoneEnabled(true);
      final videoCall = callType == 'video' || isVideo;
      if (videoCall) {
        if (!mounted || closing) {
          await nextRoom.disconnect();
          return;
        }
        await nextRoom.localParticipant?.setCameraEnabled(true);
        camOn = true;
      }

      if (!mounted) {
        try {
          await nextRoom.disconnect();
        } catch (_) {}
        return;
      }

      final remoteFocus = nextRoom.remoteParticipants.values.isNotEmpty
          ? nextRoom.remoteParticipants.values.first.identity
          : nextRoom.localParticipant?.identity;

      setState(() {
        room = nextRoom;
        localParticipant = nextRoom.localParticipant;
        connecting = false;
        focusId = isDirect ? remoteFocus : nextRoom.localParticipant?.identity;
        focusSince = DateTime.now();
      });
      unawaited(IncomingCallPresenter.dismiss(widget.callId));
      CallJoinGuard.end(widget.callId);
      maybeStartTalkTimer();
    } catch (e) {
      try {
        await listener?.dispose();
        await room?.disconnect();
      } catch (_) {}
      CallJoinGuard.end(widget.callId);
      if (mounted) {
        setState(() {
          connecting = false;
          error = 'Nem sikerült csatlakozni a híváshoz';
        });
      }
      debugPrint('LiveKit connect error: $e');
    }
  }

  Future<void> _onRoomDisconnected() async {
    if (closing) return;
    // Always tell the worker — peer must not stay in a zombie call.
    await endForEveryone();
  }

  void _onRemoteLeft() {
    final remotes = room?.remoteParticipants.length ?? 0;
    if (remotes > 0) return;
    _aloneTimer?.cancel();
    // Anyone left alone → end for everyone (worker + peers).
    unawaited(endForEveryone());
  }

  Future<void> _forceCloseLocal() async {
    if (closing) return;
    closing = true;
    _aloneTimer?.cancel();
    await IncomingCallPresenter.dismiss(widget.callId);
    await cleanupMedia();
    await disconnectRoom();
    CallJoinGuard.end(widget.callId);
    if (mounted) {
      ref.read(routerProvider).go('/');
    }
  }

  Future<void> leaveOnly() async {
    if (closing) return;
    closing = true;
    _aloneTimer?.cancel();
    await IncomingCallPresenter.dismiss(widget.callId);
    try {
      if (isDirect) {
        await ref.read(apiProvider).endCall(widget.callId);
      } else {
        await ref.read(apiProvider).leaveCall(widget.callId);
      }
    } catch (_) {}
    await cleanupMedia();
    await disconnectRoom();
    CallJoinGuard.end(widget.callId);
    if (mounted) ref.read(routerProvider).go('/');
  }

  Future<void> endForEveryone() async {
    if (closing) return;
    closing = true;
    _aloneTimer?.cancel();
    try {
      await ref.read(apiProvider).endCall(widget.callId);
    } catch (_) {}
    await IncomingCallPresenter.dismiss(widget.callId);
    await cleanupMedia();
    await disconnectRoom();
    CallJoinGuard.end(widget.callId);
    if (mounted) ref.read(routerProvider).go('/');
  }

  Future<void> cleanupMedia() async {
    try {
      await localParticipant?.setMicrophoneEnabled(false);
    } catch (_) {}
    if (camOn) {
      try {
        await localParticipant?.setCameraEnabled(false);
      } catch (_) {}
    }
    if (screenShare) {
      try {
        await localParticipant?.setScreenShareEnabled(false);
      } catch (_) {}
    }
    if (screenShare && !kIsWeb && Platform.isAndroid) {
      try {
        if (FlutterBackground.isBackgroundExecutionEnabled) {
          await FlutterBackground.disableBackgroundExecution();
        }
      } catch (_) {}
    }
  }

  Future<void> disconnectRoom() async {
    final activeListener = listener;
    listener = null;
    try {
      await activeListener?.dispose();
    } catch (_) {}
    final activeRoom = room;
    room = null;
    try {
      await activeRoom?.disconnect();
    } catch (_) {}
  }

  void maybeStartTalkTimer() {
    if (talkStartedAt != null || closing) return;
    final remotes = room?.remoteParticipants.length ?? 0;
    if (remotes <= 0) return;
    talkStartedAt = DateTime.now();
    talkElapsed = Duration.zero;
    talkTimer?.cancel();
    talkTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final started = talkStartedAt;
      if (!mounted || started == null) return;
      setState(() => talkElapsed = DateTime.now().difference(started));
    });
    if (mounted) setState(() {});
  }

  String formatTalkElapsed() {
    final total = talkElapsed.inSeconds.clamp(0, 24 * 60 * 60);
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  void disposeCallLifecycle() {
    _aloneTimer?.cancel();
    _rtSub?.cancel();
    talkTimer?.cancel();
  }
}
