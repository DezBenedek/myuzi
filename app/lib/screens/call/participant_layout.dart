import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'call_tile.dart';
import 'participant_pane.dart';

class ParticipantGrid extends StatelessWidget {
  const ParticipantGrid({
    super.key,
    required this.tiles,
    required this.focusId,
    required this.showVideo,
    required this.wide,
  });

  final List<CallTile> tiles;
  final String? focusId;
  final bool showVideo;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final n = tiles.length;
    // Phone: max 2 columns (stable). Desktop/wide: up to 3 for 5–6 people.
    final cols = n <= 1
        ? 1
        : wide
            ? (n <= 4 ? 2 : 3)
            : 2;
    final rows = (n + cols - 1) ~/ cols;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cellW = (constraints.maxWidth - 10 * (cols - 1)) / cols;
          final cellH =
              (constraints.maxHeight - 10 * (rows - 1)) / math.max(1, rows);
          final aspect = cellW / math.max(120.0, cellH);

          return GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: aspect.clamp(0.55, 1.6),
            ),
            itemCount: n,
            itemBuilder: (_, i) {
              final tile = tiles[i];
              return ParticipantPane(
                tile: tile,
                focused: tile.identity == focusId,
                showVideo: showVideo,
                large: n == 1,
              );
            },
          );
        },
      ),
    );
  }
}

class MobileSpotlight extends StatelessWidget {
  const MobileSpotlight({
    super.key,
    required this.tiles,
    required this.focusId,
    required this.showVideo,
  });

  final List<CallTile> tiles;
  final String? focusId;
  final bool showVideo;

  @override
  Widget build(BuildContext context) {
    var focus = tiles.first;
    for (final tile in tiles) {
      if (tile.identity == focusId) {
        focus = tile;
        break;
      }
    }
    // The strip keeps the stable identity order; only the large view changes.
    final strip =
        tiles.where((tile) => tile.identity != focus.identity).toList();

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ParticipantPane(
              tile: focus,
              focused: true,
              showVideo: showVideo,
              large: true,
            ),
          ),
        ),
        if (strip.isNotEmpty)
          SizedBox(
            height: 112,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              scrollDirection: Axis.horizontal,
              itemCount: strip.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, index) {
                final tile = strip[index];
                return SizedBox(
                  width: 96,
                  child: ParticipantPane(
                    tile: tile,
                    focused: false,
                    showVideo: showVideo,
                    large: false,
                    compact: true,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
