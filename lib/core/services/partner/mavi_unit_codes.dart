/// Hjelpere for MAVI Resource ID (NO_O_M0001) per samarbeidspartner.
class MaviUnitCodes {
  MaviUnitCodes._();

  static String normalize(String raw) {
    final upper = raw.trim().toUpperCase().replaceAll(RegExp(r'\s'), '');
    if (upper.isEmpty) return '';
    final m = RegExp(r'NO_O_M0*(\d{1,5})').firstMatch(upper);
    if (m != null) {
      final n = int.tryParse(m.group(1)!);
      if (n != null) return 'NO_O_M${n.toString().padLeft(4, '0')}';
    }
    final simple = RegExp(r'^M0*(\d{1,5})$').firstMatch(upper);
    if (simple != null) {
      final n = int.tryParse(simple.group(1)!);
      if (n != null) return 'NO_O_M${n.toString().padLeft(4, '0')}';
    }
    if (RegExp(r'^\d{1,5}$').hasMatch(upper)) {
      final n = int.tryParse(upper)!;
      return 'NO_O_M${n.toString().padLeft(4, '0')}';
    }
    return upper;
  }

  static int _maxIndex(Iterable<String> codes) {
    var max = 0;
    for (final c in codes) {
      final n = normalize(c);
      final m = RegExp(r'NO_O_M0*(\d{1,5})').firstMatch(n);
      if (m != null) {
        final v = int.tryParse(m.group(1)!);
        if (v != null && v > max) max = v;
      }
    }
    return max;
  }

  static String suggestNext(Iterable<String> existing) {
    final next = _maxIndex(existing) + 1;
    return 'NO_O_M${next.toString().padLeft(4, '0')}';
  }

  /// Lim inn flere linjer: M1, M0002, NO_O_M0003, osv.
  static List<String> parseBulk(String text) {
    final out = <String>[];
    final seen = <String>{};
    for (final line in text.split(RegExp(r'[\n,;]+'))) {
      final n = normalize(line);
      if (n.isEmpty || seen.contains(n)) continue;
      seen.add(n);
      out.add(n);
    }
    return out;
  }

  static const regNrPlaceholder = '—';
}
