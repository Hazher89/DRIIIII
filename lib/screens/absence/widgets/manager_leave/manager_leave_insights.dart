import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/strategic_goals_2026.dart';
import '../../../../core/services/absence/absence_service.dart';
import '../../../../core/services/absence/employee_leave_stats.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/business_days.dart';
import '../../../../models/absence.dart';
import '../../../../models/user_profile.dart';
import '../leave_period_scope.dart';

class _FerieRow {
  const _FerieRow({
    required this.user,
    required this.used,
    required this.left,
    required this.total,
  });
  final UserProfile user;
  final int used;
  final int left;
  final int total;
  double get usedPct => total <= 0 ? 0 : used / total;
}

class _DriverRow {
  const _DriverRow({
    required this.user,
    required this.days,
    required this.share,
    required this.sykmeldingDays,
  });
  final UserProfile user;
  final int days;
  final double share;
  final int sykmeldingDays;
}

class MonthEmployeeAbsence {
  const MonthEmployeeAbsence({
    required this.userId,
    required this.name,
    required this.days,
    required this.entries,
  });
  final String userId;
  final String name;
  final int days;
  final List<Absence> entries;
}

/// Strategisk fraværs-/ferieinnsikt med diagrammer, rangering og trender.
class ManagerLeaveInsights extends StatelessWidget {
  const ManagerLeaveInsights({
    super.key,
    required this.employees,
    required this.absences,
    required this.quotas,
    required this.scope,
    required this.pending,
    required this.awayToday,
    required this.nextWeekAwayCount,
    required this.onScrollToApprovals,
    this.allAbsencesForLive,
    this.onOpenEmployee,
    this.onOpenAbsence,
  });

  final List<UserProfile> employees;
  /// Absences already filtered to the selected period (år / fra–til).
  final List<Absence> absences;
  /// Full list for live views (borte i dag / snart ferie) — optional.
  final List<Absence>? allAbsencesForLive;
  final List<AbsenceQuota> quotas;
  final LeavePeriodScope scope;
  final List<Absence> pending;
  final List<Absence> awayToday;
  final int nextWeekAwayCount;
  final VoidCallback onScrollToApprovals;
  final void Function(UserProfile employee)? onOpenEmployee;
  final void Function(Absence absence)? onOpenAbsence;

  static const _targetPct = 9.9;
  static const monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mai', 'Jun',
    'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Des',
  ];

  List<Absence> get _live => allAbsencesForLive ?? absences;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    final from = BusinessDays.dayOnly(scope.rangeStart);
    var to = BusinessDays.dayOnly(scope.rangeEnd);
    final today = BusinessDays.dayOnly(now);
    if (to.isAfter(today)) to = today;

    final summary = TeamLeaveSummary.computeForRange(
      employees: employees,
      allAbsences: absences,
      rangeStart: from,
      rangeEnd: to,
    );

    final year = scope.year;
    final ferieRows = <_FerieRow>[];
    for (final e in employees) {
      AbsenceQuota? q;
      for (final item in quotas) {
        if (item.userId == e.id && item.year == year) {
          q = item;
          break;
        }
      }
      final total = q?.totalVacationDays ?? 25;
      final used = q?.vacationDaysUsed ?? 0;
      final left = q?.vacationDaysRemaining ?? total;
      ferieRows.add(_FerieRow(user: e, used: used, left: left, total: total));
    }

    final mostLeft = [...ferieRows]..sort((a, b) => b.left.compareTo(a.left));
    final mostUsed = [...ferieRows]..sort((a, b) => b.used.compareTo(a.used));

    final drivers = <_DriverRow>[];
    for (final e in employees) {
      final pool = absences.where((a) => a.userId == e.id).toList();
      final days = EmployeeLeaveSnapshot.uniqueBusinessDaysInWindow(
        absences: pool,
        rangeStart: from,
        rangeEnd: to,
      );
      if (days <= 0) continue;
      final syk = EmployeeLeaveSnapshot.uniqueBusinessDaysInWindow(
        absences: pool,
        rangeStart: from,
        rangeEnd: to,
        types: {AbsenceType.sykmelding},
      );
      drivers.add(
        _DriverRow(
          user: e,
          days: days,
          share: summary.totalFravaerDays <= 0
              ? 0
              : days / summary.totalFravaerDays,
          sykmeldingDays: syk,
        ),
      );
    }
    drivers.sort((a, b) => b.days.compareTo(a.days));

    final sykPeople = <String>{};
    for (final a in absences) {
      if (a.status != AbsenceStatus.godkjent) continue;
      if (a.type != AbsenceType.sykmelding) continue;
      if (!scope.overlaps(a)) continue;
      sykPeople.add(a.userId);
    }

    final upcomingFerie = _live
        .where((a) =>
            a.type == AbsenceType.ferie &&
            (a.status == AbsenceStatus.godkjent ||
                a.status == AbsenceStatus.ventende) &&
            !BusinessDays.dayOnly(a.endDate).isBefore(today) &&
            BusinessDays.dayOnly(a.startDate).difference(today).inDays <= 45)
        .toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));

    final monthly = _monthlyAbsenceDays(absences, from, to);
    final monthPeople = _monthlyPeople(absences, from, to, employees);
    final peakMonth = _peakMonth(monthly);
    final trend = _recentTrend(absences, now);

    final rate = summary.averageAbsencePercent;
    final overTarget = rate > _targetPct;
    final nearTarget = rate >= _targetPct * 0.75 && !overTarget;
    final rateColor = overTarget
        ? DriftProTheme.error
        : nearTarget
            ? DriftProTheme.warning
            : DriftProTheme.success;

    StrategicGoal? goal;
    for (final g in StrategicGoals2026.goals) {
      if (g.id == 'fravaer') {
        goal = g;
        break;
      }
    }

    final workDays = BusinessDays.countInRange(from, to);
    final capacityPct = employees.isEmpty
        ? 100
        : (((employees.length - nextWeekAwayCount) / employees.length) * 100)
            .round()
            .clamp(0, 100);
    final fteSyk = workDays > 0
        ? (summary.totalSykmeldingDays / workDays)
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pending.isNotEmpty) ...[
          _PendingPeopleBanner(
            pending: pending,
            onTap: onScrollToApprovals,
            onOpen: onOpenAbsence,
            isDark: isDark,
          ),
          const SizedBox(height: 12),
        ],
        _card(
          isDark: isDark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Innsikt · ${scope.shortLabel}',
                          style: DriftProTheme.labelLg
                              .copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          goal?.description ??
                              'Fravær og ferie mot strategiske mål',
                          style: DriftProTheme.caption
                              .copyWith(color: const Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  _StatusChip(
                    label: overTarget
                        ? 'Over mål'
                        : nearTarget
                            ? 'Nær mål'
                            : 'Innenfor mål',
                    color: rateColor,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, c) {
                  final wide = c.maxWidth >= 900;
                  final left = _RateHero(
                    rate: rate,
                    color: rateColor,
                    target: _targetPct,
                    fravaerDays: summary.totalFravaerDays,
                    sykmeldingDays: summary.totalSykmeldingDays,
                    sykmeldingPeople: sykPeople.length,
                    fteEquivalent: fteSyk,
                    employeeCount: employees.length,
                    workDays: workDays,
                    trend: trend,
                  );
                  final right = _TopDriversCard(
                    drivers: drivers.take(5).toList(),
                    totalDays: summary.totalFravaerDays,
                    onOpen: onOpenEmployee,
                    isDark: isDark,
                  );
                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 5, child: left),
                        const SizedBox(width: 12),
                        Expanded(flex: 5, child: right),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      left,
                      const SizedBox(height: 10),
                      right,
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              _UpcomingFeriePanel(
                items: upcomingFerie.take(8).toList(),
                onOpen: onOpenAbsence,
                onOpenEmployee: onOpenEmployee,
                employees: employees,
                isDark: isDark,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetricPill(
                    icon: Icons.event_busy_outlined,
                    label: 'Borte i dag',
                    value: '${awayToday.length}',
                    color: awayToday.isEmpty
                        ? DriftProTheme.primaryGreen
                        : DriftProTheme.warning,
                  ),
                  _MetricPill(
                    icon: Icons.medical_services_outlined,
                    label: 'Sykmelding',
                    value:
                        '${summary.totalSykmeldingDays} person-d · ${sykPeople.length} ans.',
                    color: DriftProTheme.absenceSickNote,
                  ),
                  _MetricPill(
                    icon: Icons.sick_outlined,
                    label: 'Egenmelding',
                    value: '${summary.totalEgenDays} d',
                    color: DriftProTheme.absenceSickSelf,
                  ),
                  _MetricPill(
                    icon: Icons.child_care_outlined,
                    label: 'Sykt barn',
                    value: '${summary.totalSyktDays} d',
                    color: DriftProTheme.absenceSickChild,
                  ),
                  _MetricPill(
                    icon: Icons.event_available_outlined,
                    label: 'Neste uke',
                    value: '$capacityPct% kap.',
                    color: DriftProTheme.absenceVacation,
                  ),
                  if (pending.isEmpty)
                    const _MetricPill(
                      icon: Icons.check_circle_outline,
                      label: 'Godkjenning',
                      value: 'OK',
                      color: DriftProTheme.success,
                    )
                  else
                    _MetricPill(
                      icon: Icons.pending_actions_outlined,
                      label: 'Venter',
                      value: '${pending.length}',
                      color: DriftProTheme.warning,
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _card(
          isDark: isDark,
          child: _MonthlyAbsenceChart(
            year: year,
            monthly: monthly,
            monthPeople: monthPeople,
            peakMonth: peakMonth,
            currentMonth: year == now.year ? now.month - 1 : peakMonth,
            isDark: isDark,
            onOpenEmployee: onOpenEmployee,
            onOpenAbsence: onOpenAbsence,
            employees: employees,
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 900;
            final leftRank = _RankPanel(
              title: 'Mest ferie igjen',
              subtitle: 'Hvem har flest dager igjen i $year',
              rows: mostLeft.take(5).toList(),
              mode: _RankMode.left,
              onOpen: onOpenEmployee,
              isDark: isDark,
            );
            final rightRank = _RankPanel(
              title: 'Mest ferie brukt',
              subtitle: 'Hvem har tatt ut flest dager',
              rows: mostUsed.where((r) => r.used > 0).take(5).toList(),
              mode: _RankMode.used,
              onOpen: onOpenEmployee,
              isDark: isDark,
            );
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: leftRank),
                  const SizedBox(width: 12),
                  Expanded(child: rightRank),
                ],
              );
            }
            return Column(
              children: [
                leftRank,
                const SizedBox(height: 12),
                rightRank,
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Tallene er person-virkedager (ikke antall sykmeldinger). '
          'Overlappende perioder telles én gang per ansatt. '
          '${DateFormat('d. MMM', 'nb_NO').format(from)} – '
          '${DateFormat('d. MMM yyyy', 'nb_NO').format(to)} · '
          '$workDays virkedager',
          style: DriftProTheme.caption.copyWith(
            color: const Color(0xFF94A3B8),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  static List<double> _monthlyAbsenceDays(
    List<Absence> absences,
    DateTime from,
    DateTime to,
  ) {
    final months = List<double>.filled(12, 0);
    for (var m = 0; m < 12; m++) {
      final monthStart = DateTime(from.year, m + 1, 1);
      final monthEnd = DateTime(from.year, m + 2, 0);
      final s = monthStart.isBefore(from) ? from : monthStart;
      final e = monthEnd.isAfter(to) ? to : monthEnd;
      if (e.isBefore(s)) continue;
      // Sum unique days per employee then total (person-days).
      final byUser = <String, Set<int>>{};
      for (final a in absences) {
        if (a.status != AbsenceStatus.godkjent) continue;
        if (!EmployeeLeaveSnapshot.kpiAbsenceTypes.contains(a.type)) continue;
        var day = BusinessDays.dayOnly(a.startDate);
        final end = BusinessDays.dayOnly(a.endDate);
        while (!day.isAfter(end)) {
          if (!day.isBefore(s) &&
              !day.isAfter(e) &&
              BusinessDays.isBusinessDay(day)) {
            byUser
                .putIfAbsent(a.userId, () => <int>{})
                .add(day.millisecondsSinceEpoch);
          }
          day = day.add(const Duration(days: 1));
        }
      }
      months[m] = byUser.values.fold<int>(0, (n, set) => n + set.length).toDouble();
    }
    return months;
  }

  static Map<int, List<MonthEmployeeAbsence>> _monthlyPeople(
    List<Absence> absences,
    DateTime from,
    DateTime to,
    List<UserProfile> employees,
  ) {
    final names = {for (final e in employees) e.id: e.fullName};
    final result = <int, List<MonthEmployeeAbsence>>{};
    for (var m = 0; m < 12; m++) {
      final monthStart = DateTime(from.year, m + 1, 1);
      final monthEnd = DateTime(from.year, m + 2, 0);
      final s = monthStart.isBefore(from) ? from : monthStart;
      final e = monthEnd.isAfter(to) ? to : monthEnd;
      if (e.isBefore(s)) {
        result[m] = const [];
        continue;
      }
      final daysByUser = <String, Set<int>>{};
      final entriesByUser = <String, List<Absence>>{};
      for (final a in absences) {
        if (a.status != AbsenceStatus.godkjent) continue;
        if (!EmployeeLeaveSnapshot.kpiAbsenceTypes.contains(a.type)) continue;
        var day = BusinessDays.dayOnly(a.startDate);
        final end = BusinessDays.dayOnly(a.endDate);
        var hit = false;
        while (!day.isAfter(end)) {
          if (!day.isBefore(s) &&
              !day.isAfter(e) &&
              BusinessDays.isBusinessDay(day)) {
            daysByUser
                .putIfAbsent(a.userId, () => <int>{})
                .add(day.millisecondsSinceEpoch);
            hit = true;
          }
          day = day.add(const Duration(days: 1));
        }
        if (hit) {
          entriesByUser.putIfAbsent(a.userId, () => []).add(a);
        }
      }
      final rows = daysByUser.entries
          .map(
            (e) => MonthEmployeeAbsence(
              userId: e.key,
              name: names[e.key] ??
                  entriesByUser[e.key]?.first.userName ??
                  'Ansatt',
              days: e.value.length,
              entries: entriesByUser[e.key] ?? const [],
            ),
          )
          .toList()
        ..sort((a, b) => b.days.compareTo(a.days));
      result[m] = rows;
    }
    return result;
  }

  static int _peakMonth(List<double> monthly) {
    var peak = 0;
    for (var i = 1; i < monthly.length; i++) {
      if (monthly[i] > monthly[peak]) peak = i;
    }
    return peak;
  }

  static ({double deltaPct, bool up}) _recentTrend(
    List<Absence> absences,
    DateTime now,
  ) {
    final today = BusinessDays.dayOnly(now);
    final curStart = today.subtract(const Duration(days: 29));
    final prevEnd = curStart.subtract(const Duration(days: 1));
    final prevStart = prevEnd.subtract(const Duration(days: 29));

    int daysIn(DateTime from, DateTime to) {
      final byUser = <String, Set<int>>{};
      for (final a in absences) {
        if (a.status != AbsenceStatus.godkjent) continue;
        if (!EmployeeLeaveSnapshot.kpiAbsenceTypes.contains(a.type)) continue;
        var day = BusinessDays.dayOnly(a.startDate);
        final end = BusinessDays.dayOnly(a.endDate);
        while (!day.isAfter(end)) {
          if (!day.isBefore(from) &&
              !day.isAfter(to) &&
              BusinessDays.isBusinessDay(day)) {
            byUser
                .putIfAbsent(a.userId, () => <int>{})
                .add(day.millisecondsSinceEpoch);
          }
          day = day.add(const Duration(days: 1));
        }
      }
      return byUser.values.fold<int>(0, (n, s) => n + s.length);
    }

    final cur = daysIn(curStart, today).toDouble();
    final prev = daysIn(prevStart, prevEnd).toDouble();
    if (prev <= 0) {
      return (deltaPct: cur > 0 ? 100.0 : 0.0, up: cur > 0);
    }
    final delta = ((cur - prev) / prev) * 100;
    return (deltaPct: delta.abs(), up: delta > 0.5);
  }

  Widget _card({required bool isDark, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? DriftProTheme.dividerDark : const Color(0xFFE8EEF0),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.035),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: child,
    );
  }
}

// ── Scope filters ─────────────────────────────────────────────────────────────

class ManagerLeaveScopeFilters extends StatelessWidget {
  const ManagerLeaveScopeFilters({
    super.key,
    required this.employees,
    required this.departmentNames,
    required this.departmentId,
    required this.employeeId,
    required this.onDepartmentChanged,
    required this.onEmployeeChanged,
  });

  final List<UserProfile> employees;
  final Map<String, String> departmentNames;
  final String? departmentId;
  final String? employeeId;
  final ValueChanged<String?> onDepartmentChanged;
  final ValueChanged<String?> onEmployeeChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final deptIds = employees
        .map((e) => e.departmentId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => (departmentNames[a] ?? a)
          .compareTo(departmentNames[b] ?? b));

    final scoped = departmentId == null
        ? employees
        : employees.where((e) => e.departmentId == departmentId).toList();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? DriftProTheme.dividerDark : const Color(0xFFE8EEF0),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final wrap = c.maxWidth < 640;
          final dept = _filterField(
            label: 'Avdeling',
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: departmentId,
                isExpanded: true,
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Alle avdelinger'),
                  ),
                  for (final id in deptIds)
                    DropdownMenuItem(
                      value: id,
                      child: Text(
                        departmentNames[id] ?? 'Uten navn',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: onDepartmentChanged,
              ),
            ),
          );
          final emp = _filterField(
            label: 'Ansatt',
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: employeeId,
                isExpanded: true,
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Alle ansatte'),
                  ),
                  for (final e in scoped)
                    DropdownMenuItem(
                      value: e.id,
                      child: Text(e.fullName, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: onEmployeeChanged,
              ),
            ),
          );
          if (wrap) {
            return Column(children: [dept, const SizedBox(height: 8), emp]);
          }
          return Row(
            children: [
              Expanded(child: dept),
              const SizedBox(width: 10),
              Expanded(child: emp),
            ],
          );
        },
      ),
    );
  }

  Widget _filterField({required String label, required Widget child}) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: child,
    );
  }
}

// ── Private UI ────────────────────────────────────────────────────────────────

class _PendingPeopleBanner extends StatelessWidget {
  const _PendingPeopleBanner({
    required this.pending,
    required this.onTap,
    required this.isDark,
    this.onOpen,
  });

  final List<Absence> pending;
  final VoidCallback onTap;
  final bool isDark;
  final void Function(Absence)? onOpen;

  @override
  Widget build(BuildContext context) {
    final names = pending
        .map((a) => (a.userName ?? 'Ansatt').split(' ').first)
        .toSet()
        .take(4)
        .join(', ');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                DriftProTheme.warning.withValues(alpha: isDark ? 0.22 : 0.16),
                DriftProTheme.warning.withValues(alpha: isDark ? 0.08 : 0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: DriftProTheme.warning.withValues(alpha: 0.45),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.pending_actions_rounded,
                      color: Color(0xFFB45309)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${pending.length} ${pending.length == 1 ? 'søknad' : 'søknader'} venter på godkjenning',
                      style: DriftProTheme.labelMd.copyWith(
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF9A3412),
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFB45309),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Behandle',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              if (names.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Fra $names${pending.length > 4 ? ' m.fl.' : ''}',
                  style: DriftProTheme.caption.copyWith(
                    color: const Color(0xFF9A3412).withValues(alpha: 0.85),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              ...pending.take(3).map((a) {
                final days = a.type == AbsenceType.ferie
                    ? (a.vacationDayCount ??
                        AbsenceService.vacationDayCount(
                          a.startDate,
                          a.endDate,
                        ))
                    : (a.totalDays ??
                        AbsenceService.dayCount(a.startDate, a.endDate));
                final df = DateFormat('d. MMM', 'nb_NO');
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: InkWell(
                    onTap: onOpen == null ? null : () => onOpen!(a),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${a.userName ?? 'Ansatt'} · ${a.type.label}',
                              style: DriftProTheme.bodySm
                                  .copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          Text(
                            '${df.format(a.startDate)} · $days d',
                            style: DriftProTheme.caption.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class _RateHero extends StatelessWidget {
  const _RateHero({
    required this.rate,
    required this.color,
    required this.target,
    required this.fravaerDays,
    required this.sykmeldingDays,
    required this.sykmeldingPeople,
    required this.fteEquivalent,
    required this.employeeCount,
    required this.workDays,
    required this.trend,
  });

  final double rate;
  final Color color;
  final double target;
  final int fravaerDays;
  final int sykmeldingDays;
  final int sykmeldingPeople;
  final double fteEquivalent;
  final int employeeCount;
  final int workDays;
  final ({double deltaPct, bool up}) trend;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            height: 88,
            child: CustomPaint(
              painter: _RingPainter(
                progress: (rate / (target * 1.6)).clamp(0.0, 1.0),
                color: color,
                track: color.withValues(alpha: 0.15),
              ),
              child: Center(
                child: Text(
                  '${rate.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: color,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Fraværsprosent',
                  style: DriftProTheme.labelMd
                      .copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  'Mål ≤ ${target.toStringAsFixed(1)}%',
                  style: DriftProTheme.caption.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$fravaerDays person-dager · $employeeCount ansatte · $workDays virkedager',
                  style: DriftProTheme.caption
                      .copyWith(color: const Color(0xFF64748B)),
                ),
                if (sykmeldingDays > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Sykmelding: $sykmeldingDays person-dager hos $sykmeldingPeople '
                    '${sykmeldingPeople == 1 ? 'ansatt' : 'ansatte'}'
                    '${fteEquivalent >= 0.1 ? ' (≈ ${fteEquivalent.toStringAsFixed(1)} årsverk)' : ''}',
                    style: DriftProTheme.caption.copyWith(
                      color: DriftProTheme.absenceSickNote,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                _TrendBadge(trend: trend),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendBadge extends StatelessWidget {
  const _TrendBadge({required this.trend});
  final ({double deltaPct, bool up}) trend;

  @override
  Widget build(BuildContext context) {
    final worse = trend.up;
    final color = worse ? DriftProTheme.error : DriftProTheme.success;
    final icon =
        worse ? Icons.trending_up_rounded : Icons.trending_down_rounded;
    final label = trend.deltaPct < 0.5
        ? 'Stabilt siste 30 dager'
        : worse
            ? '+${trend.deltaPct.toStringAsFixed(0)}% fravær siste 30 d'
            : '−${trend.deltaPct.toStringAsFixed(0)}% fravær siste 30 d';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopDriversCard extends StatelessWidget {
  const _TopDriversCard({
    required this.drivers,
    required this.totalDays,
    required this.isDark,
    this.onOpen,
  });

  final List<_DriverRow> drivers;
  final int totalDays;
  final bool isDark;
  final void Function(UserProfile)? onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : DriftProTheme.error.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: DriftProTheme.error.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Største bidrag til fravær',
            style: DriftProTheme.labelMd.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            totalDays <= 0
                ? 'Ingen fravær i perioden'
                : 'Hvem driver opp prosenten ($totalDays person-dager)',
            style: DriftProTheme.caption.copyWith(
              color: DriftProTheme.error.withValues(alpha: 0.85),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          if (drivers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('Ingen data', style: DriftProTheme.caption),
            )
          else
            for (var i = 0; i < drivers.length; i++)
              _driverRow(drivers[i], i + 1),
        ],
      ),
    );
  }

  Widget _driverRow(_DriverRow row, int place) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onOpen == null ? null : () => onOpen!(row.user),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Text(
                '$place',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF94A3B8),
                  fontSize: 12,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.user.fullName,
                    overflow: TextOverflow.ellipsis,
                    style: DriftProTheme.bodySm
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: row.share.clamp(0.0, 1.0),
                      minHeight: 4,
                      backgroundColor: const Color(0xFFE2E8F0),
                      color: row.sykmeldingDays > 0
                          ? DriftProTheme.absenceSickNote
                          : DriftProTheme.error,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${row.days} d',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
                Text(
                  '${(row.share * 100).round()}%',
                  style: DriftProTheme.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthlyAbsenceChart extends StatefulWidget {
  const _MonthlyAbsenceChart({
    required this.year,
    required this.monthly,
    required this.monthPeople,
    required this.peakMonth,
    required this.currentMonth,
    required this.isDark,
    required this.employees,
    this.onOpenEmployee,
    this.onOpenAbsence,
  });

  final int year;
  final List<double> monthly;
  final Map<int, List<MonthEmployeeAbsence>> monthPeople;
  final int peakMonth;
  final int currentMonth;
  final bool isDark;
  final List<UserProfile> employees;
  final void Function(UserProfile)? onOpenEmployee;
  final void Function(Absence)? onOpenAbsence;

  @override
  State<_MonthlyAbsenceChart> createState() => _MonthlyAbsenceChartState();
}

class _MonthlyAbsenceChartState extends State<_MonthlyAbsenceChart> {
  final _layerLink = LayerLink();
  final _portal = OverlayPortalController();
  int? _hoverMonth;
  Offset? _hoverLocal;
  double _chartWidth = 400;

  void _clearHover() {
    if (_hoverMonth == null && _hoverLocal == null && !_portal.isShowing) {
      return;
    }
    setState(() {
      _hoverMonth = null;
      _hoverLocal = null;
    });
    if (_portal.isShowing) _portal.hide();
  }

  void _setHover(int month, Offset? local) {
    if (_hoverMonth == month && _hoverLocal == local) return;
    setState(() {
      _hoverMonth = month;
      _hoverLocal = local;
    });
    if (!_portal.isShowing) _portal.show();
  }

  Offset _anchorFor(int month, List<double> monthly, double chartMaxY) {
    const chartH = 180.0;
    const leftPad = 28.0;
    const bottomPad = 22.0;
    final plotW = (_chartWidth - leftPad).clamp(1.0, 9999.0);
    final plotH = chartH - bottomPad;
    final x = leftPad + (month / 11) * plotW;
    final y = plotH - (monthly[month] / chartMaxY) * plotH;
    return _hoverLocal ?? Offset(x, y.clamp(8.0, plotH));
  }

  @override
  Widget build(BuildContext context) {
    final monthly = widget.monthly;
    final maxY = monthly.fold<double>(0, math.max);
    final chartMaxY = (maxY * 1.25).clamp(4.0, double.infinity).toDouble();
    final spots = <FlSpot>[
      for (var i = 0; i < 12; i++) FlSpot(i.toDouble(), monthly[i]),
    ];
    final peakLabel = ManagerLeaveInsights.monthNames[widget.peakMonth];
    final mom = _monthOverMonth(monthly, widget.currentMonth);
    final selected = _hoverMonth;
    final people = selected == null
        ? const <MonthEmployeeAbsence>[]
        : (widget.monthPeople[selected] ?? const []);

    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) {
        if (selected == null) return const SizedBox.shrink();
        final anchor = _anchorFor(selected, monthly, chartMaxY);
        final offset = _FloatingMonthPopup.offsetFor(
          anchor: anchor,
          chartWidth: _chartWidth,
          peopleCount: people.length,
        );
        // Root overlay — over «Mest ferie»-kortene under diagrammet.
        return CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          targetAnchor: Alignment.topLeft,
          followerAnchor: Alignment.topLeft,
          offset: offset,
          child: _FloatingMonthPopup(
            monthIndex: selected,
            year: widget.year,
            totalDays: monthly[selected].round(),
            people: people,
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fravær per måned ${widget.year}',
                      style: DriftProTheme.labelLg
                          .copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      maxY <= 0
                          ? 'Ingen fraværsdager registrert ennå'
                          : 'Mest fravær i $peakLabel (${monthly[widget.peakMonth].round()} person-dager) · hold over prikk for detaljer',
                      style: DriftProTheme.caption
                          .copyWith(color: const Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              if (mom != null) _MomChip(mom: mom),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              const chartH = 180.0;
              const leftPad = 28.0;
              if (_chartWidth != constraints.maxWidth) {
                _chartWidth = constraints.maxWidth;
              }

              return CompositedTransformTarget(
                link: _layerLink,
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: chartH,
                  child: maxY <= 0
                      ? Center(
                          child: Text(
                            'Ingen data å vise',
                            style: DriftProTheme.caption,
                          ),
                        )
                      : MouseRegion(
                          onHover: (e) =>
                              setState(() => _hoverLocal = e.localPosition),
                          onExit: (_) => _clearHover(),
                          child: LineChart(
                            LineChartData(
                              minX: 0,
                              maxX: 11,
                              minY: 0,
                              maxY: chartMaxY,
                              gridData: FlGridData(
                                show: true,
                                drawVerticalLine: false,
                                getDrawingHorizontalLine: (v) => FlLine(
                                  color: widget.isDark
                                      ? Colors.white12
                                      : const Color(0xFFE2E8F0),
                                  strokeWidth: 1,
                                ),
                              ),
                              borderData: FlBorderData(show: false),
                              titlesData: FlTitlesData(
                                topTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                                rightTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                                leftTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: leftPad,
                                    getTitlesWidget: (v, m) => Text(
                                      v.toInt().toString(),
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFF94A3B8),
                                      ),
                                    ),
                                  ),
                                ),
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    interval: 1,
                                    getTitlesWidget: (v, m) {
                                      final i = v.toInt();
                                      if (i < 0 || i > 11) {
                                        return const SizedBox.shrink();
                                      }
                                      final active = i == selected ||
                                          i == widget.peakMonth;
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Text(
                                          ManagerLeaveInsights.monthNames[i],
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: active
                                                ? FontWeight.w900
                                                : FontWeight.w600,
                                            color: active
                                                ? DriftProTheme.error
                                                : const Color(0xFF94A3B8),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              lineTouchData: LineTouchData(
                                enabled: true,
                                handleBuiltInTouches: false,
                                touchTooltipData: const LineTouchTooltipData(
                                  getTooltipItems: _emptyTooltipItems,
                                ),
                                getTouchedSpotIndicator: (bar, indexes) =>
                                    indexes
                                        .map(
                                          (i) => TouchedSpotIndicatorData(
                                            FlLine(
                                              color: DriftProTheme.primaryGreen
                                                  .withValues(alpha: 0.45),
                                              strokeWidth: 1.5,
                                              dashArray: [4, 3],
                                            ),
                                            FlDotData(
                                              show: true,
                                              getDotPainter:
                                                  (spot, pct, b, idx) =>
                                                      FlDotCirclePainter(
                                                radius: 6,
                                                color: DriftProTheme
                                                    .primaryGreenDark,
                                                strokeWidth: 2,
                                                strokeColor: Colors.white,
                                              ),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                touchCallback: (event, response) {
                                  if (event is FlPointerExitEvent) {
                                    _clearHover();
                                    return;
                                  }
                                  final spot =
                                      response?.lineBarSpots?.firstOrNull;
                                  if (spot == null) {
                                    if (event is FlPanEndEvent ||
                                        event is FlLongPressEnd ||
                                        event is FlTapUpEvent) {
                                      _clearHover();
                                    }
                                    return;
                                  }
                                  final m = spot.x.round().clamp(0, 11);
                                  Offset? local;
                                  if (event is FlPointerHoverEvent) {
                                    local = event.localPosition;
                                  } else if (event is FlTapDownEvent) {
                                    local = event.localPosition;
                                  } else if (event is FlLongPressMoveUpdate) {
                                    local = event.localPosition;
                                  } else if (event is FlPanUpdateEvent) {
                                    local = event.localPosition;
                                  }
                                  _setHover(m, local ?? _hoverLocal);
                                },
                              ),
                              lineBarsData: [
                                LineChartBarData(
                                  spots: spots,
                                  isCurved: true,
                                  color: DriftProTheme.primaryGreen,
                                  barWidth: 3,
                                  dotData: FlDotData(
                                    show: true,
                                    getDotPainter: (spot, pct, bar, i) {
                                      final peak = i == widget.peakMonth;
                                      final hover = i == selected;
                                      return FlDotCirclePainter(
                                        radius: hover || peak ? 5.5 : 3.2,
                                        color: hover
                                            ? DriftProTheme.primaryGreenDark
                                            : peak
                                                ? DriftProTheme.error
                                                : DriftProTheme.primaryGreen,
                                        strokeWidth: hover ? 2 : 0,
                                        strokeColor: Colors.white,
                                      );
                                    },
                                  ),
                                  belowBarData: BarAreaData(
                                    show: true,
                                    color: DriftProTheme.primaryGreen
                                        .withValues(alpha: 0.12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  static List<LineTooltipItem?> _emptyTooltipItems(List<LineBarSpot> spots) =>
      spots.map((_) => null).toList();

  static ({bool up, double pct, String label})? _monthOverMonth(
    List<double> monthly,
    int currentMonth,
  ) {
    if (currentMonth <= 0 || currentMonth >= monthly.length) return null;
    final cur = monthly[currentMonth];
    final prev = monthly[currentMonth - 1];
    final curName = ManagerLeaveInsights.monthNames[currentMonth];
    final prevName = ManagerLeaveInsights.monthNames[currentMonth - 1];
    if (prev <= 0 && cur <= 0) return null;
    if (prev <= 0) {
      return (up: true, pct: 100, label: '$curName vs $prevName');
    }
    final delta = ((cur - prev) / prev) * 100;
    if (delta.abs() < 0.5) {
      return (up: false, pct: 0, label: 'Stabilt $curName');
    }
    return (up: delta > 0, pct: delta.abs(), label: '$curName vs $prevName');
  }
}

class _FloatingMonthPopup extends StatelessWidget {
  const _FloatingMonthPopup({
    required this.monthIndex,
    required this.year,
    required this.totalDays,
    required this.people,
  });

  final int monthIndex;
  final int year;
  final int totalDays;
  final List<MonthEmployeeAbsence> people;

  static const popupW = 260.0;

  static Offset offsetFor({
    required Offset anchor,
    required double chartWidth,
    required int peopleCount,
  }) {
    final rows = peopleCount.clamp(0, 5);
    final estimatedH = 72.0 + rows * 36.0;
    var left = anchor.dx - popupW / 2;
    left = left.clamp(4.0, math.max(4.0, chartWidth - popupW - 4));
    var top = anchor.dy - estimatedH - 12;
    // Prefer above; if far above chart origin, flip below the point.
    if (top < -160) top = anchor.dy + 14;
    return Offset(left, top);
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d. MMM', 'nb_NO');
    final month = ManagerLeaveInsights.monthNames[monthIndex];
    final rows = people.take(5).toList();

    return IgnorePointer(
      child: Material(
        elevation: 24,
        shadowColor: Colors.black54,
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xFF0F172A),
        child: SizedBox(
          width: popupW,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$month $year',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
                Text(
                  '$totalDays person-d · ${people.length} ${people.length == 1 ? 'ansatt' : 'ansatte'}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (rows.isEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Ingen fravær',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 12,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  for (final p in rows) ...[
                    Text(
                      p.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    for (final a in p.entries.take(2))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          '${a.type.label} · ${df.format(a.startDate)}–${df.format(a.endDate)} · ${p.days} d',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.78),
                            fontSize: 11,
                            height: 1.25,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (p != rows.last) const SizedBox(height: 6),
                  ],
                  if (people.length > rows.length) ...[
                    const SizedBox(height: 4),
                    Text(
                      '+${people.length - rows.length} flere…',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MomChip extends StatelessWidget {
  const _MomChip({required this.mom});
  final ({bool up, double pct, String label}) mom;

  @override
  Widget build(BuildContext context) {
    final worse = mom.up;
    final color = mom.pct < 0.5
        ? const Color(0xFF64748B)
        : worse
            ? DriftProTheme.error
            : DriftProTheme.success;
    final icon = mom.pct < 0.5
        ? Icons.horizontal_rule_rounded
        : worse
            ? Icons.arrow_upward_rounded
            : Icons.arrow_downward_rounded;
    final value = mom.pct < 0.5
        ? '±0%'
        : '${worse ? '+' : '−'}${mom.pct.toStringAsFixed(0)}%';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: color,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          Text(
            mom.label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

enum _RankMode { left, used }

class _RankPanel extends StatelessWidget {
  const _RankPanel({
    required this.title,
    required this.subtitle,
    required this.rows,
    required this.mode,
    required this.isDark,
    this.onOpen,
  });

  final String title;
  final String subtitle;
  final List<_FerieRow> rows;
  final _RankMode mode;
  final bool isDark;
  final void Function(UserProfile)? onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? DriftProTheme.dividerDark : const Color(0xFFE8EEF0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: DriftProTheme.labelLg.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: DriftProTheme.caption.copyWith(color: const Color(0xFF64748B)),
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                mode == _RankMode.used
                    ? 'Ingen har tatt ut ferie ennå'
                    : 'Ingen data',
                style: DriftProTheme.caption,
              ),
            )
          else
            for (var i = 0; i < rows.length; i++) _rankRow(rows[i], i + 1),
        ],
      ),
    );
  }

  Widget _rankRow(_FerieRow row, int place) {
    final value = mode == _RankMode.left ? row.left : row.used;
    final accent = mode == _RankMode.left
        ? DriftProTheme.primaryGreen
        : DriftProTheme.absenceVacation;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onOpen == null ? null : () => onOpen!(row.user),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$place',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: accent,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.user.fullName,
                        overflow: TextOverflow.ellipsis,
                        style: DriftProTheme.bodySm
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: row.usedPct.clamp(0.0, 1.0),
                          minHeight: 4,
                          backgroundColor: const Color(0xFFE2E8F0),
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  mode == _RankMode.left ? '$value d igjen' : '$value d brukt',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: accent,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UpcomingFeriePanel extends StatelessWidget {
  const _UpcomingFeriePanel({
    required this.items,
    required this.employees,
    required this.isDark,
    this.onOpen,
    this.onOpenEmployee,
  });

  final List<Absence> items;
  final List<UserProfile> employees;
  final bool isDark;
  final void Function(Absence)? onOpen;
  final void Function(UserProfile)? onOpenEmployee;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d. MMM', 'nb_NO');
    final accent = DriftProTheme.absenceVacation;
    final peopleCount = items.map((a) => a.userId).toSet().length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : accent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.beach_access_rounded, color: accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Kommende ferie',
                      style: DriftProTheme.labelMd
                          .copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      items.isEmpty
                          ? 'Ingen planlagt ferie de neste 45 dagene'
                          : '$peopleCount ${peopleCount == 1 ? 'ansatt' : 'ansatte'} · ${items.length} perioder neste 45 dager',
                      style: DriftProTheme.caption.copyWith(
                        color: accent.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (items.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${items.length}',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: accent,
                      fontSize: 13,
                    ),
                  ),
                ),
            ],
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 14, 0, 4),
              child: Text(
                'Når noen søker eller får godkjent ferie, vises de her.',
                style: DriftProTheme.caption.copyWith(
                  color: const Color(0xFF94A3B8),
                ),
              ),
            )
          else ...[
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, c) {
                final wide = c.maxWidth >= 640;
                final tiles = [
                  for (final a in items)
                    _upcomingTile(
                      a: a,
                      df: df,
                      accent: accent,
                    ),
                ];
                if (!wide) {
                  return Column(
                    children: [
                      for (var i = 0; i < tiles.length; i++) ...[
                        if (i > 0) const SizedBox(height: 8),
                        tiles[i],
                      ],
                    ],
                  );
                }
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in tiles)
                      SizedBox(
                        width: (c.maxWidth - 8) / 2,
                        child: t,
                      ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _upcomingTile({
    required Absence a,
    required DateFormat df,
    required Color accent,
  }) {
    final days = a.vacationDayCount ??
        AbsenceService.vacationDayCount(a.startDate, a.endDate);
    final pending = a.status == AbsenceStatus.ventende;
    final today = BusinessDays.dayOnly(DateTime.now());
    final start = BusinessDays.dayOnly(a.startDate);
    final end = BusinessDays.dayOnly(a.endDate);
    final ongoing = !today.isBefore(start) && !today.isAfter(end);
    UserProfile? emp;
    for (final e in employees) {
      if (e.id == a.userId) {
        emp = e;
        break;
      }
    }
    final daysUntil = start.difference(today).inDays;
    final whenLabel = ongoing
        ? 'Pågår nå'
        : daysUntil == 0
            ? 'Starter i dag'
            : daysUntil == 1
                ? 'I morgen'
                : 'Om $daysUntil dager';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (onOpen != null) {
            onOpen!(a);
          } else if (emp != null && onOpenEmployee != null) {
            onOpenEmployee!(emp);
          }
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: accent.withValues(alpha: 0.14),
                child: Text(
                  (a.userName ?? emp?.fullName ?? '?')
                      .trim()
                      .split(RegExp(r'\s+'))
                      .take(2)
                      .map((p) => p.isEmpty ? '' : p[0].toUpperCase())
                      .join(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: accent,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.userName ?? emp?.fullName ?? 'Ansatt',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DriftProTheme.bodySm
                          .copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${df.format(a.startDate)} – ${df.format(a.endDate)} · $days d',
                      style: DriftProTheme.caption.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    whenLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: ongoing ? DriftProTheme.warning : accent,
                    ),
                  ),
                  if (pending) ...[
                    const SizedBox(height: 4),
                    const _StatusChip(
                      label: 'Venter',
                      color: DriftProTheme.warning,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 7),
          Text(
            '$label · ',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color.withValues(alpha: 0.85),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.color,
    required this.track,
  });

  final double progress;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 5;
    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
