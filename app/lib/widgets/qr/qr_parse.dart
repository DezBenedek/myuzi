/// Parses MyÜzi user id from QR payload (`…/u/{id}` or raw id).
String? parseQrUserId(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final uri = Uri.tryParse(text);
  if (uri != null) {
    final parts = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final i = parts.indexOf('u');
    if (i >= 0 && i + 1 < parts.length) {
      final id = parts[i + 1];
      if (RegExp(r'^[A-Za-z0-9_-]{8,80}$').hasMatch(id)) return id;
    }
  }
  final m = RegExp(r'(?:^|/)u/([A-Za-z0-9_-]+)').firstMatch(text);
  final pathId = m?.group(1);
  if (pathId != null && pathId.length >= 8 && pathId.length <= 80) return pathId;
  if (RegExp(r'^[A-Za-z0-9_-]{8,80}$').hasMatch(text)) return text;
  return null;
}
