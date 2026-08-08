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
        ..on<ParticipantDisconnectedEvent>((e) {
          if (_focusId == e.participant.identity) {
            _focusId = null;
            _focusSince = null;
            _candidateId = null;
            _candidateSince = null;
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
        _focusId = room.localParticipant?.identity;
        _focusSince = DateTime.now();
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

  void _onActiveSpeakers(ActiveSpeakersChangedEvent event) {
    if (!mounted || _room == null) return;

    final speakers = event.speakers;
    if (speakers.isEmpty) {
      // Keep focus; refresh speaking rings (everyone quiet).
      setState(() {});
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
      setState(() {
        _candidateId = null;
        _candidateSince = null;
      });
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
      setState(() {}); // speaking rings only
      return;
    }

    if (_candidateId != topId) {
      _candidateId = topId;
      _candidateSince = now;
      _speakerEvalTimer?.cancel();
      _speakerEvalTimer = Timer(_promoteAfter, _tryPromoteCandidate);
    }
    setState(() {});
  }

  void _tryPromoteCandidate() {
    if (!mounted) return;
    final cand = _candidateId;
    final since = _candidateSince;
    final focusSince = _focusSince;
    if (cand == null || since == null) return;

    final now = DateTime.now();
    if (now.difference(since) < _promoteAfter) return;
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
    await _cleanupMedia();
    await _room?.disconnect();
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _endForEveryone() async {
    try {
      await ref.read(apiProvider).endCall(widget.callId);
    } catch (_) {}
    await _cleanupMedia();
    await _room?.disconnect();
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _cleanupMedia() async {
    if (_screenShare && !kIsWeb && Platform.isAndroid) {
      try {
        if (FlutterBackground.isBackgroundExecutionEnabled) {
          await FlutterBackground.disableBackgroundExecution();
        }
      } catch (_) {}
    }
  }

  Future<void> _onHangUpPressed() async {
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
      final devices =
          await Hardware.instance.enumerateDevices(type: 'videoinput');
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
        notificationIcon:
            AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
      );
      hasPermissions =
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
    if (kIsWeb) return;
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
      setState(() => _screenShare = next);
    } catch (e) {
      debugPrint('screen share: $e');
      if (mounted) {
        showAppToast(context, 'Kijelzőmegosztás nem elérhető ezen a gépen',
            error: true);
      }
    }
  }

  @override
  void dispose() {
    _speakerEvalTimer?.cancel();
    _listener?.dispose();
    unawaited(_room?.disconnect() ?? Future.value());
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

    // Always keep tile positions stable. Active speaker = border/glow only
    // (no layout jump). Phone uses 2-col grid; desktop/wide up to 3-col.
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
                    '${tiles.length} résztvevő · ${_isVideo ? 'Videó' : 'Hang'}',
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
                          : _ParticipantGrid(
                              tiles: tiles,
                              focusId: focusId,
                              showVideo: _isVideo || _camOn,
                              wide: useWideGrid,
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

class _ParticipantPane extends StatelessWidget {
  const _ParticipantPane({
    required this.tile,
    required this.focused,
    required this.showVideo,
    required this.large,
  });

  final _CallTile tile;
  final bool focused;
  final bool showVideo;
  final bool large;

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
        borderRadius: BorderRadius.circular(18),
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
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
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
