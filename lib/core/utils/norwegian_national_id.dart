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

  /// Parser fødselsdato fra de seks første sifrene + individnummer (3 siffer).
  ///
  /// Individnummer (siffer 7–9) bestemmer århundre (Folkeregisteret):
  /// 000–499 → 1900–1999, 500–749 → 1854–1899 eller 2000–2039,
  /// 750–899 → 2000–2039, 900–999 → 1940–1999.
  static DateTime? birthDateFrom(String? raw) {
    final n = normalize(raw);
    if (n == null) return null;

    var day = int.tryParse(n.substring(0, 2));
    var month = int.tryParse(n.substring(2, 4));
    final yearPart = int.tryParse(n.substring(4, 6));
    final individ = int.tryParse(n.substring(6, 9));
    if (day == null || month == null || yearPart == null || individ == null) {
      return null;
    }

    // D-nummer: dag/måned kan ha +40.
    if (day > 40) day -= 40;
    if (month > 40) month -= 40;

    final year = _birthYearFromIndivid(yearPart, individ);
    if (year == null) return null;

    try {
      return DateTime(year, month, day);
    } catch (_) {
      return null;
    }
  }

  static int? _birthYearFromIndivid(int yearPart, int individ) {
    if (individ >= 0 && individ <= 499) {
      return 1900 + yearPart;
    }
    if (individ >= 500 && individ <= 749) {
      return yearPart >= 54 ? 1800 + yearPart : 2000 + yearPart;
    }
    if (individ >= 750 && individ <= 899) {
      return 2000 + yearPart;
    }
    if (individ >= 900 && individ <= 999) {
      return 1900 + yearPart;
    }
    return null;
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
