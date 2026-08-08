import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../providers/realtime_provider.dart';
import '../router.dart';
import '../services/app_notify.dart';
import '../services/call_navigation.dart';
import '../services/incoming_call_presenter.dart';
import '../services/pending_call_store.dart';

/// App-wide incoming-call watcher (single presenter + pending actions).
class IncomingCallHost extends ConsumerStatefulWidget {
  const IncomingCallHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<IncomingCallHost> createState() => _IncomingCallHostState();
}

class _IncomingCallHostState extends ConsumerState<IncomingCallHost>
    with WidgetsBindingObserver {
  Timer? _poll;
  Timer? _pendingTimer;
  StreamSubscription? _rtSub;
  String? _incomingCallId;
  bool _joinInFlight = false;
  bool _tickInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Fast poll so FSI-woken app finds ringing call without waiting 12s.
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _tick());
    _pendingTimer = Timer.periodic(const Duration(milliseconds: 350), (_) {
      unawaited(_drainPending());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(realtimeLifecycleProvider);
      _rtSub = ref.read(realtimeProvider).events.listen(_onRealtime);
      unawaited(_bootstrap());
    });
  }

  Future<void> _bootstrap() async {
    // Ignore stale persisted rings on a normal open (avoid sudden /incoming jump).
    final hydrated = await PendingCallStore.hydratePending();
    if (hydrated) {
      await _drainPending();
    }
    _tick();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _pendingTimer?.cancel();
    _rtSub?.cancel();
    AppNotify.stopCallRingtone();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_bootstrap());
    }
  }

  Future<void> _drainPending() async {
    if (!mounted || _joinInFlight) return;
    final auth = ref.read(authProvider);
    if (!auth.isLoggedIn || auth.loading) return;

    final router = ref.read(routerProvider);
    final loc = router.state.matchedLocation;

    final declineId = PendingCallAction.declineCallId;
    if (declineId != null) {
      PendingCallAction.declineCallId = null;
      try {
        await ref.read(apiProvider).declineCall(declineId);
      } catch (_) {}
      await IncomingCallPresenter.dismiss(declineId);
      if (_incomingCallId == declineId) _incomingCallId = null;
      if (loc.startsWith('/incoming/')) {
        router.go('/');
      }
      return;
    }

    final dismissId = PendingCallAction.dismissCallId;
    if (dismissId != null) {
      PendingCallAction.dismissCallId = null;
      await IncomingCallPresenter.dismiss(dismissId);
      if (_incomingCallId == dismissId) _incomingCallId = null;
      if (loc.startsWith('/incoming/')) {
        router.go('/');
      }
      return;
    }

    final acceptId = PendingCallAction.acceptCallId;
    if (acceptId != null) {
      PendingCallAction.acceptCallId = null;
      await _acceptById(acceptId);
      return;
    }

    final ringId = PendingCallAction.ringCallId;
    if (ringId != null && ringId.isNotEmpty) {
      if (_incomingCallId == ringId ||
          loc == '/incoming/$ringId' ||
          loc.startsWith('/call/')) {
        PendingCallAction.ringCallId = null;
      } else {
        final name = PendingCallAction.ringCallerName ?? 'Családtag';
        final type = PendingCallAction.ringCallType ?? 'audio';
        PendingCallAction.ringCallId = null;
        _incomingCallId = ringId;
        router.go('/incoming/$ringId', extra: {
          'callerName': name,
          'callType': type,
        });
        unawaited(IncomingCallPresenter.onFullScreenShown(ringId));
        return;
      }
    }

    final conversationId = PendingCallAction.conversationId;
    if (conversationId != null && conversationId.isNotEmpty) {
      PendingCallAction.conversationId = null;
      if (!loc.startsWith('/call/') && !loc.startsWith('/incoming/')) {
        router.go('/chat/$conversationId');
      }
    }
  }

  void _onRealtime(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    if (type == 'incoming_call') {
      unawaited(_presentFromEvent(event));
    } else if (type == 'call_ended') {
      final id = event['callId'] as String?;
      if (id == null) return;
      unawaited(IncomingCallPresenter.dismiss(id));
      if (_incomingCallId == id) _incomingCallId = null;
      final router = ref.read(routerProvider);
      final loc = router.state.matchedLocation;
      if (loc == '/incoming/$id') {
        router.go('/');
      }
      // /call/:id listens itself via CallScreen.
    } else if (type == 'call_updated') {
      // Active = someone answered. Do NOT pop /incoming (accept race).
      // Group members may still join; ringtone can stop once we're on call UI.
      final id = event['callId'] as String?;
      final status = event['status'] as String?;
      if (id == null || status != 'active') return;
      final loc = ref.read(routerProvider).state.matchedLocation;
      if (loc.startsWith('/call/')) {
        unawaited(IncomingCallPresenter.dismiss(id));
      }
    } else if (type == 'message_created') {
      final from = event['fromName'] as String? ?? 'Családtag';
      final conversationId = event['conversationId'] as String?;
      unawaited(AppNotify.showMessage(
        title: 'Új hangüzenet',
        body: '$from hangüzenetet küldött',
        conversationId: conversationId,
      ));
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
    if (_incomingCallId == id || IncomingCallPresenter.isPresenting(id)) return;

    _incomingCallId = id;
    await IncomingCallPresenter.present(
      callId: id,
      callerName: event['fromName'] as String? ?? 'Családtag',
      callType: event['callType'] as String? ?? 'audio',
      conversationId: event['conversationId'] as String?,
    );
  }

  Future<void> _tick() async {
    if (_tickInFlight || !mounted) return;
    final auth = ref.read(authProvider);
    if (!auth.isLoggedIn || auth.loading) return;

    final loc = ref.read(routerProvider).state.matchedLocation;
    if (loc.startsWith('/call/')) return;

    _tickInFlight = true;
    try {
      await PendingCallStore.hydratePending();

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
          final id = _incomingCallId!;
          await IncomingCallPresenter.dismiss(id);
          _incomingCallId = null;
          if (loc == '/incoming/$id') {
            ref.read(routerProvider).go('/');
          }
        }
        return;
      }

      final id = ringing['id'] as String;
      if (_incomingCallId == id || IncomingCallPresenter.isPresenting(id)) {
        // Ensure /incoming is open after FSI wake even if already "presenting".
        if (!loc.startsWith('/incoming/') && !loc.startsWith('/call/')) {
          PendingCallAction.setRing(
            id,
            callerName: PendingCallAction.ringCallerName ?? 'Bejövő hívás',
            callType: ringing['call_type'] as String? ?? 'audio',
          );
        }
        return;
      }
      _incomingCallId = id;
      await IncomingCallPresenter.present(
        callId: id,
        callerName: 'Bejövő hívás',
        callType: ringing['call_type'] as String? ?? 'audio',
      );
    } catch (_) {
    } finally {
      _tickInFlight = false;
    }
  }

  Future<void> _acceptById(String callId) async {
    if (_joinInFlight) return;
    _joinInFlight = true;
    await IncomingCallPresenter.dismiss(callId);
    try {
      CallJoinGuard.begin(callId);
      // Instant open — CallScreen joins LiveKit itself.
      ref.read(routerProvider).go('/call/$callId', extra: {
        'livekitUrl': '',
        'token': '',
        'callType': PendingCallAction.ringCallType ?? 'audio',
        'mode': 'direct',
        'title': PendingCallAction.ringCallerName ?? 'Hívás',
      });
    } finally {
      _joinInFlight = false;
      _incomingCallId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(realtimeLifecycleProvider);
    return widget.child;
  }
}
