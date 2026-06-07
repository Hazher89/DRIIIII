import '../../../core/constants/leave_rules.dart';
import '../../../models/absence.dart';
import '../../../models/user_profile.dart';
import '../../../core/services/absence/employee_leave_stats.dart';

/// Én ansatt rangert etter registrert fravær (egenmelding + sykt barn).
class DepartmentMemberAbsenceRank {
  final String userId;
  final String fullName;
  final String initials;
  final int totalDaysYtd;
  final int egenDays;
  final int syktDays;
  final int egenTilfeller;
  final Map<AbsenceType, int> daysByType;

  const DepartmentMemberAbsenceRank({
    required this.userId,
    required this.fullName,
    required this.initials,
    required this.totalDaysYtd,
    this.egenDays = 0,
    this.syktDays = 0,
    this.egenTilfeller = 0,
    this.daysByType = const {},
  });

  AbsenceType? get dominantType {
    if (daysByType.isEmpty) return null;
    return daysByType.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }
}

/// Fraværsoversikt per avdeling — samme saldo som Team & kalender.
class DepartmentAbsenceOverview {
  final int memberCount;
  final int awayToday;
  final int onVacationToday;
  final int otherAbsenceToday;
  final int pendingCount;
  final int upcomingWeek;
  final int presentCount;
  final int ytdYear;
  /// Sum egenmelding + sykt barn (alle ansattes registrerte saldo).
  final int totalDaysYtd;
  final int registeredEgenDays;
  final int registeredSyktDays;
  final int registeredFerieDays;
  final Map<AbsenceType, int> typeBreakdownYtd;
  final List<DepartmentMemberAbsenceRank> topByAbsence;
  final double averageAbsencePercent;
  final int totalEgenTilfeller;

  const DepartmentAbsenceOverview({
    required this.memberCount,
    this.awayToday = 0,
    this.onVacationToday = 0,
    this.otherAbsenceToday = 0,
    this.pendingCount = 0,
    this.upcomingWeek = 0,
    this.presentCount = 0,
    this.ytdYear = 0,
    this.totalDaysYtd = 0,
    this.registeredEgenDays = 0,
    this.registeredSyktDays = 0,
    this.registeredFerieDays = 0,
    this.typeBreakdownYtd = const {},
    this.topByAbsence = const [],
    this.averageAbsencePercent = 0,
    this.totalEgenTilfeller = 0,
  });

  static const empty = DepartmentAbsenceOverview(memberCount: 0);

  int get presentPercent =>
      memberCount > 0 ? ((presentCount / memberCount) * 100).round().clamp(0, 100) : 100;

  bool get hasActivity =>
      awayToday > 0 || pendingCount > 0 || upcomingWeek > 0;

  bool get allPresent => memberCount > 0 && awayToday == 0 && pendingCount == 0;

  bool get hasYtdInsights =>
      totalDaysYtd > 0 || topByAbsence.isNotEmpty || typeBreakdownYtd.isNotEmpty;

  int get averageAbsencePercentRounded => averageAbsencePercent.round();
}

class DepartmentAbsenceStats {
  DepartmentAbsenceStats._();

  static bool _isActiveOn(Absence a, DateTime day) {
    if (a.status != AbsenceStatus.godkjent) return false;
    final d = DateTime(day.year, day.month, day.day);
    final s = DateTime(a.startDate.year, a.startDate.month, a.startDate.day);
    final e = DateTime(a.endDate.year, a.endDate.month, a.endDate.day);
    return !d.isBefore(s) && !d.isAfter(e);
  }

  static bool _overlapsRange(Absence a, DateTime start, DateTime end) {
    if (a.status != AbsenceStatus.godkjent) return false;
    final s = DateTime(a.startDate.year, a.startDate.month, a.startDate.day);
    final e = DateTime(a.endDate.year, a.endDate.month, a.endDate.day);
    return !e.isBefore(start) && !s.isAfter(end);
  }

  static int _approvedDaysInRangeForType(
    Absence a,
    DateTime rangeStart,
    DateTime rangeEnd,
    Set<AbsenceType> types,
  ) {
    if (a.status != AbsenceStatus.godkjent) return 0;
    if (!types.contains(a.type)) return 0;
    final s = DateTime(a.startDate.year, a.startDate.month, a.startDate.day);
    final e = DateTime(a.endDate.year, a.endDate.month, a.endDate.day);
    final from = s.isBefore(rangeStart) ? rangeStart : s;
    final to = e.isAfter(rangeEnd) ? rangeEnd : e;
    if (to.isBefore(from)) return 0;
    return to.difference(from).inDays + 1;
  }

  static List<Absence> _forDepartment({
    required String departmentId,
    required List<UserProfile> members,
    required List<Absence> allAbsences,
  }) {
    final memberIds = members.map((m) => m.id).toSet();
    return allAbsences.where((a) {
      if (a.departmentId == departmentId) return true;
      return memberIds.contains(a.userId);
    }).toList();
  }

  static List<Absence> _absencesForUser(List<Absence> pool, String userId) =>
      pool.where((a) => a.userId == userId).toList();

  static Map<String, EmployeeLeaveSnapshot> _snapshotsForMembers({
    required List<UserProfile> members,
    required List<Absence> pool,
    CompanyLeaveSettings company = const CompanyLeaveSettings(),
  }) {
    return {
      for (final m in members)
        m.id: EmployeeLeaveSnapshot.compute(
          employee: m,
          employeeAbsences: _absencesForUser(pool, m.id),
          company: company,
        ),
    };
  }

  static Map<AbsenceType, int> _fravaerBreakdownFromSnapshots(
    Iterable<EmployeeLeaveSnapshot> snapshots,
  ) {
    var egen = 0;
    var sykt = 0;
    for (final s in snapshots) {
      egen += s.egenDaysTotal;
      sykt += s.syktDays;
    }
    final map = <AbsenceType, int>{};
    if (egen > 0) map[AbsenceType.egenmelding] = egen;
    if (sykt > 0) map[AbsenceType.syktBarn] = sykt;
    return map;
  }

  static List<DepartmentMemberAbsenceRank> _topMembersFromSnapshots({
    required List<UserProfile> members,
    required Map<String, EmployeeLeaveSnapshot> snapshots,
    int limit = 3,
  }) {
    final ranks = <DepartmentMemberAbsenceRank>[];
    for (final m in members) {
      final snap = snapshots[m.id];
      if (snap == null || snap.totalFravaerDager <= 0) continue;
      final byType = <AbsenceType, int>{};
      if (snap.egenDaysTotal > 0) {
        byType[AbsenceType.egenmelding] = snap.egenDaysTotal;
      }
      if (snap.syktDays > 0) {
        byType[AbsenceType.syktBarn] = snap.syktDays;
      }
      ranks.add(
        DepartmentMemberAbsenceRank(
          userId: m.id,
          fullName: m.fullName,
          initials: m.initials,
          totalDaysYtd: snap.totalFravaerDager,
          egenDays: snap.egenDaysTotal,
          syktDays: snap.syktDays,
          egenTilfeller: snap.egenTilfeller,
          daysByType: Map.unmodifiable(byType),
        ),
      );
    }
    ranks.sort((a, b) => b.totalDaysYtd.compareTo(a.totalDaysYtd));
    return ranks.take(limit).toList();
  }

  static int _registeredFerieDays({
    required Iterable<Absence> pool,
    required int year,
  }) {
    final from = DateTime(year, 1, 1);
    final to = DateTime(year, 12, 31);
    var total = 0;
    for (final a in pool) {
      total += _approvedDaysInRangeForType(
        a,
        from,
        to,
        const {AbsenceType.ferie},
      );
    }
    return total;
  }

  static DepartmentAbsenceOverview forDepartment({
    required String departmentId,
    required List<UserProfile> members,
    required List<Absence> allAbsences,
    DateTime? referenceDate,
    CompanyLeaveSettings company = const CompanyLeaveSettings(),
  }) {
    final today = referenceDate ?? DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    final weekEnd = day.add(const Duration(days: 6));
    final pool = _forDepartment(
      departmentId: departmentId,
      members: members,
      allAbsences: allAbsences,
    );
    final approved = pool.where((a) => a.status == AbsenceStatus.godkjent);

    final snapshots = _snapshotsForMembers(
      members: members,
      pool: pool,
      company: company,
    );
    final typeBreakdown = _fravaerBreakdownFromSnapshots(snapshots.values);
    final registeredEgen = typeBreakdown[AbsenceType.egenmelding] ?? 0;
    final registeredSykt = typeBreakdown[AbsenceType.syktBarn] ?? 0;
    final registeredFerie = _registeredFerieDays(pool: approved, year: day.year);
    final totalFravaer = snapshots.values.fold<int>(
      0,
      (sum, s) => sum + s.totalFravaerDager,
    );
    final leaveSummary = TeamLeaveSummary.compute(
      employees: members,
      allAbsences: pool,
      company: company,
      referenceDate: day,
    );
    final avgPercent = leaveSummary.averageAbsencePercent;
    final totalTilfeller = snapshots.values.fold<int>(
      0,
      (sum, s) => sum + s.egenTilfeller,
    );

    final awayTodayIds = <String>{};
    final vacationIds = <String>{};
    final otherIds = <String>{};

    for (final a in pool) {
      if (!_isActiveOn(a, day)) continue;
      awayTodayIds.add(a.userId);
      if (a.type == AbsenceType.ferie) {
        vacationIds.add(a.userId);
      } else {
        otherIds.add(a.userId);
      }
    }

    final pending = pool.where((a) => a.status == AbsenceStatus.ventende).length;

    final upcoming = pool.where((a) {
      if (!_overlapsRange(a, day.add(const Duration(days: 1)), weekEnd)) {
        return false;
      }
      return !_isActiveOn(a, day);
    }).length;

    final memberCount = members.length;
    final away = awayTodayIds.length;

    return DepartmentAbsenceOverview(
      memberCount: memberCount,
      awayToday: away,
      onVacationToday: vacationIds.length,
      otherAbsenceToday: otherIds.length,
      pendingCount: pending,
      upcomingWeek: upcoming,
      presentCount: memberCount > 0 ? (memberCount - away).clamp(0, memberCount) : 0,
      ytdYear: day.year,
      totalDaysYtd: totalFravaer,
      registeredEgenDays: registeredEgen,
      registeredSyktDays: registeredSykt,
      registeredFerieDays: registeredFerie,
      typeBreakdownYtd: typeBreakdown,
      topByAbsence: _topMembersFromSnapshots(
        members: members,
        snapshots: snapshots,
      ),
      averageAbsencePercent: avgPercent,
      totalEgenTilfeller: totalTilfeller,
    );
  }

  static Map<String, DepartmentAbsenceOverview> forAllDepartments({
    required Iterable<String> departmentIds,
    required Map<String, List<UserProfile>> membersByDept,
    required List<Absence> allAbsences,
    CompanyLeaveSettings company = const CompanyLeaveSettings(),
  }) {
    return {
      for (final id in departmentIds)
        id: forDepartment(
          departmentId: id,
          members: membersByDept[id] ?? const [],
          allAbsences: allAbsences,
          company: company,
        ),
    };
  }
}
