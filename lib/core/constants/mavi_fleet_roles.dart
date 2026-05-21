/// Biltyper for MAVI-enheter i ruteplanlegging.
abstract final class MaviFleetRoles {
  static const tjenestebil = 'tjenestebil';
  static const enmannsbil = 'enmannsbil';
  static const tomannsbil = '2mannsbil';
  static const intern = 'intern';

  static const all = [tjenestebil, enmannsbil, tomannsbil, intern];

  static String label(String id) {
    switch (id) {
      case tjenestebil:
        return 'Tjenestebil';
      case enmannsbil:
        return 'Enmannsbil';
      case tomannsbil:
        return '2-mannsbil';
      case intern:
        return 'Intern';
      default:
        return id;
    }
  }

  static List<String> normalize(Iterable<String>? raw) {
    if (raw == null) return [];
    final out = <String>[];
    for (final r in raw) {
      final k = r.trim().toLowerCase();
      if (all.contains(k) && !out.contains(k)) out.add(k);
    }
    return out;
  }
}
