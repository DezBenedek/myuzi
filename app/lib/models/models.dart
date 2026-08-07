class User {
  User({
    required this.id,
    required this.email,
    required this.name,
    required this.visionAssist,
  });

  final String id;
  final String email;
  final String name;
  final bool visionAssist;

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: j['id'] as String,
        email: j['email'] as String,
        name: j['name'] as String,
        visionAssist: j['visionAssist'] as bool? ?? false,
      );

  User copyWith({String? name, bool? visionAssist}) => User(
        id: id,
        email: email,
        name: name ?? this.name,
        visionAssist: visionAssist ?? this.visionAssist,
      );
}

class Family {
  Family({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.plan,
    required this.maxMembers,
    this.role,
    this.stripeStatus,
  });

  final String id;
  final String name;
  final String ownerId;
  final String plan;
  final int maxMembers;
  final String? role;
  final String? stripeStatus;

  factory Family.fromJson(Map<String, dynamic> j) => Family(
        id: j['id'] as String,
        name: j['name'] as String,
        ownerId: j['ownerId'] as String,
        plan: j['plan'] as String? ?? 'none',
        maxMembers: j['maxMembers'] as int? ?? 6,
        role: j['role'] as String?,
        stripeStatus: j['stripeStatus'] as String?,
      );
}

class FamilyMember {
  FamilyMember({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
  });

  final String id;
  final String name;
  final String email;
  final String role;

  factory FamilyMember.fromJson(Map<String, dynamic> j) => FamilyMember(
        id: j['id'] as String,
        name: j['name'] as String,
        email: j['email'] as String,
        role: j['role'] as String? ?? 'member',
      );
}

class ConversationSummary {
  ConversationSummary({
    required this.id,
    required this.type,
    required this.name,
    required this.memberCount,
    this.lastMessageAt,
    required this.members,
  });

  final String id;
  final String type;
  final String name;
  final int memberCount;
  final String? lastMessageAt;
  final List<FamilyMember> members;

  factory ConversationSummary.fromJson(Map<String, dynamic> j) =>
      ConversationSummary(
        id: j['id'] as String,
        type: j['type'] as String,
        name: j['name'] as String? ?? 'Beszélgetés',
        memberCount: j['memberCount'] as int? ?? 0,
        lastMessageAt: j['lastMessageAt'] as String?,
        members: ((j['members'] as List?) ?? [])
            .map((e) => FamilyMember.fromJson({
                  ...Map<String, dynamic>.from(e as Map),
                  'role': 'member',
                }))
            .toList(),
      );
}

class VoiceMessage {
  VoiceMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.durationMs,
    required this.createdAt,
    required this.url,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String senderName;
  final int durationMs;
  final String createdAt;
  final String url;

  factory VoiceMessage.fromJson(Map<String, dynamic> j) => VoiceMessage(
        id: j['id'] as String,
        conversationId: j['conversationId'] as String,
        senderId: j['senderId'] as String,
        senderName: j['senderName'] as String? ?? '',
        durationMs: j['durationMs'] as int? ?? 0,
        createdAt: j['createdAt'] as String? ?? '',
        url: j['url'] as String,
      );
}

class CallSession {
  CallSession({
    required this.id,
    required this.roomName,
    required this.callType,
    required this.livekitUrl,
    required this.token,
    required this.status,
  });

  final String id;
  final String roomName;
  final String callType;
  final String livekitUrl;
  final String token;
  final String status;

  factory CallSession.fromJson(Map<String, dynamic> j) => CallSession(
        id: j['id'] as String,
        roomName: j['roomName'] as String,
        callType: j['callType'] as String,
        livekitUrl: j['livekitUrl'] as String,
        token: j['token'] as String,
        status: j['status'] as String? ?? 'ringing',
      );
}
