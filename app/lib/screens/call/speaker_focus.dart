import 'dart:async';

import 'package:livekit_client/livekit_client.dart';

import 'call_room_lifecycle.dart';

/// Active-speaker highlight with hysteresis (no flicker / jump).
mixin SpeakerFocusMixin on CallRoomLifecycle {
  /// Must keep speaking this long before becoming the focus speaker.
  static const promoteAfter = Duration(milliseconds: 1400);

  /// Current focus stays at least this long before we allow a switch.
  static const holdMin = Duration(milliseconds: 2800);

  /// New speaker must beat current by this audio-level margin.
  static const levelMargin = 0.12;

  String? candidateId;
  DateTime? candidateSince;
  Timer? speakerEvalTimer;
  Timer? speakerUiTimer;

  void disposeSpeakerFocus() {
    speakerEvalTimer?.cancel();
    speakerUiTimer?.cancel();
  }

  @override
  void clearFocusIfParticipant(String identity) {
    if (focusId == identity) {
      focusId = null;
      focusSince = null;
      candidateId = null;
      candidateSince = null;
      speakerEvalTimer?.cancel();
    }
  }

  @override
  void onActiveSpeakers(ActiveSpeakersChangedEvent event) {
    if (!mounted || room == null) return;

    final speakers = event.speakers;
    if (speakers.isEmpty) {
      // Keep focus; clear a candidate that stopped speaking.
      candidateId = null;
      candidateSince = null;
      speakerEvalTimer?.cancel();
      scheduleSpeakerUiRefresh();
      return;
    }

    // Loudest first (SDK already orders this way).
    final top = speakers.first;
    final topId = top.identity;
    final now = DateTime.now();

    if (focusId == null) {
      setState(() {
        focusId = topId;
        focusSince = now;
        candidateId = null;
        candidateSince = null;
      });
      return;
    }

    if (topId == focusId) {
      candidateId = null;
      candidateSince = null;
      speakerEvalTimer?.cancel();
      scheduleSpeakerUiRefresh();
      return;
    }

    Participant? focusP;
    for (final s in speakers) {
      if (s.identity == focusId) {
        focusP = s;
        break;
      }
    }
    final focusLevel = focusP?.audioLevel ?? 0.0;
    final topLevel = top.audioLevel;

    final focusSilent = focusP == null || !focusP.isSpeaking;
    if (!focusSilent && topLevel < focusLevel + levelMargin) {
      scheduleSpeakerUiRefresh();
      return;
    }

    if (candidateId != topId) {
      candidateId = topId;
      candidateSince = now;
      speakerEvalTimer?.cancel();
      speakerEvalTimer = Timer(promoteAfter, tryPromoteCandidate);
    }
    scheduleSpeakerUiRefresh();
  }

  void scheduleSpeakerUiRefresh() {
    if (speakerUiTimer?.isActive ?? false) return;
    speakerUiTimer = Timer(const Duration(milliseconds: 100), () {
      if (mounted) setState(() {});
    });
  }

  void tryPromoteCandidate() {
    if (!mounted) return;
    final cand = candidateId;
    final since = candidateSince;
    final currentFocusSince = focusSince;
    if (cand == null || since == null) return;

    final now = DateTime.now();
    if (now.difference(since) < promoteAfter) return;
    final candidate = room?.getParticipantByIdentity(cand);
    if (candidate == null || !candidate.isSpeaking) {
      candidateId = null;
      candidateSince = null;
      return;
    }
    if (currentFocusSince != null &&
        now.difference(currentFocusSince) < holdMin) {
      final wait = holdMin - now.difference(currentFocusSince);
      speakerEvalTimer?.cancel();
      speakerEvalTimer = Timer(wait, tryPromoteCandidate);
      return;
    }

    if (focusId == cand) return;
    setState(() {
      focusId = cand;
      focusSince = DateTime.now();
      candidateId = null;
      candidateSince = null;
    });
  }
}
