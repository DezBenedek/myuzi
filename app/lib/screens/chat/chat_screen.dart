import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../providers/connectivity_provider.dart';
import '../../providers/providers.dart';
import '../../providers/realtime_provider.dart';
import '../../router.dart';
import '../../services/api_client.dart';
import '../../services/local_cache.dart';
import '../../services/toast.dart';
import 'chat_call_event.dart';
import 'chat_composer.dart';
import 'chat_message_list.dart';
import 'chat_playback.dart';
import 'chat_recording.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<ChatScreen> createState() => ChatScreenState();
}

class ChatScreenState extends ConsumerState<ChatScreen>
    with ChatRecordingMixin, ChatPlaybackMixin {
  final scroll = ScrollController();
  @override
  List<VoiceMessage> messages = [];
  List<MemberRead> memberReads = [];
  bool loading = true;
  String title = 'Beszélgetés';
  Timer? refresh;
  StreamSubscription? rtSub;
  bool loadInFlight = false;
  bool callStarting = false;
  bool _busyJoin = false;

  /// Active/ringing call in this chat that we can join (not already on call UI).
  VoiceMessage? get _joinableCall {
    final me = ref.read(authProvider).user?.id;
    if (me == null) return null;
    for (final m in messages.reversed) {
      if (!m.isCall) continue;
      final status = m.callStatus;
      if (status != 'ringing' && status != 'active') continue;
      final callId = m.callId;
      if (callId == null || callId.isEmpty) continue;
      return m;
    }
    return null;
  }

  @override
  int get maxRecordMs {
    final fam = ref.read(familyProvider).asData?.value.family;
    return fam?.voiceMaxMs ?? 2 * 60 * 1000;
  }

  @override
  int get maxRecordBytes {
    final plan = ref.read(familyProvider).asData?.value.family?.plan;
    if (plan == 'family_plus') return 20 * 1024 * 1024;
    if (plan == 'family') return 12 * 1024 * 1024;
    return 8 * 1024 * 1024;
  }

  @override
  void initState() {
    super.initState();
    initPlayback();
    boot();
    refresh = Timer.periodic(
      const Duration(seconds: 25),
      (_) => loadMessages(silent: true),
    );
    rtSub = ref.read(realtimeProvider).events.listen((ev) {
      final type = ev['type'] as String?;
      if (type == 'message_created' &&
          ev['conversationId'] == widget.conversationId) {
        unawaited(loadMessages(silent: true));
      } else if ((type == 'call_updated' ||
              type == 'call_ended' ||
              type == 'incoming_call') &&
          ev['conversationId'] == widget.conversationId) {
        unawaited(loadMessages(silent: true));
      }
    });
  }

  @override
  Future<void> deleteRecordingFile(String? path) async {
    if (path == null) return;
    try {
      await File(path).delete();
    } catch (_) {}
  }

  @override
  void dispose() {
    refresh?.cancel();
    rtSub?.cancel();
    disposeRecording();
    disposePlayback();
    scroll.dispose();
    super.dispose();
  }

  Future<void> boot() async {
    final cached = await LocalCache.loadMessages(widget.conversationId);
    if (!mounted) return;
    final home = ref.read(homeNotifierProvider).asData?.value;
    final conv =
        home?.conversations.where((c) => c.id == widget.conversationId).firstOrNull;
    if (mounted) {
      setState(() {
        if (cached != null && cached.isNotEmpty) {
          messages = cached;
          loading = false;
        }
        if (conv != null) title = conv.name;
      });
      if (cached != null && cached.isNotEmpty) scrollToBottom();
    }
    await loadMessages();
  }

  @override
  void scrollToBottom({bool animate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scroll.hasClients) return;
      final target = scroll.position.maxScrollExtent;
      if (animate) {
        scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      } else {
        scroll.jumpTo(target);
      }
    });
  }

  @override
  Future<void> loadMessages({bool silent = false}) async {
    if (loadInFlight || !mounted) return;
    loadInFlight = true;
    if (!silent && messages.isEmpty) {
      setState(() => loading = true);
    }
    try {
      final api = ref.read(apiProvider);
      final page = await api.listMessages(widget.conversationId, limit: 50);
      // Keep locally cleared "heard" flags if refresh races with mark-read.
      final heardIds = {
        for (final m in messages)
          if (!m.unread) m.id,
      };
      final next = page.messages
          .map((m) => heardIds.contains(m.id) ? m.copyWith(unread: false) : m)
          .toList();
      await LocalCache.saveMessages(widget.conversationId, next);
      unawaited(LocalCache.prefetchAudio(
        api,
        next.where((m) => !m.isCall && m.url != null).toList(),
        keep: 3,
      ));

      final home = ref.read(homeNotifierProvider).asData?.value;
      final conv =
          home?.conversations.where((c) => c.id == widget.conversationId).firstOrNull;

      if (mounted) {
        setState(() {
          messages = next;
          memberReads = page.memberReads;
          if (conv != null) title = conv.name;
          loading = false;
        });
        if (!silent) scrollToBottom();
        unawaited(ref.read(homeNotifierProvider.notifier).refresh(silent: true));
      }
    } on ApiException catch (e) {
      if (mounted && !silent) showAppToast(context, e.message, error: true);
      if (mounted) setState(() => loading = false);
    } catch (e) {
      if (mounted && !silent) {
        showAppToast(context, 'Üzenetek betöltése sikertelen', error: true);
      }
      debugPrint('message load error: $e');
      if (mounted) setState(() => loading = false);
    } finally {
      loadInFlight = false;
    }
  }

  Future<void> startCall(String type) async {
    if (callStarting) return;
    if (!ref.read(connectivityProvider)) {
      showAppToast(context, 'Nincs internet', error: true);
      return;
    }
    callStarting = true;
    try {
      final session = await ref.read(apiProvider).startCall(
            conversationId: widget.conversationId,
            callType: type,
          );
      if (!mounted) return;
      unawaited(loadMessages(silent: true));
      context.push('/call/${session.id}', extra: {
        'livekitUrl': session.livekitUrl,
        'token': session.token,
        'callType': session.callType,
        'mode': session.mode,
        'title': title,
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      showAppToast(context, e.message, error: true);
    } finally {
      callStarting = false;
    }
  }

  Future<void> onCallEventTap(VoiceMessage m) async {
    await joinCallFromChatEvent(
      context: context,
      api: ref.read(apiProvider),
      router: ref.read(routerProvider),
      message: m,
      title: title,
    );
  }

  Future<void> _joinActiveCall(VoiceMessage m) async {
    if (_busyJoin) return;
    setState(() => _busyJoin = true);
    try {
      await joinCallFromChatEvent(
        context: context,
        api: ref.read(apiProvider),
        router: ref.read(routerProvider),
        message: m,
        title: title,
      );
    } finally {
      if (mounted) setState(() => _busyJoin = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authProvider).user!.id;
    final paid = ref.watch(familyProvider).asData?.value.family?.isPaid ?? false;
    final t = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (paid) ...[
            if (_joinableCall != null)
              TextButton(
                onPressed: _busyJoin ? null : () => _joinActiveCall(_joinableCall!),
                child: Text(
                  _busyJoin ? 'Csatlakozás…' : 'Csatlakozás!',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              )
            else ...[
              IconButton(
                tooltip: 'Hanghívás',
                onPressed: () => startCall('audio'),
                icon: const Icon(Icons.call),
              ),
              IconButton(
                tooltip: 'Videó',
                onPressed: () => startCall('video'),
                icon: const Icon(Icons.videocam),
              ),
            ],
          ],
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : messages.isEmpty
                    ? Center(
                        child: Text(
                          'Még nincs hangüzenet.\nKoppints a mikrofonra a felvételhez.',
                          textAlign: TextAlign.center,
                          style: t.textTheme.bodyLarge,
                        ),
                      )
                    : ChatMessageList(
                        messages: messages,
                        memberReads: memberReads,
                        scrollController: scroll,
                        meId: me,
                        playingId: playingId,
                        playProgress: playProgress,
                        onPlay: playMessage,
                        onMessageActions: messageActions,
                        onCallEventTap: onCallEventTap,
                      ),
          ),
          ChatComposer(
            recording: recording,
            sending: sending,
            recordElapsed: recordElapsed,
            waveSamples: waveCollector.liveScrollUnits(),
            onToggleRecord: sending ? null : toggleRecord,
          ),
        ],
      ),
    );
  }
}
