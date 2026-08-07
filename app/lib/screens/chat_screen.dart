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
  List<VoiceMessage> _messages = [];
  bool _loading = true;
  bool _recording = false;
  DateTime? _recordStarted;
  String? _playingId;
  String? _error;
  String _title = 'Beszélgetés';
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _load();
    _refresh = Timer.periodic(const Duration(seconds: 8), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
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

  Future<void> _toggleRecord() async {
    if (_recording) {
      final path = await _recorder.stop();
      final started = _recordStarted;
      setState(() {
        _recording = false;
        _recordStarted = null;
      });
      if (path == null || started == null) return;
      final duration = DateTime.now().difference(started).inMilliseconds;
      final bytes = await File(path).readAsBytes();
      try {
        await ref.read(apiProvider).uploadVoice(
              conversationId: widget.conversationId,
              bytes: bytes,
              contentType: 'audio/m4a',
              durationMs: duration,
            );
        await _load();
      } on ApiException catch (e) {
        if (mounted) setState(() => _error = e.message);
      }
      return;
    }

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
    setState(() {
      _recording = true;
      _recordStarted = DateTime.now();
      _error = null;
    });
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

  Future<void> _call(String type) async {
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
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authProvider).user!.id;
    final t = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
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
                          'Még nincs hangüzenet.\nNyomd meg és tartsd, vagy koppints a mikrofonra.',
                          textAlign: TextAlign.center,
                          style: t.textTheme.bodyLarge,
                        ),
                      )
                    : ListView.builder(
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
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
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
                                            style: t.textTheme.titleLarge?.copyWith(fontSize: 16),
                                          ),
                                          Text(
                                            '${(m.durationMs / 1000).ceil()} mp hangüzenet',
                                            style: t.textTheme.bodyMedium,
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
              child: BigButton(
                label: _recording ? 'Küldés (felvétel alatt)' : 'Hangüzenet',
                icon: _recording ? Icons.stop : Icons.mic,
                onPressed: _toggleRecord,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
