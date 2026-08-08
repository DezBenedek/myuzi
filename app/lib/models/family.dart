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

  bool get isPaid => plan == 'family' || plan == 'family_plus';

  String get planLabel {
    if (plan == 'family_plus') return 'Család+';
    if (plan == 'family') return 'Család';
    return 'Ingyenes';
  }

  String get planSummary {
    if (plan == 'family_plus') {
      return 'Család+ · max $maxMembers fő · 20 perc hang · hívás · csoport';
    }
    if (plan == 'family') {
      return 'Család · max $maxMembers fő · 10 perc hang · hívás · csoport';
    }
    return 'Ingyenes · max $maxMembers fő · 2 perc hang · nincs hívás';
  }

  int get voiceMaxMs {
    if (plan == 'family_plus') return 20 * 60 * 1000;
    if (plan == 'family') return 10 * 60 * 1000;
    return 2 * 60 * 1000;
  }

  factory Family.fromJson(Map<String, dynamic> j) => Family(
        id: j['id'] as String,
        name: j['name'] as String,
        ownerId: j['ownerId'] as String,
        plan: j['plan'] as String? ?? 'none',
        maxMembers: j['maxMembers'] as int? ?? 3,
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
    this.avatarUrl,
  });

  final String id;
  final String name;
  final String email;
  final String role;
  final String? avatarUrl;

  factory FamilyMember.fromJson(Map<String, dynamic> j) => FamilyMember(
        id: j['id'] as String,
        name: j['name'] as String,
        email: j['email'] as String? ?? '',
        role: j['role'] as String? ?? 'member',
        avatarUrl: j['avatarUrl'] as String?,
      );
}
