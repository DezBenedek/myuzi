import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/call_navigation.dart';
import '../services/push_service.dart';
import '../services/realtime_service.dart';

final realtimeProvider = Provider<RealtimeService>((ref) {
  final service = RealtimeService();
  ref.onDispose(service.dispose);
  return service;
});

/// Connects Durable Object WS + FCM when logged in.
/// (No CallStandby FGS — it conflicted with call accept / crashed the app.)
final realtimeLifecycleProvider = Provider<void>((ref) {
  final auth = ref.watch(authProvider);
  final api = ref.watch(apiProvider);
  final realtime = ref.watch(realtimeProvider);

  if (auth.loading) return;
  if (!auth.isLoggedIn) {
    realtime.disconnect();
    PendingCallAction.clear();
    unawaited(PushService.clear());
    return;
  }

  final token = api.token;
  if (token == null || token.isEmpty) return;

  realtime.connect(
    baseUrl: api.baseUrl,
    ticketProvider: () => api.realtimeTicket(),
  );
  unawaited(PushService.syncToken(api));
});
