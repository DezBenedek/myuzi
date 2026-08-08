class CallSession {
  CallSession({
    required this.id,
    required this.roomName,
    required this.callType,
    required this.livekitUrl,
    required this.token,
    required this.status,
    this.mode = 'group',
  });

  final String id;
  final String roomName;
  final String callType;
  final String livekitUrl;
  final String token;
  final String status;
  /// `direct` (1:1) or `group`.
  final String mode;

  bool get isDirect => mode == 'direct';

  factory CallSession.fromJson(Map<String, dynamic> j) => CallSession(
        id: j['id'] as String,
        roomName: j['roomName'] as String,
        callType: j['callType'] as String,
        livekitUrl: j['livekitUrl'] as String,
        token: j['token'] as String,
        status: j['status'] as String? ?? 'ringing',
        mode: (j['mode'] as String?) == 'direct' ? 'direct' : 'group',
      );
}
