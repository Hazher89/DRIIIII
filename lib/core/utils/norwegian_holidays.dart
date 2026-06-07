import 'business_days.dart';

/// Norsk helligdag med navn — brukes i fraværskalender.
class NorwegianHoliday {
  final DateTime date;
  final String name;

  const NorwegianHoliday({required this.date, required this.name});
}

class NorwegianHolidays {
  NorwegianHolidays._();

  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Alle offisielle røde dager for et år, sortert kronologisk.
  static List<NorwegianHoliday> forYear(int year) {
    final easter = BusinessDays.easterSunday(year);
    final items = <NorwegianHoliday>[
      NorwegianHoliday(date: DateTime(year, 1, 1), name: 'Nyttårsdag'),
      NorwegianHoliday(
        date: easter.subtract(const Duration(days: 2)),
        name: 'Langfredag',
      ),
      NorwegianHoliday(
        date: easter.add(const Duration(days: 1)),
        name: '2. påskedag',
      ),
      NorwegianHoliday(
        date: easter.add(const Duration(days: 39)),
        name: 'Kristi himmelfartsdag',
      ),
      NorwegianHoliday(
        date: easter.add(const Duration(days: 50)),
        name: '2. pinsedag',
      ),
      NorwegianHoliday(date: DateTime(year, 5, 1), name: '1. mai'),
      NorwegianHoliday(date: DateTime(year, 5, 17), name: '17. mai'),
      NorwegianHoliday(date: DateTime(year, 12, 25), name: '1. juledag'),
      NorwegianHoliday(date: DateTime(year, 12, 26), name: '2. juledag'),
    ];
    items.sort((a, b) => a.date.compareTo(b.date));
    return items;
  }

  static List<NorwegianHoliday> forMonth(int year, int month) {
    return forYear(year)
        .where((h) => h.date.year == year && h.date.month == month)
        .toList();
  }

  static List<NorwegianHoliday> upcomingFrom(DateTime from) {
    final start = _dayOnly(from);
    return [
      ...forYear(start.year),
      ...forYear(start.year + 1),
    ].where((h) => !_dayOnly(h.date).isBefore(start)).toList();
  }

  static String? nameOn(DateTime date) => BusinessDays.holidayName(date);

  static bool isRedDay(DateTime date) => BusinessDays.isNorwegianPublicHoliday(date);
}
