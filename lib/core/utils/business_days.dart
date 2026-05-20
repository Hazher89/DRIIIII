/// Virkedager (man–fre) og norske helligdager for partner fri-søknad.
class BusinessDays {
  BusinessDays._();

  static DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static bool isWeekend(DateTime d) {
    final w = dayOnly(d).weekday;
    return w == DateTime.saturday || w == DateTime.sunday;
  }

  /// Faste norske helligdager (dato uten år — gjelder alle år i appen).
  static bool isFixedHoliday(DateTime d) {
    final m = d.month;
    final day = d.day;
    if (m == 1 && day == 1) return true; // nyttår
    if (m == 5 && day == 1) return true; // 1. mai
    if (m == 5 && day == 17) return true; // 17. mai
    if (m == 12 && day == 25) return true;
    if (m == 12 && day == 26) return true;
    return false;
  }

  /// Påske (Gregorian) — Good Friday + Easter Monday for året.
  static bool isEasterRelatedHoliday(DateTime d) {
    final y = d.year;
    final easter = _easterSunday(y);
    final goodFriday = easter.subtract(const Duration(days: 2));
    final easterMonday = easter.add(const Duration(days: 1));
    final a = dayOnly(d);
    return a == dayOnly(goodFriday) || a == dayOnly(easterMonday);
  }

  static bool isNorwegianPublicHoliday(DateTime d) {
    return isFixedHoliday(d) || isEasterRelatedHoliday(d);
  }

  static bool isBusinessDay(DateTime d) {
    return !isWeekend(d) && !isNorwegianPublicHoliday(d);
  }

  /// Tidligste dato sjåfør kan søke fri: minst [minBusinessDays] virkedager frem i tid.
  static DateTime earliestAllowedDate({
    DateTime? from,
    int minBusinessDays = 3,
  }) {
    var cursor = dayOnly(from ?? DateTime.now());
    var counted = 0;
    while (counted < minBusinessDays) {
      cursor = cursor.add(const Duration(days: 1));
      if (isBusinessDay(cursor)) counted++;
    }
    return cursor;
  }

  static DateTime _easterSunday(int year) {
    final a = year % 19;
    final b = year ~/ 100;
    final c = year % 100;
    final d = b ~/ 4;
    final e = b % 4;
    final f = (b + 8) ~/ 25;
    final g = (b - f + 1) ~/ 3;
    final h = (19 * a + b - d - g + 15) % 30;
    final i = c ~/ 4;
    final k = c % 4;
    final l = (32 + 2 * e + 2 * i - h - k) % 7;
    final m = (a + 11 * h + 22 * l) ~/ 451;
    final month = (h + l - 7 * m + 114) ~/ 31;
    final day = ((h + l - 7 * m + 114) % 31) + 1;
    return DateTime(year, month, day);
  }
}
