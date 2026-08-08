import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/local_cache.dart';

/// Small authenticated avatar (Bearer-protected R2 image).
class UserAvatar extends ConsumerStatefulWidget {
  const UserAvatar({
    super.key,
    required this.name,
    this.avatarUrl,
    this.userId,
    this.radius = 22,
    this.highlight = false,
  });

  final String name;
  final String? avatarUrl;
  final String? userId;
  final double radius;
  final bool highlight;

  @override
  ConsumerState<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends ConsumerState<UserAvatar> {
  Uint8List? _bytes;
  String? _loadedFor;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarUrl != widget.avatarUrl ||
        oldWidget.userId != widget.userId) {
      _loadGeneration++;
      _bytes = null;
      _loadedFor = null;
      _load();
    }
  }

  String? get _cacheId {
    if (widget.userId != null && widget.userId!.isNotEmpty) {
      return widget.userId;
    }
    final url = widget.avatarUrl;
    if (url == null) return null;
    final parts = url.split('/');
    final i = parts.indexOf('users');
    if (i >= 0 && i + 1 < parts.length) return parts[i + 1];
    return null;
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final url = widget.avatarUrl;
    final cacheId = _cacheId;
    if (url == null || url.isEmpty || cacheId == null) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _bytes = null;
          _loadedFor = null;
        });
      }
      return;
    }
    if (_loadedFor == url && _bytes != null) return;

    final cached = await LocalCache.loadAvatarBytes(cacheId);
    if (cached != null && mounted && generation == _loadGeneration) {
      setState(() {
        _bytes = cached;
        _loadedFor = url;
      });
    }

    try {
      final bytes = await ref.read(apiProvider).downloadBytes(url);
      if (generation != _loadGeneration) return;
      await LocalCache.putAvatarBytes(cacheId, bytes);
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _bytes = bytes;
          _loadedFor = url;
        });
      }
    } catch (_) {
      // Keep cached / initials.
    }
  }

  /// Theme-aware placeholder colors (works in light + dark).
  (Color bg, Color fg) _placeholderColors(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final seed = widget.name.hashCode;
    // A few muted brand-tinted hues so avatars differ but stay readable.
    const lightBgs = [
      Color(0xFFD9F2E6),
      Color(0xFFD6EAE3),
      Color(0xFFE2F0E8),
      Color(0xFFCFE8DC),
    ];
    const darkBgs = [
      Color(0xFF2A3D34),
      Color(0xFF243830),
      Color(0xFF314840),
      Color(0xFF1F332A),
    ];
    final bgs = dark ? darkBgs : lightBgs;
    var bg = bgs[seed.abs() % bgs.length];
    if (widget.highlight) {
      bg = dark ? const Color(0xFF3D6B55) : const Color(0xFFB8E6D0);
    }
    final fg = dark ? const Color(0xFFE8F5EE) : const Color(0xFF12261C);
    return (bg, fg);
  }

  @override
  Widget build(BuildContext context) {
    final initial =
        widget.name.isNotEmpty ? widget.name.characters.first.toUpperCase() : '?';
    final (bg, fg) = _placeholderColors(context);

    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: bg,
      foregroundColor: fg,
      backgroundImage: _bytes != null ? MemoryImage(_bytes!) : null,
      child: _bytes == null
          ? Text(
              initial,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w700,
                fontSize: widget.radius * 0.85,
              ),
            )
          : null,
    );
  }
}
