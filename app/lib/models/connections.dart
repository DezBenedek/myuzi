class FamilyConnection {
  const FamilyConnection({
    required this.id,
    required this.familyId,
    required this.familyName,
    required this.ownerId,
    required this.ownerName,
    required this.ownerEmail,
    required this.createdAt,
  });

  final String id;
  final String familyId;
  final String familyName;
  final String ownerId;
  final String ownerName;
  final String ownerEmail;
  final DateTime createdAt;

  factory FamilyConnection.fromJson(Map<String, dynamic> json) {
    return FamilyConnection(
      id: json['id'] as String? ?? '',
      familyId: json['familyId'] as String? ?? '',
      familyName: json['familyName'] as String? ?? '',
      ownerId: json['ownerId'] as String? ?? '',
      ownerName: json['ownerName'] as String? ?? '',
      ownerEmail: json['ownerEmail'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class FamilyConnectionInvite {
  const FamilyConnectionInvite({
    required this.id,
    required this.token,
    required this.familyId,
    required this.familyName,
    required this.invitedByName,
    required this.invitedByEmail,
    required this.expiresAt,
  });

  final String id;
  final String token;
  final String familyId;
  final String familyName;
  final String invitedByName;
  final String invitedByEmail;
  final DateTime expiresAt;

  factory FamilyConnectionInvite.fromJson(Map<String, dynamic> json) {
    return FamilyConnectionInvite(
      id: json['id'] as String? ?? '',
      token: json['token'] as String? ?? '',
      familyId: json['familyId'] as String? ?? '',
      familyName: json['familyName'] as String? ?? '',
      invitedByName: json['invitedByName'] as String? ?? '',
      invitedByEmail: json['invitedByEmail'] as String? ?? '',
      expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class NearbyPerson {
  const NearbyPerson({
    required this.id,
    required this.name,
    required this.email,
    required this.avatarUrl,
    required this.familyId,
    required this.familyName,
    required this.connectionId,
  });

  final String id;
  final String name;
  final String email;
  final String? avatarUrl;
  final String? familyId;
  final String? familyName;
  final String? connectionId;

  factory NearbyPerson.fromJson(Map<String, dynamic> json) {
    return NearbyPerson(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String?,
      familyId: json['familyId'] as String?,
      familyName: json['familyName'] as String?,
      connectionId: json['connectionId'] as String?,
    );
  }
}

class NearbyRequest {
  const NearbyRequest({
    required this.id,
    required this.status,
    required this.incoming,
    required this.user,
  });

  final String id;
  final String status;
  final bool incoming;
  final NearbyPerson user;

  factory NearbyRequest.fromJson(Map<String, dynamic> json) {
    return NearbyRequest(
      id: json['id'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      incoming: json['incoming'] == true,
      user: NearbyPerson.fromJson(
        Map<String, dynamic>.from(json['user'] as Map? ?? {}),
      ),
    );
  }
}
