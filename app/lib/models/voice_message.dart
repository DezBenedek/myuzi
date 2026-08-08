class VoiceMessage {
  VoiceMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.durationMs,
    required this.createdAt,
    this.url,
    this.unread = false,
    this.waveBars = const [],
    this.kind = 'voice',
    this.callId,
    this.callStatus,
    this.callType,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String senderName;
  final int durationMs;
  final String createdAt;
  final String? url;
  final bool unread;
  /// Bar heights 1–20 (empty = generate fallback from id).
  final List<int> waveBars;
  /// `voice` or `call`
  final String kind;
  final String? callId;
  /// ringing | active | missed | ended
  final String? callStatus;
  final String? callType;

  bool get isCall => kind == 'call';

  factory VoiceMessage.fromJson(Map<String, dynamic> j) {
    final raw = j['waveBars'];
    List<int> bars = const [];
    if (raw is List) {
      bars = raw
          .map((e) => (e is num ? e.toInt() : int.tryParse('$e') ?? 1))
          .map((n) => n.clamp(1, 20))
          .toList();
    }
    final kind = j['kind'] as String? ?? 'voice';
    return VoiceMessage(
      id: j['id'] as String,
      conversationId: j['conversationId'] as String,
      senderId: j['senderId'] as String,
      senderName: j['senderName'] as String? ?? '',
      durationMs: j['durationMs'] as int? ?? 0,
      createdAt: j['createdAt'] as String? ?? '',
      url: j['url'] as String?,
      unread: j['unread'] as bool? ?? false,
      waveBars: bars,
      kind: kind,
      callId: j['callId'] as String?,
      callStatus: j['callStatus'] as String?,
      callType: j['callType'] as String?,
    );
  }

  VoiceMessage copyWith({
    bool? unread,
    List<int>? waveBars,
    String? callStatus,
    int? durationMs,
  }) =>
      VoiceMessage(
        id: id,
        conversationId: conversationId,
        senderId: senderId,
        senderName: senderName,
        durationMs: durationMs ?? this.durationMs,
        createdAt: createdAt,
        url: url,
        unread: unread ?? this.unread,
        waveBars: waveBars ?? this.waveBars,
        kind: kind,
        callId: callId,
        callStatus: callStatus ?? this.callStatus,
        callType: callType,
      );
}
