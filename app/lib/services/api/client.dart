import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../config.dart';
import '../../models/models.dart';
import '../../providers/connectivity_provider.dart';

part 'auth_api.dart';
part 'billing_api.dart';
part 'calls_api.dart';
part 'conversations_api.dart';
part 'devices_api.dart';
part 'families_api.dart';
part 'messages_api.dart';

class ApiException implements Exception {
  ApiException(
    this.message, {
    this.statusCode,
    this.softPaywall = false,
    this.needsName = false,
    this.needsLeaveConfirmation = false,
    this.currentFamilyName,
    this.targetFamilyName,
  });
  final String message;
  final int? statusCode;
  final bool softPaywall;
  final bool needsName;
  final bool needsLeaveConfirmation;
  final String? currentFamilyName;
  final String? targetFamilyName;

  @override
  String toString() => message;
}

/// HTTP core, session, and shared helpers. Domain APIs are mixins on this base.
class ApiClientBase {
  ApiClientBase({http.Client? client}) : _client = client ?? http.Client();

  static const _sessionKey = 'session_token';
  static const _secureStorage = FlutterSecureStorage();

  final http.Client _client;
  String? _token;
  String _baseUrl = AppConfig.primaryBaseUrl;

  String? get token => _token;
  String get baseUrl => _baseUrl;
  String get webAccountUrl => AppConfig.webAccountUrlFor(_baseUrl);

  Future<void> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    _token = await _secureStorage.read(key: _sessionKey);
    if (_token == null) {
      // Migrate tokens written by older versions exactly once.
      final legacyToken = prefs.getString(_sessionKey);
      if (legacyToken != null && legacyToken.isNotEmpty) {
        _token = legacyToken;
        await _secureStorage.write(key: _sessionKey, value: legacyToken);
        await prefs.remove(_sessionKey);
      }
    }
    // Always use canonical host; drop stale workers.dev from older installs
    _baseUrl = AppConfig.primaryBaseUrl;
    await prefs.setString('api_base_url', _baseUrl);
  }

  Future<void> saveSession(String token) async {
    _token = token;
    await _secureStorage.write(key: _sessionKey, value: token);
  }

  Future<void> clearSession() async {
    _token = null;
    await _secureStorage.delete(key: _sessionKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
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
    Duration timeout = const Duration(seconds: 8),
  }) async {
    // Do not hard-block on connectivity_plus (false offline → fake logout).
    // Let the request fail naturally; map errors below.
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query);
    try {
      return await request(uri).timeout(timeout);
    } catch (e) {
      if (e is ApiException) rethrow;
      if (!NetStatus.online) {
        throw ApiException('Nincs internet');
      }
      throw ApiException('Nem elérhető a szerver. Ellenőrizd az internetet.');
    }
  }

  Future<Map<String, dynamic>> _json(http.Response res) async {
    Map<String, dynamic> body = {};
    if (res.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) body = decoded;
      } catch (_) {
        throw ApiException(
          'Érvénytelen szerverválasz',
          statusCode: res.statusCode,
        );
      }
    }
    if (res.statusCode >= 400) {
      throw ApiException(
        body['error'] as String? ?? 'Hiba (${res.statusCode})',
        statusCode: res.statusCode,
        softPaywall: body['softPaywall'] == true,
        needsName: body['needsName'] == true,
        needsLeaveConfirmation: body['needsLeaveConfirmation'] == true,
        currentFamilyName: body['currentFamilyName'] as String?,
        targetFamilyName: body['targetFamilyName'] as String?,
      );
    }
    return body;
  }

  Future<Uint8List> downloadBytes(String path) async {
    final res = await _send(
      (uri) => _client.get(uri, headers: _headers(json: false)),
      path: path,
      timeout: const Duration(seconds: 30),
    );
    if (res.statusCode >= 400) {
      throw ApiException('Nem sikerült betölteni', statusCode: res.statusCode);
    }
    return res.bodyBytes;
  }
}

class ApiClient extends ApiClientBase
    with
        AuthApi,
        BillingApi,
        FamiliesApi,
        ConversationsApi,
        MessagesApi,
        CallsApi,
        DevicesApi {
  ApiClient({super.client});
}
