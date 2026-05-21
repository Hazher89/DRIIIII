/// Norsk fødselsnummer / D-nummer — normalisering og fødselsdato.
class NorwegianNationalId {
  NorwegianNationalId._();

  /// Kun siffer (11 tegn) eller null hvis ugyldig lengde.
  static String? normalize(String? raw) {
    if (raw == null) return null;
    final d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.isEmpty) return null;
    if (d.length != 11) return null;
    return d;
  }

  static String formatDisplay(String? normalized) {
    final n = normalize(normalized);
    if (n == null) return '';
    return '${n.substring(0, 6)} ${n.substring(6)}';
  }

  /// Masker for lister (viser ikke kontrollsiffer i detalj).
  static String formatMasked(String? normalized) {
    final n = normalize(normalized);
    if (n == null) return '—';
    return '${n.substring(0, 6)} *****';
  }

  /// Parser fødselsdato fra de seks første sifrene + individsiffer (standard regler).
  static DateTime? birthDateFrom(String? raw) {
    final n = normalize(raw);
    if (n == null) return null;

    final day = int.tryParse(n.substring(0, 2));
    final month = int.tryParse(n.substring(2, 4));
    final yearPart = int.tryParse(n.substring(4, 6));
    if (day == null || month == null || yearPart == null) return null;

    final ind = int.tryParse(n[6]);
    if (ind == null) return null;

    int year;
    if (ind >= 0 && ind <= 3) {
      year = 1900 + yearPart;
    } else if (ind >= 4 && ind <= 5) {
      year = yearPart >= 40 ? 1900 + yearPart : 2000 + yearPart;
    } else if (ind >= 6 && ind <= 7) {
      year = 2000 + yearPart;
    } else {
      year = 1800 + yearPart;
    }

    try {
      return DateTime(year, month, day);
    } catch (_) {
      return null;
    }
  }

  /// Dager til neste bursdag (0 = i dag).
  static int daysUntilNextBirthday(DateTime birthDate, {DateTime? from}) {
    final now = from ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var next = DateTime(today.year, birthDate.month, birthDate.day);
    if (next.isBefore(today)) {
      next = DateTime(today.year + 1, birthDate.month, birthDate.day);
    }
    return next.difference(today).inDays;
  }

  static int ageOnNextBirthday(DateTime birthDate, {DateTime? from}) {
    final now = from ?? DateTime.now();
    var age = now.year - birthDate.year;
    final nextBday = DateTime(now.year, birthDate.month, birthDate.day);
    if (nextBday.isBefore(DateTime(now.year, now.month, now.day))) {
      age += 1;
    }
    return age;
  }
}
