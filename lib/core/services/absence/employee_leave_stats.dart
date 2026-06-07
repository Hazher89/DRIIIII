import '../../constants/leave_rules.dart';
import '../../utils/business_days.dart';
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

  /// Egenmelding som andel av årlig kvote (0–100).
  double get egenQuotaPercent =>
      egenMax > 0 ? (egenDaysTotal / egenMax * 100).clamp(0, 100) : 0;

  /// Sykt barn som andel av årlig kvote (0–100).
  double get syktQuotaPercent =>
      syktMax > 0 ? (syktDays / syktMax * 100).clamp(0, 100) : 0;

  /// Høyeste kvotebruk blant egenmelding og sykt barn (0–100).
  double get quotaUsagePercent =>
      egenQuotaPercent > syktQuotaPercent ? egenQuotaPercent : syktQuotaPercent;

  /// Fraværsrate YTD: fraværsdager / virkedager hittil i år (0–100).
  /// Matcher bedrifts-KPI (mål ≤ 9,9 %).
  double absenceRatePercent([DateTime? referenceDate]) {
    final ref = referenceDate ?? DateTime.now();
    final workDays = BusinessDays.countInRange(
      DateTime(ref.year, 1, 1),
      ref,
    );
    if (workDays <= 0) return 0;
    return (totalFravaerDager / workDays * 100).clamp(0, 100);
  }

  LeaveUsageLevel get quotaUsageLevel =>
      LeaveUsageColors.levelFromUsed(quotaUsagePercent.round(), 100);

  LeaveUsageLevel absenceRateLevel([DateTime? referenceDate]) =>
      LeaveUsageColors.levelFromUsed(
        absenceRatePercent(referenceDate).round(),
        10,
      );

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

/// Samlet fraværsstatistikk for team / avdeling / bedrift.
class TeamLeaveSummary {
  final double averageAbsencePercent;
  final int totalFravaerDays;
  final int totalEgenDays;
  final int totalSyktDays;
  final int totalEgenTilfeller;
  final int employeeCount;

  const TeamLeaveSummary({
    required this.averageAbsencePercent,
    required this.totalFravaerDays,
    required this.totalEgenDays,
    required this.totalSyktDays,
    required this.totalEgenTilfeller,
    required this.employeeCount,
  });

  static const empty = TeamLeaveSummary(
    averageAbsencePercent: 0,
    totalFravaerDays: 0,
    totalEgenDays: 0,
    totalSyktDays: 0,
    totalEgenTilfeller: 0,
    employeeCount: 0,
  );

  int get averageAbsencePercentRounded => averageAbsencePercent.round();

  LeaveUsageLevel get usageLevel => employeeCount <= 0
      ? LeaveUsageLevel.ok
      : LeaveUsageColors.levelFromUsed(averageAbsencePercentRounded, 10);

  static TeamLeaveSummary compute({
    required List<UserProfile> employees,
    required List<Absence> allAbsences,
    CompanyLeaveSettings company = const CompanyLeaveSettings(),
    DateTime? referenceDate,
  }) {
    if (employees.isEmpty) return empty;

    final ref = referenceDate ?? DateTime.now();
    final workDaysYtd = BusinessDays.countInRange(
      DateTime(ref.year, 1, 1),
      ref,
    );
    var totalDays = 0;
    var egenDays = 0;
    var syktDays = 0;
    var tilfeller = 0;

    for (final e in employees) {
      final pool =
          allAbsences.where((a) => a.userId == e.id).toList(growable: false);
      final snap = EmployeeLeaveSnapshot.compute(
        employee: e,
        employeeAbsences: pool,
        company: company,
        referenceDate: ref,
      );
      totalDays += snap.totalFravaerDager;
      egenDays += snap.egenDaysTotal;
      syktDays += snap.syktDays;
      tilfeller += snap.egenTilfeller;
    }

    final pooledRate = workDaysYtd > 0
        ? (totalDays / (employees.length * workDaysYtd) * 100)
            .clamp(0.0, 100.0)
            .toDouble()
        : 0.0;

    return TeamLeaveSummary(
      averageAbsencePercent: pooledRate,
      totalFravaerDays: totalDays,
      totalEgenDays: egenDays,
      totalSyktDays: syktDays,
      totalEgenTilfeller: tilfeller,
      employeeCount: employees.length,
    );
  }
}
