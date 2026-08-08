part of 'client.dart';

mixin AuthApi on ApiClientBase {
  Future<bool> startLogin({
    required String email,
    required bool visionAssist,
  }) async {
    final res = await _send(
      (uri) => _client.post(
        uri,
        headers: _headers(),
        body: jsonEncode({
          'email': email,
          'visionAssist': visionAssist,
        }),
      ),
      path: '/api/auth/start',
    );
    final body = await _json(res);
    return body['isNew'] == true;
  }

  Future<User> verifyLogin({
    required String email,
    required String code,
    String? name,
    bool? visionAssist,
  }) async {
    final res = await _send(
      (uri) => _client.post(
        uri,
        headers: _headers(),
        body: jsonEncode({
          'email': email,
          'code': code,
          ...?name != null && name.isNotEmpty ? {'name': name} : null,
          ...?visionAssist != null ? {'visionAssist': visionAssist} : null,
        }),
      ),
      path: '/api/auth/verify',
    );
    final body = await _json(res);
    await saveSession(body['token'] as String);
    return User.fromJson(body['user'] as Map<String, dynamic>);
  }

  Future<User?> me() async {
    if (_token == null) return null;
    try {
      final res = await _send(
        (uri) => _client.get(uri, headers: _headers()),
        path: '/api/auth/me',
      );
      final body = await _json(res);
      return User.fromJson(body['user'] as Map<String, dynamic>);
    } on ApiException catch (e) {
      // Only an invalid/expired session (401) clears login — never network blips.
      if (e.statusCode == 401) {
        await clearSession();
        return null;
      }
      rethrow;
    }
  }

  Future<void> logout() async {
    try {
      await _send(
        (uri) => _client.post(uri, headers: _headers()),
        path: '/api/auth/logout',
      );
    } catch (_) {}
    await clearSession();
  }

  Future<User> updateMe({String? name, String? email, bool? visionAssist}) async {
    final res = await _send(
      (uri) => _client.patch(
        uri,
        headers: _headers(),
        body: jsonEncode({
          ...?name != null ? {'name': name} : null,
          ...?email != null ? {'email': email} : null,
          ...?visionAssist != null ? {'visionAssist': visionAssist} : null,
        }),
      ),
      path: '/api/auth/me',
    );
    final body = await _json(res);
    return User.fromJson(body['user'] as Map<String, dynamic>);
  }

  Future<String> createWebAccountLink() async {
    final res = await _send(
      (uri) => _client.post(uri, headers: _headers()),
      path: '/api/auth/web-link',
    );
    final body = await _json(res);
    return body['url'] as String;
  }

  Future<User> uploadAvatar({
    required Uint8List bytes,
    required String contentType,
  }) async {
    final res = await _send(
      (uri) => _client.post(
        uri,
        headers: _headers(
          json: false,
          extra: {'Content-Type': contentType},
        ),
        body: bytes,
      ),
      path: '/api/auth/avatar',
    );
    final body = await _json(res);
    return User.fromJson(body['user'] as Map<String, dynamic>);
  }

  Future<User> deleteAvatar() async {
    final res = await _send(
      (uri) => _client.delete(uri, headers: _headers(json: false)),
      path: '/api/auth/avatar',
    );
    final body = await _json(res);
    return User.fromJson(body['user'] as Map<String, dynamic>);
  }
}
