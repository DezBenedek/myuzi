part of 'client.dart';

mixin ConnectionsApi on ApiClientBase {
  Future<({
    List<FamilyConnection> connections,
    List<FamilyConnectionInvite> incoming,
  })> familyConnections() async {
    final res = await _send(
      (uri) => _client.get(uri, headers: _headers()),
      path: '/api/connections',
    );
    final body = await _json(res);
    return (
      connections: ((body['connections'] as List?) ?? [])
          .whereType<Map>()
          .map((item) => FamilyConnection.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      incoming: ((body['incoming'] as List?) ?? [])
          .whereType<Map>()
          .map((item) => FamilyConnectionInvite.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList(),
    );
  }

  Future<({String url, String targetFamilyName})> inviteFamilyOwner(
    String targetEmail,
  ) async {
    final res = await _send(
      (uri) => _client.post(
        uri,
        headers: _headers(),
        body: jsonEncode({'targetEmail': targetEmail}),
      ),
      path: '/api/connections/invite',
    );
    final body = await _json(res);
    final invite = Map<String, dynamic>.from(body['invite'] as Map? ?? {});
    return (
      url: invite['url'] as String? ?? '',
      targetFamilyName: invite['targetFamilyName'] as String? ?? '',
    );
  }

  Future<Map<String, dynamic>> getFamilyConnectionInvite(String token) async {
    final res = await _send(
      (uri) => _client.get(uri, headers: _headers()),
      path: '/api/connections/invite/$token',
    );
    return _json(res);
  }

  Future<void> acceptFamilyConnectionInvite(String token) async {
    final res = await _send(
      (uri) => _client.post(
        uri,
        headers: _headers(),
        body: jsonEncode({}),
      ),
      path: '/api/connections/invite/$token/accept',
    );
    await _json(res);
  }

  Future<void> revokeFamilyConnection(String connectionId) async {
    final res = await _send(
      (uri) => _client.delete(uri, headers: _headers(json: false)),
      path: '/api/connections/$connectionId',
    );
    await _json(res);
  }

  Future<List<NearbyPerson>> nearbyPeople({String query = ''}) async {
    final res = await _send(
      (uri) => _client.get(uri, headers: _headers()),
      path: '/api/connections/nearby',
      query: {'q': query},
    );
    final body = await _json(res);
    return ((body['people'] as List?) ?? [])
        .whereType<Map>()
        .map((item) => NearbyPerson.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<List<NearbyPerson>> matchContactEmails(List<String> emails) async {
    final res = await _send(
      (uri) => _client.post(
        uri,
        headers: _headers(),
        body: jsonEncode({'emails': emails}),
      ),
      path: '/api/connections/nearby/contacts',
    );
    final body = await _json(res);
    return ((body['people'] as List?) ?? [])
        .whereType<Map>()
        .map((item) => NearbyPerson.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<void> requestNearbyConnection(String userId) async {
    final res = await _send(
      (uri) => _client.post(
        uri,
        headers: _headers(),
        body: jsonEncode({}),
      ),
      path: '/api/connections/nearby/$userId/request',
    );
    await _json(res);
  }

  Future<List<NearbyRequest>> nearbyRequests() async {
    final res = await _send(
      (uri) => _client.get(uri, headers: _headers()),
      path: '/api/connections/nearby/requests',
    );
    final body = await _json(res);
    return ((body['requests'] as List?) ?? [])
        .whereType<Map>()
        .map((item) => NearbyRequest.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<void> acceptNearbyRequest(String requestId) async {
    final res = await _send(
      (uri) => _client.post(
        uri,
        headers: _headers(),
        body: jsonEncode({}),
      ),
      path: '/api/connections/nearby/requests/$requestId/accept',
    );
    await _json(res);
  }

  Future<void> setContactDiscoverability(bool enabled) async {
    final res = await _send(
      (uri) => _client.patch(
        uri,
        headers: _headers(),
        body: jsonEncode({'enabled': enabled}),
      ),
      path: '/api/connections/nearby/discoverability',
    );
    await _json(res);
  }
}
