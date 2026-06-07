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

  /// Påske (Gregorian) — bevegelige helligdager for året.
  static bool isEasterRelatedHoliday(DateTime d) {
    final y = d.year;
    final easter = easterSunday(y);
    final a = dayOnly(d);
    final movable = [
      easter.subtract(const Duration(days: 2)), // langfredag
      easter.add(const Duration(days: 1)), // 2. påskedag
      easter.add(const Duration(days: 39)), // kristi himmelfartsdag
      easter.add(const Duration(days: 50)), // 2. pinsedag
    ];
    return movable.any((m) => a == dayOnly(m));
  }

  static bool isNorwegianPublicHoliday(DateTime d) {
    return isFixedHoliday(d) || isEasterRelatedHoliday(d);
  }

  static DateTime easterSunday(int year) => _easterSunday(year);

  /// Norsk navn på rød dag, eller null.
  static String? holidayName(DateTime d) {
    final a = dayOnly(d);
    if (a.month == 1 && a.day == 1) return 'Nyttårsdag';
    if (a.month == 5 && a.day == 1) return '1. mai';
    if (a.month == 5 && a.day == 17) return '17. mai';
    if (a.month == 12 && a.day == 25) return '1. juledag';
    if (a.month == 12 && a.day == 26) return '2. juledag';
    final easter = easterSunday(a.year);
    if (a == dayOnly(easter.subtract(const Duration(days: 2)))) return 'Langfredag';
    if (a == dayOnly(easter.add(const Duration(days: 1)))) return '2. påskedag';
    if (a == dayOnly(easter.add(const Duration(days: 39)))) {
      return 'Kristi himmelfartsdag';
    }
    if (a == dayOnly(easter.add(const Duration(days: 50)))) return '2. pinsedag';
    return null;
  }

  static bool isBusinessDay(DateTime d) {
    return !isWeekend(d) && !isNorwegianPublicHoliday(d);
  }

  /// Antall virkedager i perioden (inkl. start og slutt) — brukes for ferie.
  static int countInRange(DateTime start, DateTime end) {
    var from = dayOnly(start);
    final to = dayOnly(end);
    if (to.isBefore(from)) return 0;
    var count = 0;
    while (!from.isAfter(to)) {
      if (isBusinessDay(from)) count++;
      from = from.add(const Duration(days: 1));
    }
    return count;
  }

  /// Virkedager i perioden som faller i [year] (for ferie over årsskifte).
  static int countInRangeForYear(DateTime start, DateTime end, int year) {
    final yearStart = DateTime(year, 1, 1);
    final yearEnd = DateTime(year, 12, 31);
    final from = dayOnly(start).isBefore(yearStart) ? yearStart : dayOnly(start);
    final to = dayOnly(end).isAfter(yearEnd) ? yearEnd : dayOnly(end);
    if (to.isBefore(from)) return 0;
    return countInRange(from, to);
  }

  /// Alle kalenderår perioden berører.
  static List<int> yearsSpanned(DateTime start, DateTime end) {
    final from = dayOnly(start);
    final to = dayOnly(end);
    if (to.isBefore(from)) return const [];
    final years = <int>[];
    for (var y = from.year; y <= to.year; y++) {
      if (countInRangeForYear(from, to, y) > 0) years.add(y);
    }
    return years;
  }

  /// Fordeling av feriedager per år.
  static Map<int, int> daysByYear(DateTime start, DateTime end) {
    final map = <int, int>{};
    for (final y in yearsSpanned(start, end)) {
      map[y] = countInRangeForYear(start, end, y);
    }
    return map;
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
