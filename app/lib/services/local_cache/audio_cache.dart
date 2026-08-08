import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../../models/models.dart';
import '../api_client.dart';

/// Disk cache for voice message audio files.
class AudioCache {
  AudioCache._();

  static const maxFiles = 12;
  static const maxCacheBytes = 64 * 1024 * 1024;
  static const maxBytes = 20 * 1024 * 1024;
  static Future<void>? _prefetchInFlight;

  static Future<Directory> _dir() async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/voice_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<File> file(String messageId) async {
    final dir = await _dir();
    return File('${dir.path}/$messageId.m4a');
  }

  static Future<bool> has(String messageId) async {
    try {
      final f = await file(messageId);
      if (!await f.exists()) return false;
      if (await f.length() > maxBytes) {
        await f.delete();
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> put(String messageId, Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > maxBytes) return;
    final f = await file(messageId);
    await f.writeAsBytes(bytes, flush: true);
    await trim(recentIds: {messageId});
  }

  static Future<Uint8List?> read(String messageId) async {
    try {
      final f = await file(messageId);
      if (!await f.exists()) return null;
      if (await f.length() > maxBytes) {
        await f.delete();
        return null;
      }
      return f.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  /// Download and store audio for the newest [keep] messages (files only).
  static Future<void> prefetch(
    ApiClient api,
    List<VoiceMessage> messages, {
    int keep = 3,
  }) {
    final active = _prefetchInFlight;
    if (active != null) return active;

    final future = _prefetch(api, messages, keep: keep);
    _prefetchInFlight = future;
    future.then(
      (_) {
        if (identical(_prefetchInFlight, future)) _prefetchInFlight = null;
      },
      onError: (_, _) {
        if (identical(_prefetchInFlight, future)) _prefetchInFlight = null;
      },
    );
    return future;
  }

  static Future<void> _prefetch(
    ApiClient api,
    List<VoiceMessage> messages, {
    required int keep,
  }) async {
    final newest = messages.length > keep ? messages.sublist(messages.length - keep) : messages;
    for (final m in newest.reversed) {
      try {
        if (m.isCall || m.url == null || m.url!.isEmpty) continue;
        if (await has(m.id)) continue;
        final bytes = await api.downloadAudio(m.url!);
        await put(m.id, bytes);
      } catch (_) {
        // Best-effort cache.
      }
    }
    await trim(recentIds: newest.map((m) => m.id).toSet());
  }

  static Future<void> trim({Set<String> recentIds = const {}}) async {
    try {
      final dir = await _dir();
      final files = await dir.list().where((e) => e is File).cast<File>().toList();
      final entries = <({File file, int bytes, DateTime modified})>[];
      for (final f in files) {
        final stat = await f.stat();
        entries.add((file: f, bytes: stat.size, modified: stat.modified));
      }
      entries.sort((a, b) => b.modified.compareTo(a.modified));

      var kept = 0;
      var total = 0;
      for (final entry in entries) {
        final id = entry.file.uri.pathSegments.last.replaceAll('.m4a', '');
        final keep = (recentIds.contains(id) && entry.bytes <= maxBytes) ||
            (kept < maxFiles && total + entry.bytes <= maxCacheBytes);
        if (keep) {
          kept++;
          total += entry.bytes;
          continue;
        }
        await entry.file.delete();
      }
    } catch (_) {}
  }
}
