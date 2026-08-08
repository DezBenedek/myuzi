import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/call_standby.dart';
import '../services/push_service.dart';
import '../services/realtime_service.dart';

final realtimeProvider = Provider<RealtimeService>((ref) {
  final service = RealtimeService();
  ref.onDispose(service.dispose);
  return service;
});

/// Connects Durable Object WS + Android standby + FCM when logged in.
final realtimeLifecycleProvider = Provider<void>((ref) {
  final auth = ref.watch(authProvider);
  final api = ref.watch(apiProvider);
  final realtime = ref.watch(realtimeProvider);

  if (auth.loading) return;
  if (!auth.isLoggedIn) {
    realtime.disconnect();
    unawaited(CallStandby.stop());
    unawaited(PushService.clear());
    return;
  }

  final token = api.token;
  if (token == null || token.isEmpty) return;

  realtime.connect(baseUrl: api.baseUrl, token: token);
  unawaited(CallStandby.start());
  unawaited(PushService.syncToken(api));
});
