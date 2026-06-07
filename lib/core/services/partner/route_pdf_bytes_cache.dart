import 'dart:typed_data';

/// Midlertidig cache av PDF-bytes (samme økt) — unngår re-nedlasting ved forhåndsvisning.
class RoutePdfBytesCache {
  RoutePdfBytesCache._();

  static final Map<String, Uint8List> _byShareId = {};
  static final Map<String, Uint8List> _byPath = {};

  static void putShare(String shareId, Uint8List bytes) {
    if (shareId.isEmpty || bytes.isEmpty) return;
    _byShareId[shareId] = bytes;
  }

  static void putPath(String storagePath, Uint8List bytes) {
    final key = storagePath.trim();
    if (key.isEmpty || bytes.isEmpty) return;
    _byPath[key] = bytes;
  }

  static Uint8List? forShare(String? shareId, String? storagePath) {
    if (shareId != null && shareId.isNotEmpty) {
      final hit = _byShareId[shareId];
      if (hit != null && hit.isNotEmpty) return hit;
    }
    final path = storagePath?.trim() ?? '';
    if (path.isNotEmpty) {
      final hit = _byPath[path];
      if (hit != null && hit.isNotEmpty) return hit;
    }
    return null;
  }

  static void removeShare(String shareId) {
    _byShareId.remove(shareId);
  }

  static void clear() {
    _byShareId.clear();
    _byPath.clear();
  }
}
