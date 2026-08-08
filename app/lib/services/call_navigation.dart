import 'package:go_router/go_router.dart';

import 'api_client.dart';

/// Join a call and open the LiveKit screen via GoRouter (not builder context).
Future<void> joinAndOpenCall({
  required ApiClient api,
  required GoRouter router,
  required String callId,
  String title = 'Hívás',
  bool replace = false,
}) async {
  final id = callId.trim();
  if (id.isEmpty) throw ApiException('Érvénytelen hívás');
  if (!_looksLikeCallId(id)) throw ApiException('Érvénytelen hívás');

  final loc = router.state.matchedLocation;
  if (loc == '/call/$id') return;

  final session = await api.joinCall(id);
  final extra = {
    'livekitUrl': session.livekitUrl,
    'token': session.token,
    'callType': session.callType,
    'mode': session.mode,
    'title': title,
  };
  final path = '/call/${session.id}';
  CallJoinGuard.begin(session.id);
  if (replace) {
    router.go(path, extra: extra);
  } else {
    await router.push(path, extra: extra);
  }
}

bool _looksLikeCallId(String id) =>
    RegExp(r'^[A-Za-z0-9_-]{6,80}$').hasMatch(id);

/// Prevents host from fighting /incoming while CallScreen join is in flight.
class CallJoinGuard {
  CallJoinGuard._();
  static String? inFlightCallId;
  static void begin(String id) => inFlightCallId = id;
  static void end(String id) {
    if (inFlightCallId == id) inFlightCallId = null;
  }
  static bool isJoining(String id) => inFlightCallId == id;
}

/// Queue for cold-start / notification / incoming UI before auth+router are ready.
class PendingCallAction {
  PendingCallAction._();

  static String? ringCallId;
  static String? ringCallerName;
  static String? ringCallType;
  static String? acceptCallId;
  static String? declineCallId;
  static String? dismissCallId;
  static String? conversationId;

  /// Show /incoming screen — not an accept.
  static void setRing(
    String id, {
    String? callerName,
    String? callType,
    String? conversation,
  }) {
    ringCallId = id.trim().isEmpty ? null : id.trim();
    ringCallerName = callerName;
    ringCallType = callType ?? 'audio';
    conversationId = conversation;
    acceptCallId = null;
    declineCallId = null;
    dismissCallId = null;
  }

  /// Explicit Fogadás / user chose to join.
  static void setAccept(String id, {String? conversation}) {
    acceptCallId = id.trim().isEmpty ? null : id.trim();
    declineCallId = null;
    dismissCallId = null;
    ringCallId = null;
    conversationId = conversation;
  }

  /// @deprecated Prefer [setAccept].
  static void setCall(String id, {String? conversation}) =>
      setAccept(id, conversation: conversation);

  static void setDecline(String id) {
    declineCallId = id.trim().isEmpty ? null : id.trim();
    acceptCallId = null;
    dismissCallId = null;
    ringCallId = null;
  }

  static void setDismiss(String id) {
    dismissCallId = id.trim().isEmpty ? null : id.trim();
    acceptCallId = null;
    declineCallId = null;
    ringCallId = null;
  }

  static void setMessage({required String conversationId}) {
    acceptCallId = null;
    declineCallId = null;
    dismissCallId = null;
    ringCallId = null;
    PendingCallAction.conversationId = conversationId;
  }

  static void clear() {
    ringCallId = null;
    ringCallerName = null;
    ringCallType = null;
    acceptCallId = null;
    declineCallId = null;
    dismissCallId = null;
    conversationId = null;
  }
}
