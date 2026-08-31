/// Sikre fil- og mappestier for Supabase Storage og Dropbox.
class StoragePathSanitizer {
  StoragePathSanitizer._();

  static String segment(String raw, {String fallback = 'fil'}) {
    var s = raw.trim();
    if (s.isEmpty) return fallback;
    s = s.replaceAll('..', '_');
    s = s.replaceAll(RegExp(r'[/\\]'), '_');
    s = s.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    s = s.replaceAll(RegExp(r'_+'), '_');
    s = s.replaceAll(RegExp(r'^\.+'), '');
    s = s.replaceAll(RegExp(r'\.+$'), '');
    return s.isEmpty ? fallback : s;
  }

  static String fileName(String raw, {String fallback = 'fil.dat'}) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return fallback;
    final dot = trimmed.lastIndexOf('.');
    if (dot > 0 && dot < trimmed.length - 1) {
      final base = segment(trimmed.substring(0, dot), fallback: 'fil');
      final ext = segment(trimmed.substring(dot + 1), fallback: 'dat');
      return '$base.$ext';
    }
    return segment(trimmed, fallback: fallback);
  }

  static String storagePath(String raw) {
    return raw
        .split('/')
        .where((p) => p.trim().isNotEmpty && p != '.' && p != '..')
        .map((p) => segment(p))
        .join('/');
  }
}
