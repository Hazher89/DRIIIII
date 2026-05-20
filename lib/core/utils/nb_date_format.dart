import 'package:intl/intl.dart';

/// Norsk dato/tid med fallback hvis locale ikke er initialisert (vanlig på web).
class NbDateFormat {
  NbDateFormat._();

  static String format(DateTime date, String pattern) {
    for (final locale in const ['nb', 'nb_NO', null]) {
      try {
        if (locale == null) {
          return DateFormat(pattern).format(date);
        }
        return DateFormat(pattern, locale).format(date);
      } catch (_) {
        continue;
      }
    }
    return date.toIso8601String();
  }
}
