part of 'client.dart';

mixin MessagesApi on ApiClientBase {
  Future<({List<VoiceMessage> messages, List<MemberRead> memberReads})>
      listMessages(
    String conversationId, {
    int limit = 50,
    String? before,
  }) async {
    final res = await _send(
      (uri) => _client.get(uri, headers: _headers()),
      path: '/api/messages/$conversationId',
      query: {
        'limit': '$limit',
        ...?before != null ? {'before': before} : null,
      },
    );
    final body = await _json(res);
    return (
      messages: ((body['messages'] as List?) ?? [])
          .map((e) => VoiceMessage.fromJson(e as Map<String, dynamic>))
          .toList(),
      memberReads: ((body['memberReads'] as List?) ?? [])
          .map((e) => MemberRead.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<void> markConversationRead(String conversationId, {String? at}) async {
    final res = await _send(
      (uri) => _client.post(
        uri,
        headers: _headers(),
        body: jsonEncode({...?at != null ? {'at': at} : null}),
      ),
      path: '/api/messages/$conversationId/read',
    );
    await _json(res);
  }

  Future<void> deleteMessage(String messageId) async {
    final res = await _send(
      (uri) => _client.delete(uri, headers: _headers()),
      path: '/api/messages/item/$messageId',
    );
    await _json(res);
  }

  Future<VoiceMessage> uploadVoice({
    required String conversationId,
    required Uint8List bytes,
    required String contentType,
    required int durationMs,
    required List<int> waveBars,
  }) async {
    final res = await _send(
      (uri) => _client.post(
        uri,
        headers: _headers(
          json: false,
          extra: {
            'Content-Type': contentType,
            'X-Duration-Ms': '$durationMs',
            'X-Wave-Bars': jsonEncode(waveBars),
          },
        ),
        body: bytes,
      ),
      path: '/api/messages/$conversationId',
      timeout: const Duration(seconds: 60),
    );
    final body = await _json(res);
    return VoiceMessage.fromJson({
      ...Map<String, dynamic>.from(body['message'] as Map),
      'senderName': '',
      'createdAt': DateTime.now().toIso8601String(),
      'unread': false,
    });
  }

  Future<Uint8List> downloadAudio(String path) => downloadBytes(path);
}
