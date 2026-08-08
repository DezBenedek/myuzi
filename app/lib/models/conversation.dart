import 'family.dart';

class ConversationSummary {
  ConversationSummary({
    required this.id,
    required this.type,
    required this.name,
    required this.memberCount,
    this.lastMessageAt,
    this.lastSenderName,
    this.avatarUrl,
    this.pinned = false,
    required this.members,
    this.unreadCount = 0,
  });

  final String id;
  final String type;
  final String name;
  final int memberCount;
  final String? lastMessageAt;
  final String? lastSenderName;
  final String? avatarUrl;
  final bool pinned;
  final List<FamilyMember> members;
  final int unreadCount;

  bool get isGroup => type == 'group';

  factory ConversationSummary.fromJson(Map<String, dynamic> j) =>
      ConversationSummary(
        id: j['id'] as String,
        type: j['type'] as String,
        name: j['name'] as String? ?? 'Beszélgetés',
        memberCount: j['memberCount'] as int? ?? 0,
        lastMessageAt: j['lastMessageAt'] as String?,
        lastSenderName: j['lastSenderName'] as String?,
        avatarUrl: j['avatarUrl'] as String?,
        pinned: j['pinned'] == true,
        unreadCount: j['unreadCount'] as int? ?? 0,
        members: ((j['members'] as List?) ?? [])
            .map((e) {
              final member = Map<String, dynamic>.from(e as Map);
              return FamilyMember.fromJson({
                ...member,
                'role': member['role'] ?? 'member',
              });
            })
            .toList(),
      );
}

class MemberRead {
  MemberRead({
    required this.userId,
    required this.name,
    this.avatarUrl,
    this.lastReadAt,
  });

  final String userId;
  final String name;
  final String? avatarUrl;
  final String? lastReadAt;

  factory MemberRead.fromJson(Map<String, dynamic> j) => MemberRead(
        userId: j['userId'] as String,
        name: j['name'] as String? ?? '',
        avatarUrl: j['avatarUrl'] as String?,
        lastReadAt: j['lastReadAt'] as String?,
      );
}
