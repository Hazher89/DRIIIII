import '../../../models/absence.dart';
import '../../../models/leave_period_usage.dart';
import '../../constants/leave_rules.dart';
import '../../utils/business_days.dart';

/// Klientvalidering før innsending (speiler DB-regler der mulig).
class AbsenceService {
  AbsenceService._();

  /// Kalenderdager inkl. start og slutt (egenmelding, sykt barn, visning).
  static int dayCount(DateTime start, DateTime end) =>
      end.difference(start).inDays + 1;

  /// Virkedager i perioden — ferieloven (unntatt helg og røde dager).
  static int vacationDayCount(DateTime start, DateTime end) =>
      BusinessDays.countInRange(start, end);

  static String? validateRequest({
    required AbsenceType type,
    required DateTime start,
    required DateTime end,
    required AbsenceQuota? quota,
    Map<int, AbsenceQuota>? quotasByYear,
    LeavePeriodUsage? periodUsage,
    required CompanyLeaveSettings company,
    int childrenUnder12 = 0,
  }) {
    final days = dayCount(start, end);
    if (days < 1) return 'Ugyldig datoperiode.';

    switch (type) {
      case AbsenceType.egenmelding:
        if (days > company.egenmeldingConsecutiveMax) {
          return 'Egenmelding kan maks være ${company.egenmeldingConsecutiveMax} '
              'kalenderdager om gangen (Lovdata/AML).';
        }
        if (periodUsage != null &&
            periodUsage.egenmeldingPeriodsUsed >=
                LeaveRules.egenmeldingMaxPeriodsPerYear) {
          return 'Du har brukt alle ${LeaveRules.egenmeldingMaxPeriodsPerYear} '
              'egenmeldingsperioder i perioden ${periodUsage.window.formatRange()}.';
        }
        if (periodUsage != null &&
            periodUsage.egenmeldingDaysUsed + days >
                company.egenmeldingDaysPerYear) {
          return 'Egenmeldingskvoten er brukt opp i perioden '
              '${periodUsage.window.formatRange()} '
              '(${periodUsage.egenmeldingDaysUsed}/${company.egenmeldingDaysPerYear} dager).';
        }
        return null;

      case AbsenceType.syktBarn:
        final limit = company.syktBarnDaysLimit(childrenUnder12: childrenUnder12);
        if (periodUsage != null &&
            periodUsage.syktBarnDaysUsed + days > limit) {
          return 'Sykt-barn-kvoten er overskredet '
              '(${periodUsage.syktBarnDaysUsed}/$limit dager i perioden '
              '${periodUsage.window.formatRange()}).';
        }
        return null;

      case AbsenceType.ferie:
        final vacationDays = vacationDayCount(start, end);
        if (vacationDays < 1) {
          return 'Perioden inneholder ingen virkedager (helg/helligdag).';
        }
        final byYear = BusinessDays.daysByYear(start, end);
        for (final entry in byYear.entries) {
          final q = quotasByYear?[entry.key] ?? (entry.key == quota?.year ? quota : null);
          if (q == null) {
            return 'Ingen feriekvote funnet for ${entry.key}. Kontakt admin.';
          }
          if (entry.value > q.vacationDaysRemaining) {
            return 'Du har bare ${q.vacationDaysRemaining} feriedager igjen i '
                '${entry.key}, men perioden krever ${entry.value} dager det året.';
          }
        }
        return null;

      default:
        return null;
    }
  }

  /// Eksempel: 35 tildelt, 30 brukt → 5 kan overføres (maks company.maxVacationCarryover).
  static int projectedCarryover({
    required AbsenceQuota quota,
    required int maxCarryover,
  }) {
    final remaining = quota.vacationDaysRemaining;
    if (remaining <= 0) return 0;
    return remaining > maxCarryover ? maxCarryover : remaining;
  }

  /// Neste års total hvis admin tildeler [newYearAllocation] + overføring.
  static int projectedNextYearTotal({
    required AbsenceQuota quota,
    required int newYearAllocation,
    required int maxCarryover,
  }) =>
      newYearAllocation + projectedCarryover(quota: quota, maxCarryover: maxCarryover);

  static List<Absence> filterActiveOnDate(List<Absence> absences, DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return absences.where((a) {
      if (a.status != AbsenceStatus.godkjent) return false;
      final s = DateTime(a.startDate.year, a.startDate.month, a.startDate.day);
      final e = DateTime(a.endDate.year, a.endDate.month, a.endDate.day);
      return !d.isBefore(s) && !d.isAfter(e);
    }).toList();
  }

  static List<Absence> pendingRequests(List<Absence> absences) =>
      absences.where((a) => a.status == AbsenceStatus.ventende).toList();

  static List<Absence> approvedVacation(List<Absence> absences) =>
      absences.where((a) => a.type == AbsenceType.ferie && a.status == AbsenceStatus.godkjent).toList();

  static bool overlapsYear(Absence absence, int year) {
    final yearStart = DateTime(year, 1, 1);
    final yearEnd = DateTime(year, 12, 31);
    final start = DateTime(
      absence.startDate.year,
      absence.startDate.month,
      absence.startDate.day,
    );
    final end = DateTime(
      absence.endDate.year,
      absence.endDate.month,
      absence.endDate.day,
    );
    return !end.isBefore(yearStart) && !start.isAfter(yearEnd);
  }

  static List<Absence> approvedVacationInYear(List<Absence> absences, int year) =>
      approvedVacation(absences).where((a) => overlapsYear(a, year)).toList();

  static int approvedVacationDaysInYear(List<Absence> absences, int year) =>
      approvedVacationInYear(absences, year).fold(
        0,
        (sum, a) => sum + BusinessDays.countInRangeForYear(a.startDate, a.endDate, year),
      );
}
