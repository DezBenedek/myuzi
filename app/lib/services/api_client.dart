import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/models.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.softPaywall = false});
  final String message;
  final int? statusCode;
  final bool softPaywall;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  String? _token;

  String? get token => _token;

  Future<void> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('session_token');
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

  Uri _u(String path, [Map<String, String>? query]) =>
      Uri.parse('${AppConfig.apiBaseUrl}$path').replace(queryParameters: query);

  Map<String, String> _headers({Map<String, String>? extra, bool json = true}) {
    final h = <String, String>{
      if (json) 'Content-Type': 'application/json',
      'X-Client': 'flutter',
      if (_token != null) 'Authorization': 'Bearer $_token',
      ...?extra,
    };
    return h;
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
      );
    }
    return body;
  }

  Future<void> startLogin({
    required String name,
    required String email,
    required bool visionAssist,
  }) async {
    final res = await _client.post(
      _u('/api/auth/start'),
      headers: _headers(),
      body: jsonEncode({
        'name': name,
        'email': email,
        'visionAssist': visionAssist,
      }),
    );
    await _json(res);
  }

  Future<User> verifyLogin({required String email, required String code}) async {
    final res = await _client.post(
      _u('/api/auth/verify'),
      headers: _headers(),
      body: jsonEncode({'email': email, 'code': code}),
    );
    final body = await _json(res);
    await saveSession(body['token'] as String);
    return User.fromJson(body['user'] as Map<String, dynamic>);
  }

  Future<User?> me() async {
    if (_token == null) return null;
    try {
      final res = await _client.get(_u('/api/auth/me'), headers: _headers());
      final body = await _json(res);
      return User.fromJson(body['user'] as Map<String, dynamic>);
    } on ApiException {
      await clearSession();
      return null;
    }
  }

  Future<void> logout() async {
    try {
      await _client.post(_u('/api/auth/logout'), headers: _headers());
    } catch (_) {}
    await clearSession();
  }

  Future<User> updateMe({String? name, bool? visionAssist}) async {
    final res = await _client.patch(
      _u('/api/auth/me'),
      headers: _headers(),
      body: jsonEncode({
        if (name != null) 'name': name,
        if (visionAssist != null) 'visionAssist': visionAssist,
      }),
    );
    final body = await _json(res);
    return User.fromJson(body['user'] as Map<String, dynamic>);
  }

  Future<({Family? family, List<FamilyMember> members})> myFamily() async {
    final res = await _client.get(_u('/api/families/mine'), headers: _headers());
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
    final res = await _client.post(
      _u('/api/families'),
      headers: _headers(),
      body: jsonEncode({'name': name}),
    );
    final body = await _json(res);
    return Family.fromJson(body['family'] as Map<String, dynamic>);
  }

  Future<String> createInvite({String? email}) async {
    final res = await _client.post(
      _u('/api/invites'),
      headers: _headers(),
      body: jsonEncode({if (email != null && email.isNotEmpty) 'email': email}),
    );
    final body = await _json(res);
    return (body['invite'] as Map)['url'] as String;
  }

  Future<Map<String, dynamic>> getInvite(String token) async {
    final res = await _client.get(_u('/api/invites/$token'), headers: _headers());
    return _json(res);
  }

  Future<Family> acceptInvite(String token) async {
    final res = await _client.post(
      _u('/api/invites/$token/accept'),
      headers: _headers(),
    );
    final body = await _json(res);
    return Family.fromJson(body['family'] as Map<String, dynamic>);
  }

  Future<({List<ConversationSummary> conversations, List<FamilyMember> people})>
      listConversations() async {
    final res =
        await _client.get(_u('/api/conversations'), headers: _headers());
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
    final res = await _client.post(
      _u('/api/conversations/direct'),
      headers: _headers(),
      body: jsonEncode({'userId': userId}),
    );
    final body = await _json(res);
    return body['conversationId'] as String;
  }

  Future<String> createGroup({
    required String name,
    required List<String> memberIds,
  }) async {
    final res = await _client.post(
      _u('/api/conversations/group'),
      headers: _headers(),
      body: jsonEncode({'name': name, 'memberIds': memberIds}),
    );
    final body = await _json(res);
    return body['conversationId'] as String;
  }

  Future<List<VoiceMessage>> listMessages(String conversationId) async {
    final res = await _client.get(
      _u('/api/messages/$conversationId'),
      headers: _headers(),
    );
    final body = await _json(res);
    return ((body['messages'] as List?) ?? [])
        .map((e) => VoiceMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<VoiceMessage> uploadVoice({
    required String conversationId,
    required Uint8List bytes,
    required String contentType,
    required int durationMs,
  }) async {
    final res = await _client.post(
      _u('/api/messages/$conversationId'),
      headers: _headers(
        json: false,
        extra: {
          'Content-Type': contentType,
          'X-Duration-Ms': '$durationMs',
        },
      ),
      body: bytes,
    );
    final body = await _json(res);
    return VoiceMessage.fromJson({
      ...Map<String, dynamic>.from(body['message'] as Map),
      'senderName': '',
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  Future<Uint8List> downloadAudio(String path) async {
    final res = await _client.get(_u(path), headers: _headers(json: false));
    if (res.statusCode >= 400) {
      throw ApiException('Nem sikerült lejátszani', statusCode: res.statusCode);
    }
    return res.bodyBytes;
  }

  Future<CallSession> startCall({
    String? conversationId,
    List<String>? calleeIds,
    required String callType,
  }) async {
    final res = await _client.post(
      _u('/api/calls/start'),
      headers: _headers(),
      body: jsonEncode({
        if (conversationId != null) 'conversationId': conversationId,
        if (calleeIds != null) 'calleeIds': calleeIds,
        'callType': callType,
      }),
    );
    final body = await _json(res);
    return CallSession.fromJson(body['call'] as Map<String, dynamic>);
  }

  Future<CallSession> joinCall(String callId) async {
    final res = await _client.post(
      _u('/api/calls/$callId/join'),
      headers: _headers(),
    );
    final body = await _json(res);
    return CallSession.fromJson(body['call'] as Map<String, dynamic>);
  }

  Future<void> endCall(String callId) async {
    await _client.post(_u('/api/calls/$callId/end'), headers: _headers());
  }

  Future<List<Map<String, dynamic>>> activeCalls() async {
    final res = await _client.get(_u('/api/calls/active'), headers: _headers());
    final body = await _json(res);
    return ((body['calls'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> registerPushToken({
    required String token,
    required String platform,
  }) async {
    await _client.post(
      _u('/api/devices/push-token'),
      headers: _headers(),
      body: jsonEncode({'token': token, 'platform': platform}),
    );
  }
}
