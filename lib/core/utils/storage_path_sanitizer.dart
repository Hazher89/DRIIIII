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

  static String fileName(String raw, {String fallback = 'fil.pdf'}) {
    final base = segment(raw, fallback: fallback);
    return base.toLowerCase().endsWith('.pdf') ? base : '$base.pdf';
  }

  static String storagePath(String raw) {
    return raw
        .split('/')
        .where((p) => p.trim().isNotEmpty && p != '.' && p != '..')
        .map((p) => segment(p))
        .join('/');
  }
}
