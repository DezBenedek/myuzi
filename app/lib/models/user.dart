class User {
  User({
    required this.id,
    required this.email,
    required this.name,
    required this.visionAssist,
    this.avatarUrl,
  });

  final String id;
  final String email;
  final String name;
  final bool visionAssist;
  final String? avatarUrl;

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: j['id'] as String,
        email: j['email'] as String,
        name: j['name'] as String,
        visionAssist: j['visionAssist'] as bool? ?? false,
        avatarUrl: j['avatarUrl'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'name': name,
        'visionAssist': visionAssist,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
      };

  User copyWith({
    String? name,
    bool? visionAssist,
    String? avatarUrl,
    bool clearAvatar = false,
  }) =>
      User(
        id: id,
        email: email,
        name: name ?? this.name,
        visionAssist: visionAssist ?? this.visionAssist,
        avatarUrl: clearAvatar ? null : (avatarUrl ?? this.avatarUrl),
      );
}
