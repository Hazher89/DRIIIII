/// Felles årsvindu for ferie/fravær — historikk + maks ett år frem.
class VacationYearWindow {
  VacationYearWindow._();

  static const int yearsBack = 5;
  /// Kun inneværende + neste år (ferieplanlegging) — ikke langt inn i fremtiden.
  static const int yearsForward = 1;

  static int get currentYear => DateTime.now().year;

  /// Eldst → nyest (fra … til).
  static List<int> get years => List.generate(
        yearsBack + yearsForward + 1,
        (i) => currentYear - yearsBack + i,
      );

  /// Nyest først — til årvelger i UI (inneværende nær toppen).
  static List<int> get yearsNewestFirst => years.reversed.toList();

  static int get fromYear => currentYear - yearsBack;
  static int get toYear => currentYear + yearsForward;

  static DateTime get earliestSelectableDate => DateTime(fromYear, 1, 1);
  static DateTime get latestSelectableDate => DateTime(toYear, 12, 31);

  static bool contains(int year) => year >= fromYear && year <= toYear;
}
