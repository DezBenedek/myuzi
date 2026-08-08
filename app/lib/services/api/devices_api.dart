part of 'client.dart';

mixin DevicesApi on ApiClientBase {
  Future<void> registerPushToken({
    required String token,
    required String platform,
  }) async {
    await _send(
      (uri) => _client.post(
        uri,
        headers: _headers(),
        body: jsonEncode({'token': token, 'platform': platform}),
      ),
      path: '/api/devices/push-token',
    );
  }

  Future<String> realtimeTicket() async {
    final res = await _send(
      (uri) => _client.post(uri, headers: _headers(), body: '{}'),
      path: '/api/realtime/ticket',
    );
    final body = await _json(res);
    final ticket = body['ticket'] as String?;
    if (ticket == null || ticket.isEmpty) {
      throw ApiException('Realtime ticket hiányzik');
    }
    return ticket;
  }
}
