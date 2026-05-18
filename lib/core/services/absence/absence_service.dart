import '../../../models/absence.dart';
import '../../constants/leave_rules.dart';

/// Klientvalidering før innsending (speiler DB-regler der mulig).
class AbsenceService {
  AbsenceService._();

  static int dayCount(DateTime start, DateTime end) =>
      end.difference(start).inDays + 1;

  static String? validateRequest({
    required AbsenceType type,
    required DateTime start,
    required DateTime end,
    required AbsenceQuota? quota,
    required CompanyLeaveSettings company,
    int childrenCount = 1,
  }) {
    final days = dayCount(start, end);
    if (days < 1) return 'Ugyldig datoperiode.';

    switch (type) {
      case AbsenceType.egenmelding:
        if (days > company.egenmeldingConsecutiveMax) {
          return 'Egenmelding kan maks være ${company.egenmeldingConsecutiveMax} '
              'kalenderdager om gangen (Lovdata/AML).';
        }
        if (quota != null &&
            quota.egenmeldingPeriodsUsed >= LeaveRules.egenmeldingMaxPeriodsPerYear) {
          return 'Du har brukt alle ${LeaveRules.egenmeldingMaxPeriodsPerYear} '
              'egenmeldingsperioder dette året.';
        }
        if (quota != null &&
            quota.egenmeldingDaysUsed + days > company.egenmeldingDaysPerYear) {
          return 'Egenmeldingskvoten er brukt opp '
              '(${quota.egenmeldingDaysUsed}/${company.egenmeldingDaysPerYear} dager).';
        }
        return null;

      case AbsenceType.syktBarn:
        final limit = company.syktBarnDaysLimit(childrenCount: childrenCount);
        if (quota != null && quota.syktBarnDaysUsed + days > limit) {
          return 'Sykt-barn-kvoten er overskredet '
              '(${quota.syktBarnDaysUsed}/$limit dager i ${quota.year}).';
        }
        return null;

      case AbsenceType.ferie:
        if (quota == null) {
          return 'Ingen feriekvote funnet for ${start.year}. Kontakt admin.';
        }
        if (days > quota.vacationDaysRemaining) {
          return 'Du har bare ${quota.vacationDaysRemaining} feriedager igjen, '
              'men søker om $days dager.';
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
}
