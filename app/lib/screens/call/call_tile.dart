import 'package:livekit_client/livekit_client.dart';

/// Snapshot of a call participant for layout tiles.
class CallTile {
  CallTile({
    required this.identity,
    required this.name,
    required this.isLocal,
    required this.isSpeaking,
    required this.audioLevel,
    this.camera,
  });

  final String identity;
  final String name;
  final bool isLocal;
  final bool isSpeaking;
  final double audioLevel;
  final VideoTrack? camera;

  factory CallTile.fromParticipant(Participant p, {required bool isLocal}) {
    VideoTrack? cam;
    for (final pub in p.videoTrackPublications) {
      if (pub.isScreenShare) continue;
      final track = pub.track;
      if (track is VideoTrack && (isLocal || pub.subscribed)) {
        cam = track;
        break;
      }
    }
    return CallTile(
      identity: p.identity,
      name: p.name.isNotEmpty ? p.name : p.identity,
      isLocal: isLocal,
      isSpeaking: p.isSpeaking,
      audioLevel: p.audioLevel,
      camera: cam,
    );
  }
}
