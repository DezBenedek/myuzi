import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../router.dart';
import '../services/app_notify.dart';
import '../services/call_lock_ui.dart';
import '../services/call_navigation.dart';
import '../services/incoming_call_presenter.dart';
import '../theme/app_theme.dart';
import '../widgets/user_avatar.dart';

/// Classic phone-style full-screen incoming call.
class IncomingCallScreen extends ConsumerStatefulWidget {
  const IncomingCallScreen({
    super.key,
    required this.callId,
    required this.callerName,
    required this.callType,
    this.callerUserId,
    this.callerAvatarUrl,
  });

  final String callId;
  final String callerName;
  final String callType;
  final String? callerUserId;
  final String? callerAvatarUrl;

  @override
  ConsumerState<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends ConsumerState<IncomingCallScreen>
    with SingleTickerProviderStateMixin {
  bool _busy = false;
  late final AnimationController _pulse;

  bool get _video => widget.callType == 'video';

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    unawaited(CallLockUi.setIncomingCallUi(true));
    unawaited(IncomingCallPresenter.onFullScreenShown(widget.callId));
    unawaited(AppNotify.startCallRingtone());
  }

  @override
  void dispose() {
    _pulse.dispose();
    unawaited(CallLockUi.setIncomingCallUi(false));
    super.dispose();
  }

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    CallJoinGuard.begin(widget.callId);
    await IncomingCallPresenter.dismiss(widget.callId);
    await CallLockUi.setIncomingCallUi(false);
    if (!mounted) return;
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
    await CallLockUi.setIncomingCallUi(false);
    try {
      await ref.read(apiProvider).declineCall(widget.callId);
    } catch (_) {}
    if (!mounted) return;
    ref.read(routerProvider).go('/');
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;

    return PopScope(
      canPop: !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          unawaited(AppNotify.stopCallRingtone());
          unawaited(CallLockUi.setIncomingCallUi(false));
        }
      },
      child: Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF16241E),
                Color(0xFF0E1814),
                Color(0xFF0A1210),
              ],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(28, 36, 28, 28 + bottom * 0.25),
              child: Column(
                children: [
                  Text(
                    'Bejövő hívás',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(flex: 2),
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, child) {
                      final t = Curves.easeInOut.transform(_pulse.value);
                      return Container(
                        padding: EdgeInsets.all(10 + t * 4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.brand.withValues(alpha: 0.10 + t * 0.06),
                        ),
                        child: child,
                      );
                    },
                    child: UserAvatar(
                      name: widget.callerName,
                      userId: widget.callerUserId,
                      avatarUrl: widget.callerAvatarUrl,
                      radius: 70,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    widget.callerName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _video ? 'Videóhívás' : 'Hanghívás',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const Spacer(flex: 3),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 36),
                      child: CircularProgressIndicator(
                        color: Colors.white54,
                        strokeWidth: 2.5,
                      ),
                    )
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _RoundCallAction(
                          color: AppTheme.danger,
                          icon: Icons.call_end_rounded,
                          label: 'Elutasítás',
                          onTap: _decline,
                        ),
                        _RoundCallAction(
                          color: AppTheme.brand,
                          icon: Icons.call_rounded,
                          label: 'Fogadás',
                          onTap: _accept,
                        ),
                      ],
                    ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundCallAction extends StatelessWidget {
  const _RoundCallAction({
    required this.color,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 72,
              height: 72,
              child: Icon(icon, color: Colors.white, size: 32),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
