import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/models.dart';
import '../providers/connectivity_provider.dart';

class ApiException implements Exception {
  ApiException(
    this.message, {
    this.statusCode,
    this.softPaywall = false,
    this.needsName = false,
  });
  final String message;
  final int? statusCode;
  final bool softPaywall;
  final bool needsName;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  String? _token;
  String _baseUrl = AppConfig.primaryBaseUrl;

  String? get token => _token;
  String get baseUrl => _baseUrl;
  String get webAccountUrl => AppConfig.webAccountUrlFor(_baseUrl);

  Future<void> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('session_token');
    // Always use canonical host; drop stale workers.dev from older installs
    _baseUrl = AppConfig.primaryBaseUrl;
    await prefs.setString('api_base_url', _baseUrl);
  }

  Future<void> saveSession(String token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('session_token', token);
  }

  Future<void> clearSession() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('session_token');
  }

  Map<String, String> _headers({Map<String, String>? extra, bool json = true}) {
    return {
      if (json) 'Content-Type': 'application/json',
      'X-Client': 'flutter',
      if (_token != null) 'Authorization': 'Bearer $_token',
      ...?extra,
    };
  }

  Future<http.Response> _send(
    Future<http.Response> Function(Uri uri) request, {
    required String path,
    Map<String, String>? query,
  }) async {
    if (!NetStatus.online) {
      throw ApiException('Nincs internet');
    }
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query);
    try {
      return await request(uri).timeout(const Duration(seconds: 8));
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Nem elérhető a szerver. Ellenőrizd az internetet.');
    }
  }

  Future<Map<String, dynamic>> _json(http.Response res) async {
    Map<String, dynamic> body = {};
    if (res.body.isNotEmpty) {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    }
    if (res.statusCode >= 400) {
      throw ApiException(
        body['error'] as String? ?? 'Hiba (${res.statusCode})',
        statusCode: res.statusCode,
        softPaywall: body['softPaywall'] == true,
        needsName: body['needsName'] == true,
      );
    }
    return body;
  }

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
          if (name != null && name.isNotEmpty) 'name': name,
          if (visionAssist != null) 'visionAssist': visionAssist,
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
          if (name != null) 'name': name,
          if (email != null) 'email': email,
          if (visionAssist != null) 'visionAssist': visionAssist,
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

  Future<Uint8List> downloadBytes(String path) async {
    final res = await _send(
      (uri) => _client.get(uri, headers: _headers(json: false)),
      path: path,
    );
    if (res.statusCode >= 400) {
      throw ApiException('Nem sikerült betölteni', statusCode: res.statusCode);
    }
    return res.bodyBytes;
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

  Future<Map<String, dynamic>> getInvite(String token) async {
    final res = await _send(
      (uri) => _client.get(uri, headers: _headers()),
      path: '/api/invites/$token',
    );
    return _json(res);
  }

  Future<Family> acceptInvite(String token) async {
    final res = await _send(
      (uri) => _client.post(uri, headers: _headers()),
      path: '/api/invites/$token/accept',
    );
    final body = await _json(res);
    return Family.fromJson(body['family'] as Map<String, dynamic>);
  }

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
        if (before != null) 'before': before,
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
          if (conversationId != null) 'conversationId': conversationId,
          if (calleeIds != null) 'calleeIds': calleeIds,
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
}
