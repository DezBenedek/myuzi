import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../providers/realtime_provider.dart';
import '../router.dart';
import '../services/api_client.dart';
import '../services/app_notify.dart';
import '../services/toast.dart';
import 'widgets.dart';

/// App-wide incoming-call watcher (realtime + slow poll fallback).
class IncomingCallHost extends ConsumerStatefulWidget {
  const IncomingCallHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<IncomingCallHost> createState() => _IncomingCallHostState();
}

class _IncomingCallHostState extends ConsumerState<IncomingCallHost>
    with WidgetsBindingObserver {
  Timer? _poll;
  StreamSubscription? _rtSub;
  String? _incomingCallId;
  bool _sheetOpen = false;
  bool _actionInFlight = false;
  bool _tickInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Slow fallback if WS drops; primary path is Durable Object events.
    _poll = Timer.periodic(const Duration(seconds: 12), (_) => _tick());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(realtimeLifecycleProvider);
      _rtSub = ref.read(realtimeProvider).events.listen(_onRealtime);
      _tick();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _rtSub?.cancel();
    AppNotify.stopCallRingtone();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _tick();
    }
  }

  void _onRealtime(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    if (type == 'incoming_call') {
      unawaited(_presentFromEvent(event));
    } else if (type == 'call_ended' || type == 'call_updated') {
      final id = event['callId'] as String?;
      final status = event['status'] as String?;
      if (id != null &&
          id == _incomingCallId &&
          (type == 'call_ended' || status == 'active')) {
        unawaited(AppNotify.stopCallRingtone());
        if (mounted) setState(() => _incomingCallId = null);
      }
    } else if (type == 'message_created') {
      final from = event['fromName'] as String? ?? 'Családtag';
      unawaited(AppNotify.showMessage(title: 'Új hangüzenet', body: '$from hangüzenetet küldött'));
      unawaited(ref.read(homeNotifierProvider.notifier).refresh(silent: true));
    }
  }

  Future<void> _presentFromEvent(Map<String, dynamic> event) async {
    final auth = ref.read(authProvider);
    if (!auth.isLoggedIn) return;
    final loc = ref.read(routerProvider).state.matchedLocation;
    if (loc.startsWith('/call/')) return;

    final id = event['callId'] as String?;
    if (id == null || id.isEmpty) return;
    if (_incomingCallId == id && _sheetOpen) return;

    final call = <String, dynamic>{
      'id': id,
      'call_type': event['callType'] ?? 'audio',
      'status': 'ringing',
      'initiated_by': '', // not us — server already filtered
    };
    _incomingCallId = id;
    await AppNotify.showIncomingCall(
      title: 'Bejövő hívás',
      body: (event['fromName'] as String?)?.isNotEmpty == true
          ? '${event['fromName']} hív'
          : (event['callType'] == 'video' ? 'Videóhívás' : 'Hanghívás'),
    );
    if (!mounted) return;
    await _showIncoming(call);
  }

  Future<void> _tick() async {
    if (_tickInFlight || !mounted) return;
    final auth = ref.read(authProvider);
    if (!auth.isLoggedIn || auth.loading) return;

    final loc = ref.read(routerProvider).state.matchedLocation;
    if (loc.startsWith('/call/')) return;

    _tickInFlight = true;
    try {
      final calls = await ref.read(apiProvider).activeCalls();
      final me = ref.read(authProvider).user?.id;
      if (!mounted || me == null) return;

      Map<String, dynamic>? ringing;
      for (final call in calls) {
        if (call['status'] == 'ringing' && call['initiated_by'] != me) {
          ringing = call;
          break;
        }
      }

      if (ringing == null) {
        if (_incomingCallId != null) {
          await AppNotify.stopCallRingtone();
          if (mounted) setState(() => _incomingCallId = null);
        }
        return;
      }

      final id = ringing['id'] as String;
      if (_incomingCallId == id && _sheetOpen) return;

      _incomingCallId = id;
      await AppNotify.showIncomingCall(
        title: 'Bejövő hívás',
        body: ringing['call_type'] == 'video' ? 'Videóhívás' : 'Hanghívás',
      );
      if (!mounted) return;
      await _showIncoming(ringing);
    } catch (_) {
    } finally {
      _tickInFlight = false;
    }
  }

  Future<void> _accept(Map<String, dynamic> call) async {
    if (_actionInFlight) return;
    _actionInFlight = true;
    await AppNotify.stopCallRingtone();
    try {
      final session = await ref.read(apiProvider).joinCall(call['id'] as String);
      if (!mounted) return;
      // Must use GoRouter from routerProvider — builder context is above the router.
      await ref.read(routerProvider).push('/call/${session.id}', extra: {
        'livekitUrl': session.livekitUrl,
        'token': session.token,
        'callType': session.callType,
        'title': 'Hívás',
      });
    } on ApiException catch (e) {
      if (mounted) showAppToast(context, e.message, error: true);
    } catch (_) {
      if (mounted) {
        showAppToast(context, 'A hívás nem érhető el', error: true);
      }
    } finally {
      _actionInFlight = false;
      if (mounted) setState(() => _incomingCallId = null);
    }
  }

  Future<void> _showIncoming(Map<String, dynamic> call) async {
    if (_sheetOpen || !mounted) return;
    _sheetOpen = true;
    await AppNotify.startCallRingtone();
    if (!mounted) {
      _sheetOpen = false;
      await AppNotify.stopCallRingtone();
      return;
    }
    try {
      await showModalBottomSheet<void>(
        context: context,
        isDismissible: false,
        enableDrag: false,
        builder: (ctx) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Bejövő hívás', style: Theme.of(ctx).textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  call['call_type'] == 'video' ? 'Videóhívás' : 'Hanghívás',
                  style: Theme.of(ctx).textTheme.bodyLarge,
                ),
                const SizedBox(height: 20),
                BigButton(
                  label: 'Fogadás',
                  icon: Icons.call,
                  onPressed: () async {
                    if (ctx.mounted) Navigator.pop(ctx);
                    await _accept(call);
                  },
                ),
                const SizedBox(height: 10),
                BigButton(
                  label: 'Elutasítás',
                  icon: Icons.call_end,
                  outlined: true,
                  danger: true,
                  onPressed: () async {
                    if (_actionInFlight) return;
                    _actionInFlight = true;
                    await AppNotify.stopCallRingtone();
                    if (ctx.mounted) Navigator.pop(ctx);
                    try {
                      await ref.read(apiProvider).endCall(call['id'] as String);
                    } catch (_) {}
                    if (mounted) setState(() => _incomingCallId = null);
                    _actionInFlight = false;
                  },
                ),
              ],
            ),
          );
        },
      );
    } finally {
      _sheetOpen = false;
      await AppNotify.stopCallRingtone();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(realtimeLifecycleProvider);
    return widget.child;
  }
}
