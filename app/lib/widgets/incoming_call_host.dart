import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/providers.dart';
import '../router.dart';
import '../services/api_client.dart';
import '../services/app_notify.dart';
import '../services/toast.dart';
import 'widgets.dart';

/// App-wide incoming-call watcher so callees get alerted even outside Home.
class IncomingCallHost extends ConsumerStatefulWidget {
  const IncomingCallHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<IncomingCallHost> createState() => _IncomingCallHostState();
}

class _IncomingCallHostState extends ConsumerState<IncomingCallHost> {
  Timer? _poll;
  String? _incomingCallId;
  bool _sheetOpen = false;
  bool _actionInFlight = false;
  bool _tickInFlight = false;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _tick());
    WidgetsBinding.instance.addPostFrameCallback((_) => _tick());
  }

  @override
  void dispose() {
    _poll?.cancel();
    AppNotify.stopCallRingtone();
    super.dispose();
  }

  Future<void> _tick() async {
    if (_tickInFlight || !mounted) return;
    final auth = ref.read(authProvider);
    if (!auth.isLoggedIn || auth.loading) return;

    // Don't interrupt an active call screen with another sheet.
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
                    if (_actionInFlight) return;
                    _actionInFlight = true;
                    await AppNotify.stopCallRingtone();
                    if (ctx.mounted) Navigator.pop(ctx);
                    try {
                      final session =
                          await ref.read(apiProvider).joinCall(call['id'] as String);
                      if (!mounted) return;
                      context.push('/call/${session.id}', extra: {
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
                    }
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
  Widget build(BuildContext context) => widget.child;
}
