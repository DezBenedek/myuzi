import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../router.dart';
import '../services/app_notify.dart';
import '../services/call_navigation.dart';
import '../services/incoming_call_presenter.dart';
import '../widgets/widgets.dart';

/// Full-screen incoming call UI — primary accept surface on phone.
class IncomingCallScreen extends ConsumerStatefulWidget {
  const IncomingCallScreen({
    super.key,
    required this.callId,
    required this.callerName,
    required this.callType,
  });

  final String callId;
  final String callerName;
  final String callType;

  @override
  ConsumerState<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends ConsumerState<IncomingCallScreen> {
  bool _busy = false;

  bool get _video => widget.callType == 'video';

  @override
  void initState() {
    super.initState();
    // Full-screen is up → drop heads-up push (keep ringtone).
    unawaited(IncomingCallPresenter.onFullScreenShown(widget.callId));
    unawaited(AppNotify.startCallRingtone());
  }

  @override
  void dispose() {
    super.dispose();
  }

  /// Open call UI immediately; LiveKit join happens on CallScreen.
  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    CallJoinGuard.begin(widget.callId);
    await IncomingCallPresenter.dismiss(widget.callId);
    if (!mounted) return;
    // Instant navigation — CallScreen re-joins if token empty.
    ref.read(routerProvider).go('/call/${widget.callId}', extra: {
      'livekitUrl': '',
      'token': '',
      'callType': widget.callType,
      'mode': 'direct',
      'title': widget.callerName,
    });
  }

  Future<void> _decline() async {
    if (_busy) return;
    setState(() => _busy = true);
    await IncomingCallPresenter.dismiss(widget.callId);
    try {
      await ref.read(apiProvider).declineCall(widget.callId);
    } catch (_) {}
    if (!mounted) return;
    ref.read(routerProvider).go('/');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return PopScope(
      canPop: !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) unawaited(AppNotify.stopCallRingtone());
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0B3D2E),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              children: [
                const Spacer(),
                Text(
                  'Bejövő hívás',
                  style: t.textTheme.titleMedium?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 12),
                CircleAvatar(
                  radius: 54,
                  backgroundColor: Colors.white12,
                  child: Icon(
                    _video ? Icons.videocam : Icons.call,
                    size: 48,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  widget.callerName,
                  textAlign: TextAlign.center,
                  style: t.textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _video ? 'Videóhívás' : 'Hanghívás',
                  style: t.textTheme.bodyLarge?.copyWith(color: Colors.white70),
                ),
                const Spacer(),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 24),
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: BigButton(
                          label: 'Elutasítás',
                          icon: Icons.call_end,
                          danger: true,
                          onPressed: _decline,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: BigButton(
                          label: 'Fogadás',
                          icon: Icons.call,
                          onPressed: _accept,
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
