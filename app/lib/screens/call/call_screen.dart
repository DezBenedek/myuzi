import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';
import 'call_controls.dart';
import 'call_media.dart';
import 'call_room_lifecycle.dart';
import 'call_tile.dart';
import 'participant_layout.dart';
import 'speaker_focus.dart';

/// Production call UI:
/// - Direct (1:1): remote spotlight + local PiP (never duplicate self)
/// - Group: grid / spotlight of unique identities
class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({
    super.key,
    required this.callId,
    required this.livekitUrl,
    required this.token,
    required this.callType,
    required this.title,
    this.mode = 'group',
  });

  final String callId;
  final String livekitUrl;
  final String token;
  final String callType;
  final String title;
  /// `direct` or `group` from worker.
  final String mode;

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen>
    with CallRoomLifecycle, SpeakerFocusMixin, CallMediaControls {
  static const _maxTiles = 6;

  @override
  void initState() {
    super.initState();
    connect();
  }

  Future<void> _onHangUpPressed() async {
    if (closing || !mounted) return;
    if (isDirect) {
      await endForEveryone();
      return;
    }
    final remotes = room?.remoteParticipants.length ?? 0;
    if (remotes == 0) {
      await endForEveryone();
      return;
    }

    final choice = await showCallHangUpSheet(context);
    if (choice == 'leave') await leaveOnly();
    if (choice == 'end') await endForEveryone();
  }

  @override
  void dispose() {
    final shouldNotifyServer = !closing;
    closing = true;
    disposeCallLifecycle();
    disposeSpeakerFocus();
    final activeListener = listener;
    final activeRoom = room;
    final callId = widget.callId;
    final endEveryone = isDirect || (activeRoom?.remoteParticipants.isEmpty ?? true);
    listener = null;
    room = null;
    if (shouldNotifyServer) {
      final api = ref.read(apiProvider);
      unawaited(() async {
        try {
          if (endEveryone) {
            await api.endCall(callId);
          } else {
            await api.leaveCall(callId);
          }
        } catch (_) {}
      }());
    }
    if (screenShare && !kIsWeb && Platform.isAndroid) {
      unawaited(() async {
        try {
          await FlutterBackground.disableBackgroundExecution();
        } catch (_) {}
      }());
    }
    unawaited(() async {
      try {
        await activeListener?.dispose();
      } catch (_) {}
      try {
        await activeRoom?.disconnect();
      } catch (_) {}
    }());
    super.dispose();
  }

  /// Unique identities only — skip remotes that match local (reconnect ghosts).
  List<CallTile> _tiles() {
    final activeRoom = room;
    if (activeRoom == null) return const [];

    final out = <CallTile>[];
    final seen = <String>{};
    final local = activeRoom.localParticipant;
    if (local != null) {
      seen.add(local.identity);
      out.add(CallTile.fromParticipant(local, isLocal: true));
    }

    final remotes = activeRoom.remoteParticipants.values.toList()
      ..sort((a, b) => a.identity.compareTo(b.identity));
    for (final p in remotes) {
      if (seen.contains(p.identity)) continue;
      seen.add(p.identity);
      out.add(CallTile.fromParticipant(p, isLocal: false));
    }

    // Direct: at most local + one remote.
    if (isDirect && out.length > 2) {
      final localTile = out.where((t) => t.isLocal).take(1);
      final remoteTile = out.where((t) => !t.isLocal).take(1);
      return [...localTile, ...remoteTile];
    }

    if (out.length <= _maxTiles) return out;

    final focus = focusId;
    final kept = <CallTile>[];
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
    final activeFocusId = () {
      if (isDirect || tiles.length <= 2) {
        for (final tile in tiles) {
          if (!tile.isLocal) return tile.identity;
        }
      }
      return focusId ?? (tiles.isNotEmpty ? tiles.first.identity : null);
    }();

    // Direct / 2-person: always spotlight remote large (never equal grid).
    final twoParty = isDirect || tiles.length <= 2;
    final useWideGrid = _isWide && !twoParty;

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
                    connecting
                        ? 'Csatlakozás…'
                        : talkStartedAt == null
                            ? 'Cseng… · ${isVideo ? 'Videó' : 'Hang'}'
                            : '${formatTalkElapsed()} · ${isDirect ? '1:1' : '${tiles.length} résztvevő'} · ${isVideo ? 'Videó' : 'Hang'}',
                    style: t.textTheme.bodyMedium
                        ?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
            Expanded(
              child: connecting
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  : error != null
                      ? Center(
                          child: Text(
                            error!,
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
                              ? ParticipantGrid(
                                  tiles: tiles,
                                  focusId: activeFocusId,
                                  showVideo: isVideo || camOn,
                                  wide: true,
                                )
                              : MobileSpotlight(
                                  tiles: tiles,
                                  focusId: activeFocusId,
                                  showVideo: isVideo || camOn,
                                ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  CallRoundAction(
                    icon: micOn ? Icons.mic : Icons.mic_off,
                    label: micOn ? 'Mikrofon' : 'Némítva',
                    onTap: toggleMic,
                  ),
                  if (isVideo || camOn)
                    CallRoundAction(
                      icon: camOn ? Icons.videocam : Icons.videocam_off,
                      label: 'Kamera',
                      onTap: toggleCam,
                    ),
                  if (camOn)
                    CallRoundAction(
                      icon: Icons.cameraswitch,
                      label: 'Váltás',
                      onTap: switchCam,
                    ),
                  CallRoundAction(
                    icon: Icons.screen_share,
                    label: screenShare ? 'Megosztás be' : 'Kijelző',
                    onTap: toggleScreen,
                  ),
                  CallRoundAction(
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
