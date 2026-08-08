part of 'client.dart';

mixin ConversationsApi on ApiClientBase {
  Future<({List<ConversationSummary> conversations, List<FamilyMember> people})>
      listConversations() async {
    final res = await _send(
      (uri) => _client.get(uri, headers: _headers()),
      path: '/api/conversations',
    );
    final body = await _json(res);
    return (
      conversations: ((body['conversations'] as List?) ?? [])
          .map((e) => ConversationSummary.fromJson(e as Map<String, dynamic>))
          .toList(),
      people: ((body['familyMembers'] as List?) ?? [])
          .map((e) => FamilyMember.fromJson({
                ...Map<String, dynamic>.from(e as Map),
              }))
          .toList(),
    );
  }

  Future<String> openDirect(String userId) async {
    final res = await _send(
      (uri) => _client.post(
        uri,
        headers: _headers(),
        body: jsonEncode({'userId': userId}),
      ),
      path: '/api/conversations/direct',
    );
    final body = await _json(res);
    return body['conversationId'] as String;
  }

  /// Opens DM if email is a family member; otherwise invites them (paid).
  Future<({String? conversationId, String? inviteUrl, String? message})>
      openDirectByEmail(String email) async {
    final res = await _send(
      (uri) => _client.post(
        uri,
        headers: _headers(),
        body: jsonEncode({'email': email}),
      ),
      path: '/api/conversations/direct-by-email',
    );
    final body = await _json(res);
    return (
      conversationId: body['conversationId'] as String?,
      inviteUrl: body['inviteUrl'] as String?,
      message: body['message'] as String?,
    );
  }

  Future<String> createGroup({
    required String name,
    required List<String> memberIds,
  }) async {
    final res = await _send(
      (uri) => _client.post(
        uri,
        headers: _headers(),
        body: jsonEncode({'name': name, 'memberIds': memberIds}),
      ),
      path: '/api/conversations/group',
    );
    final body = await _json(res);
    return body['conversationId'] as String;
  }

  Future<void> pinConversation(String conversationId) async {
    final res = await _send(
      (uri) => _client.post(uri, headers: _headers()),
      path: '/api/conversations/$conversationId/pin',
    );
    await _json(res);
  }

  Future<void> unpinConversation(String conversationId) async {
    final res = await _send(
      (uri) => _client.delete(uri, headers: _headers(json: false)),
      path: '/api/conversations/$conversationId/pin',
    );
    await _json(res);
  }
}
