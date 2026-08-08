import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../models/models.dart';
import '../../providers/connectivity_provider.dart';
import '../../providers/providers.dart';
import '../../services/api_client.dart';
import '../../services/local_cache.dart';
import '../../services/toast.dart';
import '../../widgets/voice_wave_bubble.dart';
import 'chat_screen.dart';

/// Mic recording, amplitude collection, and voice upload.
mixin ChatRecordingMixin on ConsumerState<ChatScreen> {
  final recorder = AudioRecorder();
  final waveCollector = WaveformCollector();

  bool recording = false;
  DateTime? recordStarted;
  Duration recordElapsed = Duration.zero;
  bool sending = false;
  bool recordStarting = false;
  String? recordPath;
  Timer? recordTick;
  Timer? maxRecordTimer;
  StreamSubscription<Amplitude>? ampSub;

  /// Provided by [ChatScreenState].
  List<VoiceMessage> get messages;
  set messages(List<VoiceMessage> value);

  int get maxRecordMs;
  int get maxRecordBytes;

  Future<void> deleteRecordingFile(String? path);
  void scrollToBottom({bool animate = false});
  Future<void> loadMessages({bool silent = false});

  Future<void> startRecording() async {
    if (recordStarting || recording || sending) return;
    recordStarting = true;
    if (!ref.read(connectivityProvider)) {
      showAppToast(context, 'Nincs internet', error: true);
      recordStarting = false;
      return;
    }
    try {
      final ok = await recorder.hasPermission();
      if (!ok) {
        if (mounted) {
          showAppToast(context, 'Mikrofon engedély kell', error: true);
        }
        return;
      }
      final dir = await getTemporaryDirectory();
      final file =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      recordPath = file;
      waveCollector.reset();
      await ampSub?.cancel();
      await recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: file,
      );
      ampSub = recorder
          .onAmplitudeChanged(const Duration(milliseconds: 80))
          .listen((amp) {
        waveCollector.addDb(amp.current);
        if (mounted) setState(() {});
      });
      recordTick?.cancel();
      maxRecordTimer?.cancel();
      if (!mounted) return;
      setState(() {
        recording = true;
        recordStarted = DateTime.now();
        recordElapsed = Duration.zero;
      });
      recordTick = Timer.periodic(const Duration(seconds: 1), (_) {
        final started = recordStarted;
        if (started == null || !mounted) return;
        setState(() => recordElapsed = DateTime.now().difference(started));
      });
      maxRecordTimer = Timer(Duration(milliseconds: maxRecordMs), () {
        if (recording) unawaited(stopAndSend());
      });
    } catch (e) {
      await deleteRecordingFile(recordPath);
      recordPath = null;
      if (mounted) {
        showAppToast(context, 'Felvétel nem indítható', error: true);
      }
      debugPrint('record start error: $e');
    } finally {
      recordStarting = false;
    }
  }

  Future<void> stopAndSend() async {
    if (!recording || sending || recordStarting) return;
    recordTick?.cancel();
    maxRecordTimer?.cancel();
    await ampSub?.cancel();
    ampSub = null;
    if (!mounted) return;
    final waveBars = waveCollector.toBars();
    String? path;
    final started = recordStarted;
    final maxMs = maxRecordMs;
    setState(() {
      recording = false;
      recordStarted = null;
      sending = true;
    });
    try {
      path = await recorder.stop();
      if (path == null || started == null) return;

      final file = File(path);
      if (!await file.exists()) return;
      final maxUploadBytes = maxRecordBytes;
      final fileSize = await file.length();
      if (fileSize == 0 || fileSize > maxUploadBytes) {
        if (mounted) {
          showAppToast(context, 'A hangfájl túl nagy vagy üres', error: true);
        }
        return;
      }

      var duration = DateTime.now().difference(started).inMilliseconds;
      if (duration > maxMs) duration = maxMs;
      final bytes = await file.readAsBytes();
      final msg = await ref.read(apiProvider).uploadVoice(
            conversationId: widget.conversationId,
            bytes: bytes,
            contentType: 'audio/m4a',
            durationMs: duration,
            waveBars: waveBars,
          );
      final me = ref.read(authProvider).user!;
      final local = VoiceMessage(
        id: msg.id,
        conversationId: widget.conversationId,
        senderId: me.id,
        senderName: me.name,
        durationMs: duration,
        createdAt: DateTime.now().toIso8601String(),
        url: msg.url,
        waveBars: msg.waveBars.isNotEmpty ? msg.waveBars : waveBars,
      );
      await LocalCache.putAudio(msg.id, bytes);
      if (mounted) {
        setState(() => messages = [...messages, local]);
        await LocalCache.saveMessages(widget.conversationId, messages);
        scrollToBottom(animate: true);
      }
      unawaited(loadMessages(silent: true));
    } on ApiException catch (e) {
      if (mounted) showAppToast(context, e.message, error: true);
    } catch (e) {
      if (mounted) {
        showAppToast(context, 'Hangüzenet küldése sikertelen', error: true);
      }
      debugPrint('record send error: $e');
    } finally {
      await deleteRecordingFile(path ?? recordPath);
      recordPath = null;
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> toggleRecord() async {
    if (recording) {
      await stopAndSend();
      return;
    }
    await startRecording();
  }

  void disposeRecording() {
    recordTick?.cancel();
    maxRecordTimer?.cancel();
    unawaited(ampSub?.cancel());
    final path = recordPath;
    if (recording) {
      unawaited(() async {
        try {
          final stopped = await recorder.stop();
          await deleteRecordingFile(stopped ?? path);
        } catch (_) {
          await deleteRecordingFile(path);
        }
      }());
    } else if (path != null) {
      unawaited(deleteRecordingFile(path));
    }
    recorder.dispose();
  }
}
