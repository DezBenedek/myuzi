import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show Helper;
import 'package:livekit_client/livekit_client.dart';

import '../providers/providers.dart';
import '../services/toast.dart';
import '../widgets/widgets.dart';

/// Production call UI:
/// - Desktop / wide: grid of all participants (max 6), stable order
/// - Phone: large spotlight + strip
/// - Active speaker highlight with hysteresis (no flicker / jump)
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
  static const _maxTiles = 6;

  /// Must keep speaking this long before becoming the focus speaker.
  static const _promoteAfter = Duration(milliseconds: 1400);

  /// Current focus stays at least this long before we allow a switch.
  static const _holdMin = Duration(milliseconds: 2800);

  /// New speaker must beat current by this audio-level margin.
  static const _levelMargin = 0.12;

  Room? _room;
  LocalParticipant? _local;
  bool _connecting = true;
  bool _micOn = true;
  bool _camOn = false;
  bool _screenShare = false;
  String? _error;
  EventsListener<RoomEvent>? _listener;

  /// Stable focus identity (does not jump on brief noise).
  String? _focusId;
  DateTime? _focusSince;
  String? _candidateId;
  DateTime? _candidateSince;
  Timer? _speakerEvalTimer;
  Timer? _speakerUiTimer;
  Timer? _talkTimer;
  DateTime? _talkStartedAt;
  Duration _talkElapsed = Duration.zero;
  bool _closing = false;

  bool get _isVideo => widget.callType == 'video';

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    try {
      var url = widget.livekitUrl;
      var token = widget.token;
      var callType = widget.callType;

      // Builder/router extras can be lost — re-join to recover LiveKit creds.
      if (url.isEmpty || token.isEmpty) {
        final session = await ref.read(apiProvider).joinCall(widget.callId);
        url = session.livekitUrl;
        token = session.token;
        callType = session.callType;
        if (mounted) {
          setState(() {
            // callType used via local; widget fields are final.
          });
        }
      }

      final room = Room(
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
      _room = room;
      _listener = room.createListener();
      _listener!
        ..on<RoomDisconnectedEvent>((_) {
          if (mounted && !_closing) {
            _closing = true;
            Navigator.of(context).maybePop();
          }
        })
        ..on<ParticipantConnectedEvent>((_) {
          _maybeStartTalkTimer();
          if (mounted) setState(() {});
        })
        ..on<ParticipantDisconnectedEvent>((e) {
          if (_focusId == e.participant.identity) {
            _focusId = null;
            _focusSince = null;
            _candidateId = null;
            _candidateSince = null;
            _speakerEvalTimer?.cancel();
          }
          if (mounted) setState(() {});
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
        ..on<ActiveSpeakersChangedEvent>(_onActiveSpeakers);

      await room.connect(url, token);

      if (!mounted || _closing) {
        await room.disconnect();
        return;
      }
      await room.localParticipant?.setMicrophoneEnabled(true);
      final isVideo = callType == 'video' || _isVideo;
      if (isVideo) {
        if (!mounted || _closing) {
          await room.disconnect();
          return;
        }
        await room.localParticipant?.setCameraEnabled(true);
        _camOn = true;
      }

      if (!mounted) {
        try {
          await room.disconnect();
        } catch (_) {}
        return;
      }
      setState(() {
        _room = room;
        _local = room.localParticipant;
        _connecting = false;
        _focusId = room.localParticipant?.identity;
        _focusSince = DateTime.now();
      });
      _maybeStartTalkTimer();
    } catch (e) {
      try {
        await _listener?.dispose();
        await _room?.disconnect();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = 'Nem sikerült csatlakozni a híváshoz';
        });
      }
      debugPrint('LiveKit connect error: $e');
    }
  }

  void _onActiveSpeakers(ActiveSpeakersChangedEvent event) {
    if (!mounted || _room == null) return;

    final speakers = event.speakers;
    if (speakers.isEmpty) {
      // Keep focus; clear a candidate that stopped speaking.
      _candidateId = null;
      _candidateSince = null;
      _speakerEvalTimer?.cancel();
      _scheduleSpeakerUiRefresh();
      return;
    }

    // Loudest first (SDK already orders this way).
    final top = speakers.first;
    final topId = top.identity;
    final now = DateTime.now();

    if (_focusId == null) {
      setState(() {
        _focusId = topId;
        _focusSince = now;
        _candidateId = null;
        _candidateSince = null;
      });
      return;
    }

    if (topId == _focusId) {
      _candidateId = null;
      _candidateSince = null;
      _speakerEvalTimer?.cancel();
      _scheduleSpeakerUiRefresh();
      return;
    }

    Participant? focusP;
    for (final s in speakers) {
      if (s.identity == _focusId) {
        focusP = s;
        break;
      }
    }
    final focusLevel = focusP?.audioLevel ?? 0.0;
    final topLevel = top.audioLevel;

    final focusSilent = focusP == null || !focusP.isSpeaking;
    if (!focusSilent && topLevel < focusLevel + _levelMargin) {
      _scheduleSpeakerUiRefresh();
      return;
    }

    if (_candidateId != topId) {
      _candidateId = topId;
      _candidateSince = now;
      _speakerEvalTimer?.cancel();
      _speakerEvalTimer = Timer(_promoteAfter, _tryPromoteCandidate);
    }
    _scheduleSpeakerUiRefresh();
  }

  void _scheduleSpeakerUiRefresh() {
    if (_speakerUiTimer?.isActive ?? false) return;
    _speakerUiTimer = Timer(const Duration(milliseconds: 100), () {
      if (mounted) setState(() {});
    });
  }

  void _tryPromoteCandidate() {
    if (!mounted) return;
    final cand = _candidateId;
    final since = _candidateSince;
    final focusSince = _focusSince;
    if (cand == null || since == null) return;

    final now = DateTime.now();
    if (now.difference(since) < _promoteAfter) return;
    final candidate = _room?.getParticipantByIdentity(cand);
    if (candidate == null || !candidate.isSpeaking) {
      _candidateId = null;
      _candidateSince = null;
      return;
    }
    if (focusSince != null && now.difference(focusSince) < _holdMin) {
      final wait = _holdMin - now.difference(focusSince);
      _speakerEvalTimer?.cancel();
      _speakerEvalTimer = Timer(wait, _tryPromoteCandidate);
      return;
    }

    if (_focusId == cand) return;
    setState(() {
      _focusId = cand;
      _focusSince = DateTime.now();
      _candidateId = null;
      _candidateSince = null;
    });
  }

  Future<void> _leaveOnly() async {
    if (_closing) return;
    _closing = true;
    await _cleanupMedia();
    await _disconnectRoom();
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _endForEveryone() async {
    if (_closing) return;
    _closing = true;
    try {
      await ref.read(apiProvider).endCall(widget.callId);
    } catch (_) {}
    await _cleanupMedia();
    await _disconnectRoom();
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _cleanupMedia() async {
    try {
      await _local?.setMicrophoneEnabled(false);
    } catch (_) {}
    if (_camOn) {
      try {
        await _local?.setCameraEnabled(false);
      } catch (_) {}
    }
    if (_screenShare) {
      try {
        await _local?.setScreenShareEnabled(false);
      } catch (_) {}
    }
    if (_screenShare && !kIsWeb && Platform.isAndroid) {
      try {
        if (FlutterBackground.isBackgroundExecutionEnabled) {
          await FlutterBackground.disableBackgroundExecution();
        }
      } catch (_) {}
    }
  }

  Future<void> _disconnectRoom() async {
    final listener = _listener;
    _listener = null;
    try {
      await listener?.dispose();
    } catch (_) {}
    final room = _room;
    _room = null;
    try {
      await room?.disconnect();
    } catch (_) {}
  }

  Future<void> _onHangUpPressed() async {
    if (_closing || !mounted) return;
    final remotes = _room?.remoteParticipants.length ?? 0;
    if (remotes == 0) {
      await _endForEveryone();
      return;
    }

    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF1A2A22),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Kilépés a hívásból',
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  'A többiek folytathatják, vagy mindenki számára bontod.',
                  style: Theme.of(ctx)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                BigButton(
                  label: 'Csak én lépek ki',
                  icon: Icons.logout,
                  onPressed: () => Navigator.pop(ctx, 'leave'),
                ),
                const SizedBox(height: 8),
                BigButton(
                  label: 'Mindenki számára bontás',
                  icon: Icons.call_end,
                  danger: true,
                  onPressed: () => Navigator.pop(ctx, 'end'),
                ),
                const SizedBox(height: 8),
                BigButton(
                  label: 'Mégse',
                  outlined: true,
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (choice == 'leave') await _leaveOnly();
    if (choice == 'end') await _endForEveryone();
  }

  Future<void> _toggleMic() async {
    if (_closing) return;
    final next = !_micOn;
    try {
      await _local?.setMicrophoneEnabled(next);
      if (mounted && !_closing) setState(() => _micOn = next);
    } catch (_) {}
  }

  Future<void> _toggleCam() async {
    if (_closing) return;
    final next = !_camOn;
    try {
      await _local?.setCameraEnabled(next);
      if (mounted && !_closing) setState(() => _camOn = next);
    } catch (_) {}
  }

  Future<void> _switchCam() async {
    final room = _room;
    if (room == null) return;
    try {
      final devices =
          await Hardware.instance.enumerateDevices(type: 'videoinput');
      if (devices.length < 2) return;
      final current = Hardware.instance.selectedVideoInput?.deviceId;
      final next = devices.firstWhere(
        (d) => d.deviceId != current,
        orElse: () => devices.first,
      );
      await room.setVideoInputDevice(next);
      if (mounted && !_closing) setState(() {});
    } catch (e) {
      debugPrint('switch cam: $e');
    }
  }

  Future<bool> _enableAndroidScreenShareService() async {
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

  Future<void> _toggleScreen() async {
    if (kIsWeb || _closing) return;
    final next = !_screenShare;
    try {
      if (next && !kIsWeb && Platform.isAndroid) {
        final granted = await Helper.requestCapturePermission();
        if (!granted) return;
        final ok = await _enableAndroidScreenShareService();
        if (!ok) {
          if (mounted) {
            showAppToast(context, 'Kijelzőmegosztáshoz engedély kell',
                error: true);
          }
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
      if (mounted && !_closing) setState(() => _screenShare = next);
    } catch (e) {
      debugPrint('screen share: $e');
      if (mounted) {
        showAppToast(context, 'Kijelzőmegosztás nem elérhető ezen a gépen',
            error: true);
      }
    }
  }

  void _maybeStartTalkTimer() {
    if (_talkStartedAt != null || _closing) return;
    final remotes = _room?.remoteParticipants.length ?? 0;
    if (remotes <= 0) return;
    _talkStartedAt = DateTime.now();
    _talkElapsed = Duration.zero;
    _talkTimer?.cancel();
    _talkTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final started = _talkStartedAt;
      if (!mounted || started == null) return;
      setState(() => _talkElapsed = DateTime.now().difference(started));
    });
    if (mounted) setState(() {});
  }

  String _formatTalkElapsed() {
    final total = _talkElapsed.inSeconds.clamp(0, 24 * 60 * 60);
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _closing = true;
    _speakerEvalTimer?.cancel();
    _speakerUiTimer?.cancel();
    _talkTimer?.cancel();
    final listener = _listener;
    final room = _room;
    _listener = null;
    _room = null;
    if (_screenShare && !kIsWeb && Platform.isAndroid) {
      unawaited(() async {
        try {
          await FlutterBackground.disableBackgroundExecution();
        } catch (_) {}
      }());
    }
    unawaited(() async {
      try {
        await listener?.dispose();
      } catch (_) {}
      try {
        await room?.disconnect();
      } catch (_) {}
    }());
    super.dispose();
  }

  /// Stable ordered tiles (local first, then remotes by identity). Max 6.
  List<_CallTile> _tiles() {
    final room = _room;
    if (room == null) return const [];

    final out = <_CallTile>[];
    final local = room.localParticipant;
    if (local != null) {
      out.add(_CallTile.fromParticipant(local, isLocal: true));
    }

    final remotes = room.remoteParticipants.values.toList()
      ..sort((a, b) => a.identity.compareTo(b.identity));
    for (final p in remotes) {
      out.add(_CallTile.fromParticipant(p, isLocal: false));
    }

    if (out.length <= _maxTiles) return out;

    final focus = _focusId;
    final kept = <_CallTile>[];
    for (final t in out) {
      if (t.isLocal || t.identity == focus) kept.add(t);
    }
    for (final t in out) {
      if (kept.length >= _maxTiles) break;
      if (!kept.any((k) => k.identity == t.identity)) kept.add(t);
    }
    kept.sort((a, b) {
      if (a.isLocal != b.isLocal) return a.isLocal ? -1 : 1;
      return a.identity.compareTo(b.identity);
    });
    return kept.take(_maxTiles).toList();
  }

  bool get _isWide {
    final w = MediaQuery.sizeOf(context).width;
    return w >= 700 ||
        (!kIsWeb &&
            (Platform.isMacOS || Platform.isWindows || Platform.isLinux));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tiles = _tiles();
    final focusId =
        _focusId ?? (tiles.isNotEmpty ? tiles.first.identity : null);

    // Always keep desktop tile positions stable. On phones the focused
    // speaker gets the spotlight while the participant strip stays ordered.
    final useWideGrid = _isWide;

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
                      style: t.textTheme.headlineMedium
                          ?.copyWith(color: Colors.white),
                    ),
                  ),
                  Text(
                    _connecting
                        ? 'Csatlakozás…'
                        : _talkStartedAt == null
                            ? 'Cseng… · ${_isVideo ? 'Videó' : 'Hang'}'
                            : '${_formatTalkElapsed()} · ${tiles.length} résztvevő · ${_isVideo ? 'Videó' : 'Hang'}',
                    style: t.textTheme.bodyMedium
                        ?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _connecting
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  : _error != null
                      ? Center(
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.white),
                          ),
                        )
                      : tiles.isEmpty
                          ? Center(
                              child: Text(
                                'Várakozás a többiekre…',
                                style: t.textTheme.titleLarge
                                    ?.copyWith(color: Colors.white),
                              ),
                            )
                          : useWideGrid
                              ? _ParticipantGrid(
                                  tiles: tiles,
                                  focusId: focusId,
                                  showVideo: _isVideo || _camOn,
                                  wide: true,
                                )
                              : _MobileSpotlight(
                                  tiles: tiles,
                                  focusId: focusId,
                                  showVideo: _isVideo || _camOn,
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
                    onTap: _onHangUpPressed,
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

class _CallTile {
  _CallTile({
    required this.identity,
    required this.name,
    required this.isLocal,
    required this.isSpeaking,
    required this.audioLevel,
    this.camera,
  });

  final String identity;
  final String name;
  final bool isLocal;
  final bool isSpeaking;
  final double audioLevel;
  final VideoTrack? camera;

  factory _CallTile.fromParticipant(Participant p, {required bool isLocal}) {
    VideoTrack? cam;
    for (final pub in p.videoTrackPublications) {
      if (pub.isScreenShare) continue;
      final track = pub.track;
      if (track is VideoTrack && (isLocal || pub.subscribed)) {
        cam = track;
        break;
      }
    }
    return _CallTile(
      identity: p.identity,
      name: p.name.isNotEmpty ? p.name : p.identity,
      isLocal: isLocal,
      isSpeaking: p.isSpeaking,
      audioLevel: p.audioLevel,
      camera: cam,
    );
  }
}

class _ParticipantGrid extends StatelessWidget {
  const _ParticipantGrid({
    required this.tiles,
    required this.focusId,
    required this.showVideo,
    required this.wide,
  });

  final List<_CallTile> tiles;
  final String? focusId;
  final bool showVideo;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final n = tiles.length;
    // Phone: max 2 columns (stable). Desktop/wide: up to 3 for 5–6 people.
    final cols = n <= 1
        ? 1
        : wide
            ? (n <= 4 ? 2 : 3)
            : 2;
    final rows = (n + cols - 1) ~/ cols;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cellW = (constraints.maxWidth - 10 * (cols - 1)) / cols;
          final cellH =
              (constraints.maxHeight - 10 * (rows - 1)) / math.max(1, rows);
          final aspect = cellW / math.max(120.0, cellH);

          return GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: aspect.clamp(0.55, 1.6),
            ),
            itemCount: n,
            itemBuilder: (_, i) {
              final tile = tiles[i];
              return _ParticipantPane(
                tile: tile,
                focused: tile.identity == focusId,
                showVideo: showVideo,
                large: n == 1,
              );
            },
          );
        },
      ),
    );
  }
}

class _MobileSpotlight extends StatelessWidget {
  const _MobileSpotlight({
    required this.tiles,
    required this.focusId,
    required this.showVideo,
  });

  final List<_CallTile> tiles;
  final String? focusId;
  final bool showVideo;

  @override
  Widget build(BuildContext context) {
    var focus = tiles.first;
    for (final tile in tiles) {
      if (tile.identity == focusId) {
        focus = tile;
        break;
      }
    }
    // The strip keeps the stable identity order; only the large view changes.
    final strip = tiles.where((tile) => tile.identity != focus.identity).toList();

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _ParticipantPane(
              tile: focus,
              focused: true,
              showVideo: showVideo,
              large: true,
            ),
          ),
        ),
        if (strip.isNotEmpty)
          SizedBox(
            height: 112,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              scrollDirection: Axis.horizontal,
              itemCount: strip.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, index) {
                final tile = strip[index];
                return SizedBox(
                  width: 96,
                  child: _ParticipantPane(
                    tile: tile,
                    focused: false,
                    showVideo: showVideo,
                    large: false,
                    compact: true,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _ParticipantPane extends StatelessWidget {
  const _ParticipantPane({
    required this.tile,
    required this.focused,
    required this.showVideo,
    required this.large,
    this.compact = false,
  });

  final _CallTile tile;
  final bool focused;
  final bool showVideo;
  final bool large;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final borderColor = focused
        ? const Color(0xFF3DDC97)
        : tile.isSpeaking
            ? const Color(0xFF6BCB9A)
            : Colors.white24;
    final borderWidth = focused ? 3.0 : (tile.isSpeaking ? 2.0 : 1.0);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: const Color(0xFF15241C),
        borderRadius: BorderRadius.circular(compact ? 14 : 18),
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: const Color(0xFF3DDC97).withValues(alpha: 0.28),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (showVideo && tile.camera != null)
            VideoTrackRenderer(
              tile.camera!,
              key: ValueKey(tile.identity),
              fit: VideoViewFit.cover,
            )
          else
            ColoredBox(
              color: const Color(0xFF1A2E24),
              child: Center(
                child: Text(
                  tile.name.isNotEmpty
                      ? tile.name.characters.first.toUpperCase()
                      : '?',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: large ? 64 : 42,
                  ),
                ),
              ),
            ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Row(
              children: [
                if (tile.isSpeaking)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.graphic_eq,
                        color: Color(0xFF3DDC97), size: 16),
                  ),
                Expanded(
                  child: Text(
                    tile.isLocal ? '${tile.name} (te)' : tile.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: compact ? 11 : 13,
                      shadows: [
                        Shadow(blurRadius: 6, color: Colors.black54),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
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
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
