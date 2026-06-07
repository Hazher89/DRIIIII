import '../../constants/leave_rules.dart';
import '../../utils/leave_usage_colors.dart';
import '../../../models/absence.dart';
import '../../../models/leave_period_usage.dart';
import '../../../models/user_profile.dart';
import 'absence_service.dart';
import 'leave_period_usage_service.dart';

/// Felles fraværsstatistikk — brukes i Team & kalender og Avdelinger.
class EmployeeLeaveSnapshot {
  final int ferieRemaining;
  final int ferieTotal;
  final int ferieUsed;
  final int egenDaysTotal;
  final int egenTilfeller;
  final int egenMax;
  final int egenTilfellerMax;
  final int syktDays;
  final int syktMax;
  final int totalFravaerDager;
  final LeavePeriodUsage periodUsage;

  const EmployeeLeaveSnapshot({
    required this.ferieRemaining,
    required this.ferieTotal,
    required this.ferieUsed,
    required this.egenDaysTotal,
    required this.egenTilfeller,
    required this.egenMax,
    required this.egenTilfellerMax,
    required this.syktDays,
    required this.syktMax,
    required this.totalFravaerDager,
    required this.periodUsage,
  });

  LeaveUsageLevel get ferieLevel =>
      LeaveUsageColors.levelFromRemaining(ferieRemaining, ferieTotal);

  LeaveUsageLevel get egenLevel => LeaveUsageColors.worst(
        LeaveUsageColors.levelFromUsed(egenDaysTotal, egenMax),
        LeaveUsageColors.levelFromUsed(egenTilfeller, egenTilfellerMax),
      );

  LeaveUsageLevel get syktLevel =>
      LeaveUsageColors.levelFromUsed(syktDays, syktMax);

  double get ferieProgress =>
      ferieTotal > 0 ? ferieUsed / ferieTotal : 0;

  double get egenProgress => egenMax > 0 ? egenDaysTotal / egenMax : 0;

  double get syktProgress => syktMax > 0 ? syktDays / syktMax : 0;

  static EmployeeLeaveSnapshot compute({
    required UserProfile employee,
    required List<Absence> employeeAbsences,
    AbsenceQuota? quota,
    CompanyLeaveSettings company = const CompanyLeaveSettings(),
    DateTime? referenceDate,
  }) {
    final periodUsage = LeavePeriodUsageService.compute(
      absences: employeeAbsences,
      hireDate: employee.hireDate,
      referenceDate: referenceDate,
    );
    final approved = employeeAbsences
        .where((a) => a.status == AbsenceStatus.godkjent)
        .toList();
    final egenRecords =
        approved.where((a) => a.type == AbsenceType.egenmelding).toList();
    final egenDaysTotal = egenRecords.fold<int>(
      0,
      (sum, a) =>
          sum + (a.totalDays ?? AbsenceService.dayCount(a.startDate, a.endDate)),
    );
    final syktMax = company.syktBarnDaysLimit(
      childrenUnder12: employee.childrenUnder12Count,
    );
    final syktDays = periodUsage.syktBarnDaysUsed;
    final ferieTotal = quota?.totalVacationDays ?? LeaveRules.ferieLegalMinimumDays;
    final ferieUsed = quota?.vacationDaysUsed ?? 0;
    final ferieRemaining = quota?.vacationDaysRemaining ?? ferieTotal;

    return EmployeeLeaveSnapshot(
      ferieRemaining: ferieRemaining,
      ferieTotal: ferieTotal,
      ferieUsed: ferieUsed,
      egenDaysTotal: egenDaysTotal,
      egenTilfeller: egenRecords.length,
      egenMax: company.egenmeldingDaysPerYear,
      egenTilfellerMax: LeaveRules.egenmeldingMaxPeriodsPerYear,
      syktDays: syktDays,
      syktMax: syktMax,
      totalFravaerDager: egenDaysTotal + syktDays,
      periodUsage: periodUsage,
    );
  }
}
