import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Disk cache for profile avatars.
class AvatarCache {
  AvatarCache._();

  static const maxBytes = 1024 * 1024;
  static const maxFiles = 40;
  static const maxCacheBytes = 32 * 1024 * 1024;

  static Future<Directory> _dir() async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/avatar_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<File> file(String userId) async {
    final dir = await _dir();
    return File('${dir.path}/$userId.bin');
  }

  static Future<Uint8List?> loadBytes(String userId) async {
    try {
      final f = await file(userId);
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

  static Future<void> putBytes(String userId, Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > maxBytes) return;
    final f = await file(userId);
    await f.writeAsBytes(bytes, flush: true);
    await trim();
  }

  static Future<void> clear(String userId) async {
    final f = await file(userId);
    if (await f.exists()) await f.delete();
  }

  static Future<void> trim() async {
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
        if (kept < maxFiles && total + entry.bytes <= maxCacheBytes) {
          kept++;
          total += entry.bytes;
        } else {
          await entry.file.delete();
        }
      }
    } catch (_) {}
  }
}
