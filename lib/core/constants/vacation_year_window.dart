/// Felles årsvindu for ferie/fravær — historikk og planlegging fremover.
class VacationYearWindow {
  VacationYearWindow._();

  static const int yearsBack = 5;
  static const int yearsForward = 10;

  static int get currentYear => DateTime.now().year;

  static List<int> get years => List.generate(
        yearsBack + yearsForward + 1,
        (i) => currentYear - yearsBack + i,
      );

  static int get fromYear => currentYear - yearsBack;
  static int get toYear => currentYear + yearsForward;

  static DateTime get earliestSelectableDate => DateTime(fromYear, 1, 1);
  static DateTime get latestSelectableDate => DateTime(toYear, 12, 31);

  static bool contains(int year) => year >= fromYear && year <= toYear;
}
