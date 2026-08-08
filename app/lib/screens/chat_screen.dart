import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../models/models.dart';
import '../providers/connectivity_provider.dart';
import '../providers/providers.dart';
import '../services/api_client.dart';
import '../services/local_cache.dart';
import '../services/toast.dart';
import '../widgets/user_avatar.dart';
import '../widgets/voice_wave_bubble.dart';
import '../widgets/widgets.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  final _scroll = ScrollController();
  List<VoiceMessage> _messages = [];
  List<MemberRead> _memberReads = [];
  bool _loading = true;
  bool _recording = false;
  DateTime? _recordStarted;
  Duration _recordElapsed = Duration.zero;
  String? _playingId;
  double _playProgress = 0;
  int _playingDurationMs = 0;
  String _title = 'Beszélgetés';
  Timer? _refresh;
  Timer? _recordTick;
  Timer? _maxRecordTimer;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<void>? _completeSub;
  StreamSubscription<Amplitude>? _ampSub;
  final _waveCollector = WaveformCollector();
  bool _sending = false;
  bool _recordStarting = false;
  String? _recordPath;
  bool _loadInFlight = false;
  int _playRequest = 0;
  bool _callStarting = false;

  int get _maxRecordMs {
    final fam = ref.read(familyProvider).asData?.value.family;
    return fam?.voiceMaxMs ?? 2 * 60 * 1000;
  }

  int get _maxRecordBytes {
    final plan = ref.read(familyProvider).asData?.value.family?.plan;
    if (plan == 'family_plus') return 20 * 1024 * 1024;
    if (plan == 'family') return 12 * 1024 * 1024;
    return 8 * 1024 * 1024;
  }

  @override
  void initState() {
    super.initState();
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playingId = null;
          _playProgress = 0;
          _playingDurationMs = 0;
        });
      }
    });
    _posSub = _player.onPositionChanged.listen(_onPlayPosition);
    _boot();
    _refresh = Timer.periodic(const Duration(seconds: 10), (_) => _load(silent: true));
  }

  void _onPlayPosition(Duration pos) {
    if (!mounted || _playingId == null) return;
    final total = _playingDurationMs;
    if (total <= 0) return;
    final next = (pos.inMilliseconds / total).clamp(0.0, 1.0);
    // Update when progress moves enough for a smooth scrub (~half a bar).
    if ((next - _playProgress).abs() < 0.008 && next < 0.995) return;
    setState(() => _playProgress = next);
  }

  Future<void> _deleteRecordingFile(String? path) async {
    if (path == null) return;
    try {
      await File(path).delete();
    } catch (_) {}
  }

  @override
  void dispose() {
    _playRequest++;
    _refresh?.cancel();
    _recordTick?.cancel();
    _maxRecordTimer?.cancel();
    _ampSub?.cancel();
    _posSub?.cancel();
    _completeSub?.cancel();
    final recordingPath = _recordPath;
    if (_recording) {
      unawaited(() async {
        try {
          final path = await _recorder.stop();
          await _deleteRecordingFile(path ?? recordingPath);
        } catch (_) {
          await _deleteRecordingFile(recordingPath);
        }
      }());
    } else if (recordingPath != null) {
      unawaited(_deleteRecordingFile(recordingPath));
    }
    _scroll.dispose();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    final cached = await LocalCache.loadMessages(widget.conversationId);
    if (!mounted) return;
    final home = ref.read(homeNotifierProvider).asData?.value;
    final conv = home?.conversations.where((c) => c.id == widget.conversationId).firstOrNull;
    if (mounted) {
      setState(() {
        if (cached != null && cached.isNotEmpty) {
          _messages = cached;
          _loading = false;
        }
        if (conv != null) _title = conv.name;
      });
      if (cached != null && cached.isNotEmpty) _scrollToBottom();
    }
    await _load();
  }

  void _scrollToBottom({bool animate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if (animate) {
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      } else {
        _scroll.jumpTo(target);
      }
    });
  }

  Future<void> _load({bool silent = false}) async {
    if (_loadInFlight || !mounted) return;
    _loadInFlight = true;
    if (!silent && _messages.isEmpty) {
      setState(() => _loading = true);
    }
    try {
      final api = ref.read(apiProvider);
      final page = await api.listMessages(widget.conversationId, limit: 50);
      // Keep locally cleared "heard" flags if refresh races with mark-read.
      final heardIds = {
        for (final m in _messages)
          if (!m.unread) m.id,
      };
      final messages = page.messages
          .map((m) => heardIds.contains(m.id) ? m.copyWith(unread: false) : m)
          .toList();
      await LocalCache.saveMessages(widget.conversationId, messages);
      unawaited(LocalCache.prefetchAudio(api, messages, keep: 3));

      final home = ref.read(homeNotifierProvider).asData?.value;
      final conv = home?.conversations.where((c) => c.id == widget.conversationId).firstOrNull;

      if (mounted) {
        setState(() {
          _messages = messages;
          _memberReads = page.memberReads;
          if (conv != null) _title = conv.name;
          _loading = false;
        });
        if (!silent) _scrollToBottom();
        unawaited(ref.read(homeNotifierProvider.notifier).refresh(silent: true));
      }
    } on ApiException catch (e) {
      if (mounted && !silent) showAppToast(context, e.message, error: true);
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted && !silent) {
        showAppToast(context, 'Üzenetek betöltése sikertelen', error: true);
      }
      debugPrint('message load error: $e');
      if (mounted) setState(() => _loading = false);
    } finally {
      _loadInFlight = false;
    }
  }

  /// Readers whose read cursor sits on this message (Messenger-style).
  List<MemberRead> _readersAt(int index, String meId) {
    final msg = _messages[index];
    final nextCreated =
        index + 1 < _messages.length ? _messages[index + 1].createdAt : null;
    return _memberReads.where((r) {
      if (r.userId == meId) return false;
      final at = r.lastReadAt;
      if (at == null || at.isEmpty) return false;
      if (at.compareTo(msg.createdAt) < 0) return false;
      if (nextCreated != null && at.compareTo(nextCreated) >= 0) return false;
      return true;
    }).toList();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _startRecording() async {
    if (_recordStarting || _recording || _sending) return;
    _recordStarting = true;
    if (!ref.read(connectivityProvider)) {
      showAppToast(context, 'Nincs internet', error: true);
      _recordStarting = false;
      return;
    }
    try {
      final ok = await _recorder.hasPermission();
      if (!ok) {
        if (mounted) showAppToast(context, 'Mikrofon engedély kell', error: true);
        return;
      }
      final dir = await getTemporaryDirectory();
      final file = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      _recordPath = file;
      _waveCollector.reset();
      await _ampSub?.cancel();
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: file,
      );
      _ampSub = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 80))
          .listen((amp) {
        _waveCollector.addDb(amp.current);
        if (mounted) setState(() {});
      });
      _recordTick?.cancel();
      _maxRecordTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _recording = true;
        _recordStarted = DateTime.now();
        _recordElapsed = Duration.zero;
      });
      _recordTick = Timer.periodic(const Duration(seconds: 1), (_) {
        final started = _recordStarted;
        if (started == null || !mounted) return;
        setState(() => _recordElapsed = DateTime.now().difference(started));
      });
      _maxRecordTimer = Timer(Duration(milliseconds: _maxRecordMs), () {
        if (_recording) unawaited(_stopAndSend());
      });
    } catch (e) {
      await _deleteRecordingFile(_recordPath);
      _recordPath = null;
      if (mounted) showAppToast(context, 'Felvétel nem indítható', error: true);
      debugPrint('record start error: $e');
    } finally {
      _recordStarting = false;
    }
  }

  Future<void> _stopAndSend() async {
    if (!_recording || _sending || _recordStarting) return;
    _recordTick?.cancel();
    _maxRecordTimer?.cancel();
    await _ampSub?.cancel();
    _ampSub = null;
    if (!mounted) return;
    final waveBars = _waveCollector.toBars();
    String? path;
    final started = _recordStarted;
    final maxMs = _maxRecordMs;
    setState(() {
      _recording = false;
      _recordStarted = null;
      _sending = true;
    });
    try {
      path = await _recorder.stop();
      if (path == null || started == null) return;

      final file = File(path);
      if (!await file.exists()) return;
      final maxUploadBytes = _maxRecordBytes;
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
        setState(() => _messages = [..._messages, local]);
        await LocalCache.saveMessages(widget.conversationId, _messages);
        _scrollToBottom(animate: true);
      }
      unawaited(_load(silent: true));
    } on ApiException catch (e) {
      if (mounted) showAppToast(context, e.message, error: true);
    } catch (e) {
      if (mounted) showAppToast(context, 'Hangüzenet küldése sikertelen', error: true);
      debugPrint('record send error: $e');
    } finally {
      await _deleteRecordingFile(path ?? _recordPath);
      _recordPath = null;
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleRecord() async {
    if (_recording) {
      await _stopAndSend();
      return;
    }
    await _startRecording();
  }

  Future<void> _play(VoiceMessage msg) async {
    final request = ++_playRequest;
    if (_playingId == msg.id) {
      await _player.stop();
      if (!mounted || request != _playRequest) return;
      setState(() {
        _playingId = null;
        _playProgress = 0;
        _playingDurationMs = 0;
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
        final bytes = await ref.read(apiProvider).downloadAudio(msg.url);
        await LocalCache.putAudio(msg.id, bytes);
        file = await LocalCache.audioFile(msg.id);
      }
      if (!mounted || request != _playRequest) return;

      final me = ref.read(authProvider).user;
      if (me == null) return;
      final meId = me.id;
      if (msg.senderId != meId && msg.unread) {
        // Clear yellow for this message and older ones.
        setState(() {
          _messages = _messages.map((m) {
            if (m.senderId == meId) return m;
            if (m.createdAt.compareTo(msg.createdAt) <= 0) {
              return m.copyWith(unread: false);
            }
            return m;
          }).toList();
        });
        unawaited(LocalCache.saveMessages(widget.conversationId, _messages));
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
        _playingId = msg.id;
        _playProgress = 0;
        _playingDurationMs = fallbackMs;
      });
      await _player.stop();
      if (!mounted || request != _playRequest) return;
      await _player.play(DeviceFileSource(file.path));

      // Prefer real media duration once (not on every position tick).
      final mediaDur = await _player.getDuration();
      if (mounted &&
          request == _playRequest &&
          _playingId == msg.id &&
          mediaDur != null &&
          mediaDur.inMilliseconds > 200) {
        setState(() => _playingDurationMs = mediaDur.inMilliseconds);
      }
    } on ApiException catch (e) {
      if (mounted && request == _playRequest) {
        showAppToast(context, e.message, error: true);
      }
    } catch (e) {
      if (mounted && request == _playRequest) {
        showAppToast(context, 'Lejátszás sikertelen', error: true);
      }
      debugPrint('audio playback error: $e');
    }
  }

  Future<void> _messageActions(VoiceMessage msg, {required bool mine}) async {
    final playing = _playingId == msg.id;
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
                  leading: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  title: Text(playing ? 'Szüneteltetés' : 'Lejátszás'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _play(msg);
                  },
                ),
                if (mine)
                  ListTile(
                    leading: Icon(Icons.delete_outline, color: t.colorScheme.error),
                    title: Text('Törlés', style: TextStyle(color: t.colorScheme.error)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _confirmDelete(msg);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(VoiceMessage msg) async {
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

    final prev = _messages;
    final next = _messages.where((m) => m.id != msg.id).toList();
    setState(() => _messages = next);
    unawaited(LocalCache.saveMessages(widget.conversationId, next));
    if (_playingId == msg.id) {
      unawaited(_player.stop());
      setState(() {
        _playingId = null;
        _playProgress = 0;
        _playingDurationMs = 0;
      });
    }

    try {
      await ref.read(apiProvider).deleteMessage(msg.id);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _messages = prev);
      unawaited(LocalCache.saveMessages(widget.conversationId, prev));
      showAppToast(context, e.message, error: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _messages = prev);
      unawaited(LocalCache.saveMessages(widget.conversationId, prev));
      showAppToast(context, 'Törlés sikertelen', error: true);
    }
  }

  Future<void> _call(String type) async {
    if (_callStarting) return;
    if (!ref.read(connectivityProvider)) {
      showAppToast(context, 'Nincs internet', error: true);
      return;
    }
    _callStarting = true;
    try {
      final session = await ref.read(apiProvider).startCall(
            conversationId: widget.conversationId,
            callType: type,
          );
      if (!mounted) return;
      context.push('/call/${session.id}', extra: {
        'livekitUrl': session.livekitUrl,
        'token': session.token,
        'callType': session.callType,
        'title': _title,
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      showAppToast(context, e.message, error: true);
    } finally {
      _callStarting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authProvider).user!.id;
    final paid = ref.watch(familyProvider).asData?.value.family?.isPaid ?? false;
    final t = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          if (paid) ...[
            IconButton(
              tooltip: 'Hanghívás',
              onPressed: () => _call('audio'),
              icon: const Icon(Icons.call),
            ),
            IconButton(
              tooltip: 'Videó',
              onPressed: () => _call('video'),
              icon: const Icon(Icons.videocam),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Text(
                          'Még nincs hangüzenet.\nKoppints a mikrofonra a felvételhez.',
                          textAlign: TextAlign.center,
                          style: t.textTheme.bodyLarge,
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                        itemCount: _messages.length,
                        itemBuilder: (context, i) {
                          final m = _messages[i];
                          final mine = m.senderId == me;
                          final readers = _readersAt(i, me);
                          return Align(
                            alignment:
                                mine ? Alignment.centerRight : Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: MediaQuery.sizeOf(context).width * 0.82,
                                  minWidth: 160,
                                ),
                                child: Column(
                                  crossAxisAlignment: mine
                                      ? CrossAxisAlignment.end
                                      : CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: EdgeInsets.only(
                                        left: mine ? 0 : 4,
                                        right: mine ? 4 : 0,
                                        bottom: 4,
                                      ),
                                      child: Text(
                                        mine ? 'Te' : m.senderName,
                                        style: t.textTheme.labelMedium?.copyWith(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: t.colorScheme.onSurface
                                              .withValues(alpha: 0.55),
                                        ),
                                      ),
                                    ),
                                    VoiceWaveBubble(
                                      mine: mine,
                                      durationMs: m.durationMs,
                                      messageId: m.id,
                                      waveBars: m.waveBars,
                                      playing: _playingId == m.id,
                                      progress:
                                          _playingId == m.id ? _playProgress : 0,
                                      unread: m.unread && !mine,
                                      onTap: () => _play(m),
                                      onLongPress: () =>
                                          _messageActions(m, mine: mine),
                                    ),
                                    if (readers.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Padding(
                                        padding: EdgeInsets.only(
                                          left: mine ? 0 : 6,
                                          right: mine ? 6 : 0,
                                        ),
                                        child: Wrap(
                                          spacing: 4,
                                          runSpacing: 4,
                                          alignment: mine
                                              ? WrapAlignment.end
                                              : WrapAlignment.start,
                                          children: readers
                                              .map(
                                                (r) => Tooltip(
                                                  message: r.name,
                                                  child: UserAvatar(
                                                    name: r.name,
                                                    avatarUrl: r.avatarUrl,
                                                    userId: r.userId,
                                                    radius: 10,
                                                  ),
                                                ),
                                              )
                                              .toList(),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: [
                  if (_recording)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        children: [
                          Text(
                            'Felvétel · ${_fmt(_recordElapsed)}',
                            style: t.textTheme.titleLarge?.copyWith(
                              color: t.colorScheme.error,
                            ),
                          ),
                          const SizedBox(height: 10),
                          LiveScrollWave(
                            samples: _waveCollector.liveScrollUnits(),
                            height: 44,
                          ),
                        ],
                      ),
                    ),
                  BigButton(
                    label: _sending
                        ? 'Küldés…'
                        : _recording
                            ? 'Küldés'
                            : 'Hangüzenet',
                    icon: _recording ? Icons.stop : Icons.mic,
                    onPressed: _sending ? null : _toggleRecord,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
