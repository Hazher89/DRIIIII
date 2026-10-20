/// Hjelpere for MAVI Resource ID (NO_O_M0001) per samarbeidspartner.
class MaviUnitCodes {
  MaviUnitCodes._();

  static String normalize(String raw) {
    final upper = raw.trim().toUpperCase().replaceAll(RegExp(r'\s'), '');
    if (upper.isEmpty) return '';
    // Tall-koder først (NO_O_M0096).
    final m = RegExp(r'NO_O_M0*(\d{1,5})$').firstMatch(upper);
    if (m != null) {
      final n = int.tryParse(m.group(1)!);
      if (n != null) return 'NO_O_M${n.toString().padLeft(4, '0')}';
    }
    // Navnebaserte koder: NO_O_M0JIM / MJIM → NO_O_M0JIM
    final alpha = RegExp(r'NO_O_M0*([A-Z][A-Z0-9]{1,8})$').firstMatch(upper);
    if (alpha != null) return 'NO_O_M0${alpha.group(1)}';
    final simple = RegExp(r'^M0*(\d{1,5})$').firstMatch(upper);
    if (simple != null) {
      final n = int.tryParse(simple.group(1)!);
      if (n != null) return 'NO_O_M${n.toString().padLeft(4, '0')}';
    }
    final simpleAlpha = RegExp(r'^M0*([A-Z][A-Z0-9]{1,8})$').firstMatch(upper);
    if (simpleAlpha != null) return 'NO_O_M0${simpleAlpha.group(1)}';
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

  /// Enhetskode for kun reg.nr (flere biler på bedriften uten MAVI ennå).
  static String registrationUnitCode(String registration) {
    final plate = registration.trim().toUpperCase().replaceAll(RegExp(r'\s'), '');
    if (plate.isEmpty || plate == regNrPlaceholder) return '';
    return 'REG-$plate';
  }

  static bool isRegistrationOnlyUnit(String unitCode) {
    return unitCode.trim().toUpperCase().startsWith('REG-');
  }

  /// Kort visning: NO_O_M0044 → M44, NO_O_M0JIM → MJIM
  static String compactLabel(String raw) {
    final n = normalize(raw);
    final m = RegExp(r'NO_O_M0*(\d{1,5})$').firstMatch(n);
    if (m != null) {
      final num = int.tryParse(m.group(1)!);
      if (num != null) return 'M$num';
    }
    final alpha = RegExp(r'NO_O_M0*([A-Z][A-Z0-9]{1,8})$').firstMatch(n);
    if (alpha != null) return 'M${alpha.group(1)}';
    return n;
  }

  /// Portal-vennlig: NO_O_M0096 → M0096, NO_O_M0JIM → MJIM
  static String shortLabel(String raw) {
    final n = normalize(raw);
    final m = RegExp(r'NO_O_M0*(\d{1,5})$').firstMatch(n);
    if (m != null) {
      final num = int.tryParse(m.group(1)!);
      if (num != null) return 'M${num.toString().padLeft(4, '0')}';
    }
    final alpha = RegExp(r'NO_O_M0*([A-Z][A-Z0-9]{1,8})$').firstMatch(n);
    if (alpha != null) return 'M${alpha.group(1)}';
    if (isRegistrationOnlyUnit(n)) return plateFromRegistrationUnit(n);
    return compactLabel(raw);
  }

  /// Finn MAVI-kode i fri tekst (f.eks. rutetittel med UUID).
  static String? extractShortLabel(String? text) {
    if (text == null) return null;
    final m = RegExp(
      r'NO_O_M0*(?:\d{1,5}|[A-Z][A-Z0-9]{1,8})|\bM0*(?:\d{1,5}|[A-Z][A-Z0-9]{1,8})\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (m == null) return null;
    return shortLabel(m.group(0)!);
  }

  /// M17 · Sjåførnavn — brukes i lister og nedtrekksmenyer.
  static String fleetDriverLabel(String unitCode, String partnerName) {
    final m = compactLabel(unitCode);
    final name = partnerName.trim();
    if (name.isEmpty) return m;
    return '$m · $name';
  }

  static String plateFromRegistrationUnit(String unitCode) {
    if (!isRegistrationOnlyUnit(unitCode)) return '';
    return unitCode.trim().toUpperCase().replaceFirst('REG-', '');
  }
}
