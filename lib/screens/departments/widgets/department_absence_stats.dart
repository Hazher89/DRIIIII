import '../../../core/utils/business_days.dart';
import '../../../models/absence.dart';
import '../../../models/user_profile.dart';

/// Én ansatt rangert etter godkjent fravær hittil i år.
class DepartmentMemberAbsenceRank {
  final String userId;
  final String fullName;
  final String initials;
  final int totalDaysYtd;
  final Map<AbsenceType, int> daysByType;

  const DepartmentMemberAbsenceRank({
    required this.userId,
    required this.fullName,
    required this.initials,
    required this.totalDaysYtd,
    this.daysByType = const {},
  });

  AbsenceType? get dominantType {
    if (daysByType.isEmpty) return null;
    return daysByType.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }
}

/// Månedlig fravær (godkjente dager) for sparkline.
class DepartmentMonthlyAbsencePoint {
  final int year;
  final int month;
  final int days;

  const DepartmentMonthlyAbsencePoint({
    required this.year,
    required this.month,
    required this.days,
  });

  String get shortLabel {
    const names = ['jan', 'feb', 'mar', 'apr', 'mai', 'jun', 'jul', 'aug', 'sep', 'okt', 'nov', 'des'];
    return names[month - 1];
  }
}

/// Fraværsoversikt per avdeling — beregnet fra godkjente/ventende perioder.
class DepartmentAbsenceOverview {
  final int memberCount;
  final int awayToday;
  final int onVacationToday;
  final int otherAbsenceToday;
  final int pendingCount;
  final int upcomingWeek;
  final int presentCount;
  final int ytdYear;
  final int totalDaysYtd;
  final Map<AbsenceType, int> typeBreakdownYtd;
  final List<DepartmentMemberAbsenceRank> topByAbsence;
  final List<DepartmentMonthlyAbsencePoint> monthlyTrend;

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
    this.typeBreakdownYtd = const {},
    this.topByAbsence = const [],
    this.monthlyTrend = const [],
  });

  static const empty = DepartmentAbsenceOverview(memberCount: 0);

  int get presentPercent =>
      memberCount > 0 ? ((presentCount / memberCount) * 100).round().clamp(0, 100) : 100;

  bool get hasActivity =>
      awayToday > 0 || pendingCount > 0 || upcomingWeek > 0;

  bool get allPresent => memberCount > 0 && awayToday == 0 && pendingCount == 0;

  bool get hasYtdInsights =>
      totalDaysYtd > 0 || topByAbsence.isNotEmpty || typeBreakdownYtd.isNotEmpty;
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

  static int _approvedDaysInRange(Absence a, DateTime rangeStart, DateTime rangeEnd) {
    if (a.status != AbsenceStatus.godkjent) return 0;
    final s = DateTime(a.startDate.year, a.startDate.month, a.startDate.day);
    final e = DateTime(a.endDate.year, a.endDate.month, a.endDate.day);
    final from = s.isBefore(rangeStart) ? rangeStart : s;
    final to = e.isAfter(rangeEnd) ? rangeEnd : e;
    if (to.isBefore(from)) return 0;
    if (a.type == AbsenceType.ferie) {
      return BusinessDays.countInRange(from, to);
    }
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

  static Map<AbsenceType, int> _typeBreakdown(
    Iterable<Absence> pool,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) {
    final map = <AbsenceType, int>{};
    for (final a in pool) {
      final days = _approvedDaysInRange(a, rangeStart, rangeEnd);
      if (days <= 0) continue;
      map[a.type] = (map[a.type] ?? 0) + days;
    }
    return map;
  }

  static List<DepartmentMemberAbsenceRank> _topMembers({
    required List<UserProfile> members,
    required Iterable<Absence> pool,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    int limit = 3,
  }) {
    final byUser = <String, Map<AbsenceType, int>>{};
    final nameFromAbsence = <String, String>{};
    for (final a in pool) {
      final days = _approvedDaysInRange(a, rangeStart, rangeEnd);
      if (days <= 0) continue;
      final bucket = byUser.putIfAbsent(a.userId, () => {});
      bucket[a.type] = (bucket[a.type] ?? 0) + days;
      if (a.userName != null && a.userName!.trim().isNotEmpty) {
        nameFromAbsence.putIfAbsent(a.userId, () => a.userName!.trim());
      }
    }

    final nameById = {for (final m in members) m.id: m};
    final ranks = <DepartmentMemberAbsenceRank>[];
    for (final entry in byUser.entries) {
      final profile = nameById[entry.key];
      final name = profile?.fullName ?? nameFromAbsence[entry.key] ?? 'Ansatt';
      final total = entry.value.values.fold<int>(0, (sum, n) => sum + n);
      ranks.add(
        DepartmentMemberAbsenceRank(
          userId: entry.key,
          fullName: name,
          initials: profile?.initials ?? _initialsFromName(name),
          totalDaysYtd: total,
          daysByType: Map.unmodifiable(entry.value),
        ),
      );
    }
    ranks.sort((a, b) => b.totalDaysYtd.compareTo(a.totalDaysYtd));
    return ranks.take(limit).toList();
  }

  static String _initialsFromName(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  static List<DepartmentMonthlyAbsencePoint> _monthlyTrend({
    required Iterable<Absence> pool,
    required DateTime referenceDate,
    int months = 6,
  }) {
    final anchor = DateTime(referenceDate.year, referenceDate.month, 1);
    final points = <DepartmentMonthlyAbsencePoint>[];
    for (var i = months - 1; i >= 0; i--) {
      final m = DateTime(anchor.year, anchor.month - i, 1);
      final monthEnd = DateTime(m.year, m.month + 1, 0);
      var days = 0;
      for (final a in pool) {
        days += _approvedDaysInRange(a, m, monthEnd);
      }
      points.add(DepartmentMonthlyAbsencePoint(year: m.year, month: m.month, days: days));
    }
    return points;
  }

  static DepartmentAbsenceOverview forDepartment({
    required String departmentId,
    required List<UserProfile> members,
    required List<Absence> allAbsences,
    DateTime? referenceDate,
  }) {
    final today = referenceDate ?? DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    final weekEnd = day.add(const Duration(days: 6));
    final ytdStart = DateTime(day.year, 1, 1);
    final pool = _forDepartment(
      departmentId: departmentId,
      members: members,
      allAbsences: allAbsences,
    );
    final approved = pool.where((a) => a.status == AbsenceStatus.godkjent);

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

    final typeBreakdown = _typeBreakdown(approved, ytdStart, day);
    final totalYtd = typeBreakdown.values.fold<int>(0, (sum, n) => sum + n);

    return DepartmentAbsenceOverview(
      memberCount: memberCount,
      awayToday: away,
      onVacationToday: vacationIds.length,
      otherAbsenceToday: otherIds.length,
      pendingCount: pending,
      upcomingWeek: upcoming,
      presentCount: memberCount > 0 ? (memberCount - away).clamp(0, memberCount) : 0,
      ytdYear: day.year,
      totalDaysYtd: totalYtd,
      typeBreakdownYtd: typeBreakdown,
      topByAbsence: _topMembers(
        members: members,
        pool: approved,
        rangeStart: ytdStart,
        rangeEnd: day,
      ),
      monthlyTrend: _monthlyTrend(pool: approved, referenceDate: day),
    );
  }

  static Map<String, DepartmentAbsenceOverview> forAllDepartments({
    required Iterable<String> departmentIds,
    required Map<String, List<UserProfile>> membersByDept,
    required List<Absence> allAbsences,
  }) {
    return {
      for (final id in departmentIds)
        id: forDepartment(
          departmentId: id,
          members: membersByDept[id] ?? const [],
          allAbsences: allAbsences,
        ),
    };
  }
}
