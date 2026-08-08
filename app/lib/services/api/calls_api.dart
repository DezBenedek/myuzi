part of 'client.dart';

mixin CallsApi on ApiClientBase {
  Future<CallSession> startCall({
    String? conversationId,
    List<String>? calleeIds,
    required String callType,
  }) async {
    final res = await _send(
      (uri) => _client.post(
        uri,
        headers: _headers(),
        body: jsonEncode({
          ...?conversationId != null ? {'conversationId': conversationId} : null,
          ...?calleeIds != null ? {'calleeIds': calleeIds} : null,
          'callType': callType,
        }),
      ),
      path: '/api/calls/start',
    );
    final body = await _json(res);
    return CallSession.fromJson(body['call'] as Map<String, dynamic>);
  }

  Future<CallSession> joinCall(String callId) async {
    final res = await _send(
      (uri) => _client.post(uri, headers: _headers()),
      path: '/api/calls/$callId/join',
    );
    final body = await _json(res);
    return CallSession.fromJson(body['call'] as Map<String, dynamic>);
  }

  Future<void> endCall(String callId) async {
    await _send(
      (uri) => _client.post(uri, headers: _headers()),
      path: '/api/calls/$callId/end',
    );
  }

  Future<void> leaveCall(String callId) async {
    await _send(
      (uri) => _client.post(uri, headers: _headers()),
      path: '/api/calls/$callId/leave',
    );
  }

  Future<void> declineCall(String callId) async {
    await _send(
      (uri) => _client.post(uri, headers: _headers()),
      path: '/api/calls/$callId/decline',
    );
  }

  Future<List<Map<String, dynamic>>> activeCalls() async {
    final res = await _send(
      (uri) => _client.get(uri, headers: _headers()),
      path: '/api/calls/active',
    );
    final body = await _json(res);
    return ((body['calls'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }
}
