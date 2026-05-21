import '../../constants/leave_rules.dart';
import '../../../models/absence.dart';
import '../../../models/user_profile.dart';

class EmployeeLeaveInsight {
  final UserProfile profile;
  final AbsenceQuota? quota;
  final int egenmeldingUsed;
  final int egenmeldingRemaining;
  final int egenmeldingPeriodsUsed;
  final int vacationRemaining;
  final int vacationUsed;
  final int vacationTotal;
  final int absencesYtdDays;

  const EmployeeLeaveInsight({
    required this.profile,
    required this.quota,
    required this.egenmeldingUsed,
    required this.egenmeldingRemaining,
    required this.egenmeldingPeriodsUsed,
    required this.vacationRemaining,
    required this.vacationUsed,
    required this.vacationTotal,
    required this.absencesYtdDays,
  });

  bool get egenmeldingExhausted => egenmeldingRemaining <= 0;
}

class TeamLeaveInsightsSnapshot {
  final String scopeLabel;
  final bool companyWide;
  final int year;
  final List<EmployeeLeaveInsight> employees;
  final Map<AbsenceType, int> daysByTypeYtd;
  final int onVacationToday;
  final int egenmeldingExhaustedCount;
  final int pendingCount;

  const TeamLeaveInsightsSnapshot({
    required this.scopeLabel,
    required this.companyWide,
    required this.year,
    required this.employees,
    required this.daysByTypeYtd,
    required this.onVacationToday,
    required this.egenmeldingExhaustedCount,
    required this.pendingCount,
  });

  List<EmployeeLeaveInsight> get topEgenmeldingUsers {
    final copy = List<EmployeeLeaveInsight>.from(employees)
      ..sort((a, b) => b.egenmeldingUsed.compareTo(a.egenmeldingUsed));
    return copy.where((e) => e.egenmeldingUsed > 0).take(8).toList();
  }

  List<EmployeeLeaveInsight> get egenmeldingExhausted =>
      employees.where((e) => e.egenmeldingExhausted).toList();
}

class LeaveTeamInsightsService {
  LeaveTeamInsightsService._();

  static TeamLeaveInsightsSnapshot build({
    required List<UserProfile> profiles,
    required List<AbsenceQuota> quotas,
    required List<Absence> absences,
    required CompanyLeaveSettings company,
    required int year,
    required String scopeLabel,
    required bool companyWide,
  }) {
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final quotaByUser = {for (final q in quotas) q.userId: q};

    final daysByType = <AbsenceType, int>{};
    var onVacationToday = 0;
    var pending = 0;

    for (final a in absences) {
      if (a.startDate.year != year && a.endDate.year != year) continue;
      if (a.status == AbsenceStatus.ventende) pending++;
      if (a.status != AbsenceStatus.godkjent) continue;

      final days = a.totalDays ??
          (a.endDate.difference(a.startDate).inDays + 1);
      daysByType[a.type] = (daysByType[a.type] ?? 0) + days;

      if (a.type == AbsenceType.ferie) {
        final start = DateTime(a.startDate.year, a.startDate.month, a.startDate.day);
        final end = DateTime(a.endDate.year, a.endDate.month, a.endDate.day);
        if (!todayOnly.isBefore(start) && !todayOnly.isAfter(end)) {
          onVacationToday++;
        }
      }
    }

    final insights = <EmployeeLeaveInsight>[];
    for (final p in profiles) {
      if (!p.isActive || p.isPartnerPortalUser) continue;
      final q = quotaByUser[p.id];
      final used = q?.egenmeldingDaysUsed ?? 0;
      final cap = company.egenmeldingDaysPerYear;
      insights.add(
        EmployeeLeaveInsight(
          profile: p,
          quota: q,
          egenmeldingUsed: used,
          egenmeldingRemaining: (cap - used).clamp(0, cap),
          egenmeldingPeriodsUsed: q?.egenmeldingPeriodsUsed ?? 0,
          vacationRemaining: q?.vacationDaysRemaining ?? 0,
          vacationUsed: q?.vacationDaysUsed ?? 0,
          vacationTotal: q?.vacationDaysTotal ?? 0,
          absencesYtdDays: absences
              .where((a) =>
                  a.userId == p.id &&
                  a.status == AbsenceStatus.godkjent &&
                  (a.startDate.year == year || a.endDate.year == year))
              .fold<int>(
                0,
                (sum, a) =>
                    sum +
                    (a.totalDays ??
                        (a.endDate.difference(a.startDate).inDays + 1)),
              ),
        ),
      );
    }

    insights.sort((a, b) => a.profile.fullName.compareTo(b.profile.fullName));

    return TeamLeaveInsightsSnapshot(
      scopeLabel: scopeLabel,
      companyWide: companyWide,
      year: year,
      employees: insights,
      daysByTypeYtd: daysByType,
      onVacationToday: onVacationToday,
      egenmeldingExhaustedCount:
          insights.where((e) => e.egenmeldingExhausted).length,
      pendingCount: pending,
    );
  }
}
