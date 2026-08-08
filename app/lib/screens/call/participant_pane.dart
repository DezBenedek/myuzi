import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import 'call_tile.dart';

class ParticipantPane extends StatelessWidget {
  const ParticipantPane({
    super.key,
    required this.tile,
    required this.focused,
    required this.showVideo,
    required this.large,
    this.compact = false,
  });

  final CallTile tile;
  final bool focused;
  final bool showVideo;
  final bool large;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final borderColor = focused
        ? const Color(0xFF3DDC97)
        : tile.isSpeaking
            ? const Color(0xFF6BCB9A)
            : Colors.white24;
    final borderWidth = focused ? 3.0 : (tile.isSpeaking ? 2.0 : 1.0);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: const Color(0xFF15241C),
        borderRadius: BorderRadius.circular(compact ? 14 : 18),
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: const Color(0xFF3DDC97).withValues(alpha: 0.28),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (showVideo && tile.camera != null)
            VideoTrackRenderer(
              tile.camera!,
              key: ValueKey(tile.identity),
              fit: VideoViewFit.cover,
            )
          else
            ColoredBox(
              color: const Color(0xFF1A2E24),
              child: Center(
                child: Text(
                  tile.name.isNotEmpty
                      ? tile.name.characters.first.toUpperCase()
                      : '?',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: large ? 64 : 42,
                  ),
                ),
              ),
            ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Row(
              children: [
                if (tile.isSpeaking)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.graphic_eq,
                        color: Color(0xFF3DDC97), size: 16),
                  ),
                Expanded(
                  child: Text(
                    tile.isLocal ? '${tile.name} (te)' : tile.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: compact ? 11 : 13,
                      shadows: [
                        Shadow(blurRadius: 6, color: Colors.black54),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
