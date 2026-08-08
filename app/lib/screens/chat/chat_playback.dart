import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../providers/connectivity_provider.dart';
import '../../providers/providers.dart';
import '../../services/api_client.dart';
import '../../services/local_cache.dart';
import '../../services/toast.dart';
import '../../widgets/widgets.dart';
import 'chat_screen.dart';

/// Voice playback, mark-heard, and delete actions.
mixin ChatPlaybackMixin on ConsumerState<ChatScreen> {
  final player = AudioPlayer();

  String? playingId;
  double playProgress = 0;
  int playingDurationMs = 0;
  int playRequest = 0;
  StreamSubscription<Duration>? posSub;
  StreamSubscription<void>? completeSub;

  /// Provided by [ChatScreenState].
  List<VoiceMessage> get messages;
  set messages(List<VoiceMessage> value);

  void initPlayback() {
    completeSub = player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          playingId = null;
          playProgress = 0;
          playingDurationMs = 0;
        });
      }
    });
    posSub = player.onPositionChanged.listen(onPlayPosition);
  }

  void onPlayPosition(Duration pos) {
    if (!mounted || playingId == null) return;
    final total = playingDurationMs;
    if (total <= 0) return;
    final next = (pos.inMilliseconds / total).clamp(0.0, 1.0);
    // Update when progress moves enough for a smooth scrub (~half a bar).
    if ((next - playProgress).abs() < 0.008 && next < 0.995) return;
    setState(() => playProgress = next);
  }

  Future<void> playMessage(VoiceMessage msg) async {
    if (msg.isCall || msg.url == null) return;
    final request = ++playRequest;
    if (playingId == msg.id) {
      await player.stop();
      if (!mounted || request != playRequest) return;
      setState(() {
        playingId = null;
        playProgress = 0;
        playingDurationMs = 0;
      });
      return;
    }

    try {
      File file = await LocalCache.audioFile(msg.id);
      if (!await file.exists()) {
        if (!ref.read(connectivityProvider)) {
          if (!mounted) return;
          showAppToast(context, 'Nincs internet', error: true);
          return;
        }
        final bytes = await ref.read(apiProvider).downloadAudio(msg.url!);
        await LocalCache.putAudio(msg.id, bytes);
        file = await LocalCache.audioFile(msg.id);
      }
      if (!mounted || request != playRequest) return;

      final me = ref.read(authProvider).user;
      if (me == null) return;
      final meId = me.id;
      if (msg.senderId != meId && msg.unread) {
        // Clear yellow for this message and older ones.
        setState(() {
          messages = messages.map((m) {
            if (m.senderId == meId) return m;
            if (m.createdAt.compareTo(msg.createdAt) <= 0) {
              return m.copyWith(unread: false);
            }
            return m;
          }).toList();
        });
        unawaited(LocalCache.saveMessages(widget.conversationId, messages));
        unawaited(
          ref.read(apiProvider).markConversationRead(
                widget.conversationId,
                at: msg.createdAt,
              ),
        );
        unawaited(ref.read(homeNotifierProvider.notifier).refresh(silent: true));
      }

      final fallbackMs = msg.durationMs > 200 ? msg.durationMs : 1000;
      setState(() {
        playingId = msg.id;
        playProgress = 0;
        playingDurationMs = fallbackMs;
      });
      await player.stop();
      if (!mounted || request != playRequest) return;
      await player.play(DeviceFileSource(file.path));

      // Prefer real media duration once (not on every position tick).
      final mediaDur = await player.getDuration();
      if (mounted &&
          request == playRequest &&
          playingId == msg.id &&
          mediaDur != null &&
          mediaDur.inMilliseconds > 200) {
        setState(() => playingDurationMs = mediaDur.inMilliseconds);
      }
    } on ApiException catch (e) {
      if (mounted && request == playRequest) {
        showAppToast(context, e.message, error: true);
      }
    } catch (e) {
      if (mounted && request == playRequest) {
        showAppToast(context, 'Lejátszás sikertelen', error: true);
      }
      debugPrint('audio playback error: $e');
    }
  }

  Future<void> messageActions(VoiceMessage msg, {required bool mine}) async {
    final playing = playingId == msg.id;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final t = Theme.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
                  title: Text(playing ? 'Szüneteltetés' : 'Lejátszás'),
                  onTap: () {
                    Navigator.pop(ctx);
                    playMessage(msg);
                  },
                ),
                if (mine)
                  ListTile(
                    leading: Icon(
                      Icons.delete_outline,
                      color: t.colorScheme.error,
                    ),
                    title: Text(
                      'Törlés',
                      style: TextStyle(color: t.colorScheme.error),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      confirmDelete(msg);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> confirmDelete(VoiceMessage msg) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final t = Theme.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Üzenet törlése', style: t.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  'Biztosan törlöd ezt a hangüzenetet?',
                  style: t.textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
                BigButton(
                  label: 'Törlés',
                  icon: Icons.delete_outline,
                  danger: true,
                  onPressed: () => Navigator.pop(ctx, true),
                ),
                const SizedBox(height: 8),
                BigButton(
                  label: 'Mégse',
                  icon: Icons.close,
                  outlined: true,
                  onPressed: () => Navigator.pop(ctx, false),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (ok != true || !mounted) return;

    final prev = messages;
    final next = messages.where((m) => m.id != msg.id).toList();
    setState(() => messages = next);
    unawaited(LocalCache.saveMessages(widget.conversationId, next));
    if (playingId == msg.id) {
      unawaited(player.stop());
      setState(() {
        playingId = null;
        playProgress = 0;
        playingDurationMs = 0;
      });
    }

    try {
      await ref.read(apiProvider).deleteMessage(msg.id);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => messages = prev);
      unawaited(LocalCache.saveMessages(widget.conversationId, prev));
      showAppToast(context, e.message, error: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => messages = prev);
      unawaited(LocalCache.saveMessages(widget.conversationId, prev));
      showAppToast(context, 'Törlés sikertelen', error: true);
    }
  }

  void disposePlayback() {
    playRequest++;
    unawaited(posSub?.cancel());
    unawaited(completeSub?.cancel());
    player.dispose();
  }
}
