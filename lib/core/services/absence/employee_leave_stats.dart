import '../../constants/leave_rules.dart';
import '../../utils/business_days.dart';
import '../../utils/leave_usage_colors.dart';
import '../../../models/absence.dart';
import '../../../models/leave_period_usage.dart';
import '../../../models/user_profile.dart';
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
  final int sykmeldingDays;
  /// KPI-fravær: egenmelding + sykt barn + sykmelding (ikke ferie).
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
    required this.sykmeldingDays,
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

  /// Typer som teller i bedriftens fraværs-% (ferie/permisjon telles ikke).
  static const kpiAbsenceTypes = {
    AbsenceType.egenmelding,
    AbsenceType.syktBarn,
    AbsenceType.sykmelding,
  };

  /// Unike virkedager i [rangeStart]–[rangeEnd] for godkjente fravær av [types].
  /// Overlappende perioder for samme person telles bare én gang (person-dager).
  static int uniqueBusinessDaysInWindow({
    required List<Absence> absences,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    Set<AbsenceType> types = kpiAbsenceTypes,
  }) {
    final from = BusinessDays.dayOnly(rangeStart);
    final to = BusinessDays.dayOnly(rangeEnd);
    if (to.isBefore(from)) return 0;

    final days = <int>{};
    for (final a in absences) {
      if (a.status != AbsenceStatus.godkjent) continue;
      if (!types.contains(a.type)) continue;
      var cursor = BusinessDays.dayOnly(a.startDate);
      final end = BusinessDays.dayOnly(a.endDate);
      while (!cursor.isAfter(end)) {
        if (!cursor.isBefore(from) &&
            !cursor.isAfter(to) &&
            BusinessDays.isBusinessDay(cursor)) {
          days.add(cursor.millisecondsSinceEpoch);
        }
        cursor = cursor.add(const Duration(days: 1));
      }
    }
    return days.length;
  }

  /// Virkedager i [year] frem til [through] som overlapper godkjente fravær.
  static int businessDaysInYearToDate({
    required List<Absence> absences,
    required int year,
    required DateTime through,
    Set<AbsenceType> types = kpiAbsenceTypes,
  }) {
    return uniqueBusinessDaysInWindow(
      absences: absences,
      rangeStart: DateTime(year, 1, 1),
      rangeEnd: through,
      types: types,
    );
  }

  static EmployeeLeaveSnapshot compute({
    required UserProfile employee,
    required List<Absence> employeeAbsences,
    AbsenceQuota? quota,
    CompanyLeaveSettings company = const CompanyLeaveSettings(),
    DateTime? referenceDate,
    LeavePeriodUsage? periodUsageOverride,
  }) {
    final ref = referenceDate ?? DateTime.now();
    final periodUsage = periodUsageOverride ??
        LeavePeriodUsageService.compute(
          absences: employeeAbsences,
          hireDate: employee.hireDate,
          referenceDate: ref,
        );
    // Kvote-meter: egenmelding/sykt barn i aktiv periode.
    final egenDaysTotal = periodUsage.egenmeldingDaysUsed;
    final egenTilfeller = periodUsage.egenmeldingPeriodsUsed;
    final syktMax = company.syktBarnDaysLimit(
      childrenUnder12: employee.childrenUnder12Count,
    );
    final syktDays = periodUsage.syktBarnDaysUsed;
    final ferieTotal = quota?.totalVacationDays ?? LeaveRules.ferieLegalMinimumDays;
    final ferieUsed = quota?.vacationDaysUsed ?? 0;
    final ferieRemaining = quota?.vacationDaysRemaining ?? ferieTotal;

    // KPI-fravær: kalenderår YTD inkl. sykmelding (ikke bare egen/sykt barn).
    final sykmeldingDays = businessDaysInYearToDate(
      absences: employeeAbsences,
      year: ref.year,
      through: ref,
      types: {AbsenceType.sykmelding},
    );
    final totalFravaerDager = businessDaysInYearToDate(
      absences: employeeAbsences,
      year: ref.year,
      through: ref,
      types: kpiAbsenceTypes,
    );

    return EmployeeLeaveSnapshot(
      ferieRemaining: ferieRemaining,
      ferieTotal: ferieTotal,
      ferieUsed: ferieUsed,
      egenDaysTotal: egenDaysTotal,
      egenTilfeller: egenTilfeller,
      egenMax: company.effectiveEgenmeldingDaysPerYear,
      egenTilfellerMax: LeaveRules.egenmeldingMaxPeriodsPerYear,
      syktDays: syktDays,
      syktMax: syktMax,
      sykmeldingDays: sykmeldingDays,
      totalFravaerDager: totalFravaerDager,
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
  final int totalSykmeldingDays;
  final int totalEgenTilfeller;
  final int employeeCount;

  const TeamLeaveSummary({
    required this.averageAbsencePercent,
    required this.totalFravaerDays,
    required this.totalEgenDays,
    required this.totalSyktDays,
    required this.totalSykmeldingDays,
    required this.totalEgenTilfeller,
    required this.employeeCount,
  });

  static const empty = TeamLeaveSummary(
    averageAbsencePercent: 0,
    totalFravaerDays: 0,
    totalEgenDays: 0,
    totalSyktDays: 0,
    totalSykmeldingDays: 0,
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
    final ref = referenceDate ?? DateTime.now();
    return computeForRange(
      employees: employees,
      allAbsences: allAbsences,
      company: company,
      rangeStart: DateTime(ref.year, 1, 1),
      rangeEnd: ref,
    );
  }

  /// Fraværssum for vilkårlig periode (år eller fra–til).
  /// Sykmelding/egen/sykt barn = unike person-virkedager per ansatt (ingen dobbelttelling).
  static TeamLeaveSummary computeForRange({
    required List<UserProfile> employees,
    required List<Absence> allAbsences,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    CompanyLeaveSettings company = const CompanyLeaveSettings(),
  }) {
    if (employees.isEmpty) return empty;

    final from = BusinessDays.dayOnly(rangeStart);
    final to = BusinessDays.dayOnly(rangeEnd);
    final workDays = BusinessDays.countInRange(from, to);
    var totalDays = 0;
    var egenDays = 0;
    var syktDays = 0;
    var sykmeldingDays = 0;
    var tilfeller = 0;

    for (final e in employees) {
      final pool =
          allAbsences.where((a) => a.userId == e.id).toList(growable: false);
      totalDays += EmployeeLeaveSnapshot.uniqueBusinessDaysInWindow(
        absences: pool,
        rangeStart: from,
        rangeEnd: to,
        types: EmployeeLeaveSnapshot.kpiAbsenceTypes,
      );
      egenDays += EmployeeLeaveSnapshot.uniqueBusinessDaysInWindow(
        absences: pool,
        rangeStart: from,
        rangeEnd: to,
        types: {AbsenceType.egenmelding},
      );
      syktDays += EmployeeLeaveSnapshot.uniqueBusinessDaysInWindow(
        absences: pool,
        rangeStart: from,
        rangeEnd: to,
        types: {AbsenceType.syktBarn},
      );
      sykmeldingDays += EmployeeLeaveSnapshot.uniqueBusinessDaysInWindow(
        absences: pool,
        rangeStart: from,
        rangeEnd: to,
        types: {AbsenceType.sykmelding},
      );
      // Tilfeller fortsatt fra kvote-vindu via snapshot (best effort).
      final snap = EmployeeLeaveSnapshot.compute(
        employee: e,
        employeeAbsences: pool,
        company: company,
        referenceDate: to,
      );
      tilfeller += snap.egenTilfeller;
    }

    final pooledRate = workDays > 0
        ? (totalDays / (employees.length * workDays) * 100)
            .clamp(0.0, 100.0)
            .toDouble()
        : 0.0;

    return TeamLeaveSummary(
      averageAbsencePercent: pooledRate,
      totalFravaerDays: totalDays,
      totalEgenDays: egenDays,
      totalSyktDays: syktDays,
      totalSykmeldingDays: sykmeldingDays,
      totalEgenTilfeller: tilfeller,
      employeeCount: employees.length,
    );
  }
}
