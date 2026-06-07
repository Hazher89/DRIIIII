import '../../../models/absence.dart';
import '../../../models/leave_period_usage.dart';
import '../../utils/leave_period_window.dart';
import 'absence_service.dart';

class LeavePeriodUsageService {
  LeavePeriodUsageService._();

  /// Beregner godkjent bruk i perioden som inneholder [referenceDate].
  static LeavePeriodUsage compute({
    required List<Absence> absences,
    DateTime? hireDate,
    DateTime? referenceDate,
  }) {
    final window = LeavePeriodWindow.forReference(
      hireDate: hireDate,
      referenceDate: referenceDate,
    );

    final approved = absences.where((a) => a.status == AbsenceStatus.godkjent);

    final egen = approved
        .where((a) =>
            a.type == AbsenceType.egenmelding && window.contains(a.startDate))
        .toList();

    final sykt = approved
        .where((a) =>
            a.type == AbsenceType.syktBarn && window.contains(a.startDate))
        .toList();

    int daysFor(List<Absence> list) => list.fold(
          0,
          (sum, a) =>
              sum +
              (a.totalDays ??
                  AbsenceService.dayCount(a.startDate, a.endDate)),
        );

    return LeavePeriodUsage(
      window: window,
      egenmeldingDaysUsed: daysFor(egen),
      egenmeldingPeriodsUsed: egen.length,
      syktBarnDaysUsed: daysFor(sykt),
    );
  }
}
