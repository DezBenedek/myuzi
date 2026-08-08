part of 'client.dart';

mixin FamiliesApi on ApiClientBase {
  Future<({Family? family, List<FamilyMember> members})> myFamily() async {
    final res = await _send(
      (uri) => _client.get(uri, headers: _headers()),
      path: '/api/families/mine',
    );
    final body = await _json(res);
    final familyJson = body['family'];
    return (
      family: familyJson == null
          ? null
          : Family.fromJson(familyJson as Map<String, dynamic>),
      members: ((body['members'] as List?) ?? [])
          .map((e) => FamilyMember.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<Family> createFamily(String name) async {
    final res = await _send(
      (uri) => _client.post(
        uri,
        headers: _headers(),
        body: jsonEncode({'name': name}),
      ),
      path: '/api/families',
    );
    final body = await _json(res);
    return Family.fromJson(body['family'] as Map<String, dynamic>);
  }

  Future<Family> renameFamily({
    required String familyId,
    required String name,
  }) async {
    final res = await _send(
      (uri) => _client.patch(
        uri,
        headers: _headers(),
        body: jsonEncode({'name': name}),
      ),
      path: '/api/families/$familyId',
    );
    final body = await _json(res);
    return Family.fromJson(body['family'] as Map<String, dynamic>);
  }

  Future<void> removeFamilyMember({
    required String familyId,
    required String userId,
  }) async {
    final res = await _send(
      (uri) => _client.delete(uri, headers: _headers(json: false)),
      path: '/api/families/$familyId/members/$userId',
    );
    await _json(res);
  }

  Future<String> createInvite({String? email}) async {
    final res = await _send(
      (uri) => _client.post(
        uri,
        headers: _headers(),
        body: jsonEncode({if (email != null && email.isNotEmpty) 'email': email}),
      ),
      path: '/api/invites',
    );
    final body = await _json(res);
    return (body['invite'] as Map)['url'] as String;
  }

  Future<({String url, String userId, String name})> myQr() async {
    final res = await _send(
      (uri) => _client.get(uri, headers: _headers()),
      path: '/api/users/me/qr',
    );
    final body = await _json(res);
    return (
      url: body['url'] as String,
      userId: body['userId'] as String,
      name: body['name'] as String? ?? '',
    );
  }

  Future<Map<String, dynamic>> userCard(String userId) async {
    final res = await _send(
      (uri) => _client.get(uri, headers: _headers()),
      path: '/api/users/$userId/card',
    );
    return _json(res);
  }

  Future<({String message, bool targetHasFamily, String? targetFamilyName, String targetName})>
      inviteUserById(String userId) async {
    final res = await _send(
      (uri) => _client.post(
        uri,
        headers: _headers(),
        body: jsonEncode({'userId': userId}),
      ),
      path: '/api/invites/user',
    );
    final body = await _json(res);
    final invite = body['invite'] as Map<String, dynamic>? ?? {};
    return (
      message: body['message'] as String? ?? 'Meghívó elküldve',
      targetHasFamily: invite['targetHasFamily'] == true,
      targetFamilyName: invite['targetFamilyName'] as String?,
      targetName: invite['targetName'] as String? ?? '',
    );
  }

  Future<List<Map<String, dynamic>>> inviteInbox() async {
    final res = await _send(
      (uri) => _client.get(uri, headers: _headers()),
      path: '/api/invites/inbox',
    );
    final body = await _json(res);
    return ((body['invites'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Map<String, dynamic>> getInvite(String token) async {
    final res = await _send(
      (uri) => _client.get(uri, headers: _headers()),
      path: '/api/invites/$token',
    );
    return _json(res);
  }

  Future<Family> acceptInvite(String token, {bool confirmLeave = false}) async {
    final res = await _send(
      (uri) => _client.post(
        uri,
        headers: _headers(),
        body: jsonEncode({'confirmLeave': confirmLeave}),
      ),
      path: '/api/invites/$token/accept',
    );
    final body = await _json(res);
    return Family.fromJson(body['family'] as Map<String, dynamic>);
  }
}
