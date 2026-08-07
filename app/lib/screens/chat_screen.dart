import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../services/api_client.dart';
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
  bool _loading = true;
  bool _recording = false;
  DateTime? _recordStarted;
  Duration _recordElapsed = Duration.zero;
  String? _playingId;
  String? _error;
  String _title = 'Beszélgetés';
  Timer? _refresh;
  Timer? _recordTick;
  Timer? _maxRecordTimer;
  bool _sending = false;

  int get _maxRecordMs {
    final fam = ref.read(familyProvider).asData?.value.family;
    return fam?.voiceMaxMs ?? 2 * 60 * 1000;
  }

  @override
  void initState() {
    super.initState();
    _load();
    _refresh = Timer.periodic(const Duration(seconds: 8), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _recordTick?.cancel();
    _maxRecordTimer?.cancel();
    _scroll.dispose();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
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
    if (!silent) setState(() => _loading = true);
    try {
      final api = ref.read(apiProvider);
      final messages = await api.listMessages(widget.conversationId);
      final detail = await api.listConversations();
      final conv = detail.conversations
          .where((c) => c.id == widget.conversationId)
          .firstOrNull;
      if (mounted) {
        setState(() {
          _messages = messages;
          _title = conv?.name ?? _title;
          _loading = false;
          _error = null;
        });
        _scrollToBottom();
        ref.invalidate(homeProvider);
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _startRecording() async {
    final ok = await _recorder.hasPermission();
    if (!ok) {
      setState(() => _error = 'Mikrofon engedély kell');
      return;
    }
    final dir = await getTemporaryDirectory();
    final file = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: file,
    );
    _recordTick?.cancel();
    _maxRecordTimer?.cancel();
    setState(() {
      _recording = true;
      _recordStarted = DateTime.now();
      _recordElapsed = Duration.zero;
      _error = null;
    });
    _recordTick = Timer.periodic(const Duration(seconds: 1), (_) {
      final started = _recordStarted;
      if (started == null || !mounted) return;
      setState(() => _recordElapsed = DateTime.now().difference(started));
    });
    _maxRecordTimer = Timer(Duration(milliseconds: _maxRecordMs), () {
      if (_recording) _stopAndSend();
    });
  }

  Future<void> _stopAndSend() async {
    if (!_recording || _sending) return;
    _recordTick?.cancel();
    _maxRecordTimer?.cancel();
    final path = await _recorder.stop();
    final started = _recordStarted;
    final maxMs = _maxRecordMs;
    setState(() {
      _recording = false;
      _recordStarted = null;
      _sending = true;
    });
    if (path == null || started == null) {
      setState(() => _sending = false);
      return;
    }
    var duration = DateTime.now().difference(started).inMilliseconds;
    if (duration > maxMs) duration = maxMs;
    final bytes = await File(path).readAsBytes();
    try {
      await ref.read(apiProvider).uploadVoice(
            conversationId: widget.conversationId,
            bytes: bytes,
            contentType: 'audio/m4a',
            durationMs: duration,
          );
      await _load();
      _scrollToBottom(animate: true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
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
    if (_playingId == msg.id) {
      await _player.stop();
      setState(() => _playingId = null);
      return;
    }
    final bytes = await ref.read(apiProvider).downloadAudio(msg.url);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${msg.id}.m4a');
    await file.writeAsBytes(bytes, flush: true);
    setState(() => _playingId = msg.id);
    await _player.play(DeviceFileSource(file.path));
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingId = null);
    });
  }

  Future<void> _confirmDelete(VoiceMessage msg) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Üzenet törlése'),
        content: const Text('Biztosan törlöd ezt a hangüzenetet?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Mégse')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Törlés')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiProvider).deleteMessage(msg.id);
      if (!mounted) return;
      setState(() => _messages = _messages.where((m) => m.id != msg.id).toList());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _call(String type) async {
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
      setState(() => _error = e.message);
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
          if (_error != null)
            Material(
              color: const Color(0xFFFFE8E6),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!, style: TextStyle(color: t.colorScheme.error)),
              ),
            ),
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
                          return Align(
                            alignment:
                                mine ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              constraints: BoxConstraints(
                                maxWidth: MediaQuery.sizeOf(context).width * 0.82,
                              ),
                              child: SoftCard(
                                onTap: () => _play(m),
                                onLongPress: mine ? () => _confirmDelete(m) : null,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (m.unread && !mine)
                                      Container(
                                        width: 10,
                                        height: 10,
                                        margin: const EdgeInsets.only(right: 8),
                                        decoration: BoxDecoration(
                                          color: t.colorScheme.primary,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    Icon(
                                      _playingId == m.id
                                          ? Icons.stop_circle
                                          : Icons.play_circle_fill,
                                      size: 40,
                                      color: t.colorScheme.primary,
                                    ),
                                    const SizedBox(width: 10),
                                    Flexible(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            mine ? 'Te' : m.senderName,
                                            style: t.textTheme.titleLarge?.copyWith(
                                              fontSize: 16,
                                              fontWeight: m.unread && !mine
                                                  ? FontWeight.w800
                                                  : FontWeight.w700,
                                            ),
                                          ),
                                          Text(
                                            '${(m.durationMs / 1000).ceil()} mp hangüzenet',
                                            style: t.textTheme.bodyMedium?.copyWith(
                                              fontWeight: m.unread && !mine
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
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
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        'Felvétel · ${_fmt(_recordElapsed)}',
                        style: t.textTheme.titleLarge?.copyWith(
                          color: t.colorScheme.error,
                        ),
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
