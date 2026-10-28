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

/// Strategisk fraværs-/ferieinnsikt med diagrammer, rangering og trender.
class ManagerLeaveInsights extends StatelessWidget {
  const ManagerLeaveInsights({
    super.key,
    required this.employees,
    required this.absences,
    required this.quotas,
    required this.year,
    required this.pending,
    required this.awayToday,
    required this.nextWeekAwayCount,
    required this.onScrollToApprovals,
    this.onOpenEmployee,
    this.onOpenAbsence,
  });

  final List<UserProfile> employees;
  final List<Absence> absences;
  final List<AbsenceQuota> quotas;
  final int year;
  final List<Absence> pending;
  final List<Absence> awayToday;
  final int nextWeekAwayCount;
  final VoidCallback onScrollToApprovals;
  final void Function(UserProfile employee)? onOpenEmployee;
  final void Function(Absence absence)? onOpenAbsence;

  static const _targetPct = 9.9;
  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mai', 'Jun',
    'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Des',
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    final ref = year == now.year
        ? now
        : year < now.year
            ? DateTime(year, 12, 31)
            : DateTime(year, 1, 1);

    final summary = TeamLeaveSummary.compute(
      employees: employees,
      allAbsences: absences,
      referenceDate: ref,
    );

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

    final ferieUsed = ferieRows.fold<int>(0, (s, r) => s + r.used);
    final ferieTotal = ferieRows.fold<int>(0, (s, r) => s + r.total);
    final ferieLeft = ferieRows.fold<int>(0, (s, r) => s + r.left);
    final feriePct = ferieTotal <= 0 ? 0.0 : ferieUsed / ferieTotal;

    final mostLeft = [...ferieRows]
      ..sort((a, b) => b.left.compareTo(a.left));
    final mostUsed = [...ferieRows]
      ..sort((a, b) => b.used.compareTo(a.used));

    final upcomingFerie = absences
        .where((a) =>
            a.type == AbsenceType.ferie &&
            (a.status == AbsenceStatus.godkjent ||
                a.status == AbsenceStatus.ventende) &&
            !BusinessDays.dayOnly(a.endDate).isBefore(BusinessDays.dayOnly(now)) &&
            BusinessDays.dayOnly(a.startDate)
                    .difference(BusinessDays.dayOnly(now))
                    .inDays <=
                45)
        .toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));

    final monthly = _monthlyAbsenceDays(absences, year, ref);
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

    final capacityPct = employees.isEmpty
        ? 100
        : (((employees.length - nextWeekAwayCount) / employees.length) * 100)
            .round()
            .clamp(0, 100);

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
                          'Innsikt $year',
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
                    employeeCount: employees.length,
                    trend: trend,
                  );
                  final right = _FerieSplitCard(
                    used: ferieUsed,
                    left: ferieLeft,
                    total: ferieTotal,
                    usedPct: feriePct,
                    avgLeft: employees.isEmpty
                        ? 0
                        : (ferieLeft / employees.length).round(),
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
                    value: '${summary.totalSykmeldingDays} d',
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
            peakMonth: peakMonth,
            currentMonth: year == now.year ? now.month - 1 : peakMonth,
            isDark: isDark,
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
        if (upcomingFerie.isNotEmpty) ...[
          const SizedBox(height: 12),
          _card(
            isDark: isDark,
            child: _UpcomingFeriePanel(
              items: upcomingFerie.take(6).toList(),
              onOpen: onOpenAbsence,
              onOpenEmployee: onOpenEmployee,
              employees: employees,
              isDark: isDark,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'Beregnet på virkedager hittil i $year'
          '${year == now.year ? ' (YTD)' : ''} · '
          '${BusinessDays.countInRange(DateTime(year, 1, 1), ref)} virkedager',
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
    int year,
    DateTime through,
  ) {
    final months = List<double>.filled(12, 0);
    final yearStart = DateTime(year, 1, 1);
    final yearEnd = BusinessDays.dayOnly(through);

    for (final a in absences) {
      if (a.status != AbsenceStatus.godkjent) continue;
      if (!EmployeeLeaveSnapshot.kpiAbsenceTypes.contains(a.type)) continue;
      var day = BusinessDays.dayOnly(a.startDate);
      final end = BusinessDays.dayOnly(a.endDate);
      while (!day.isAfter(end)) {
        if (!day.isBefore(yearStart) &&
            !day.isAfter(yearEnd) &&
            !BusinessDays.isWeekend(day) &&
            !BusinessDays.isNorwegianPublicHoliday(day)) {
          months[day.month - 1] += 1;
        }
        day = day.add(const Duration(days: 1));
      }
    }
    return months;
  }

  static int _peakMonth(List<double> monthly) {
    var peak = 0;
    for (var i = 1; i < monthly.length; i++) {
      if (monthly[i] > monthly[peak]) peak = i;
    }
    return peak;
  }

  /// Positiv = mer fravær siste 30 dager enn forrige 30 (opp = dårligere).
  static ({double deltaPct, bool up}) _recentTrend(
    List<Absence> absences,
    DateTime now,
  ) {
    final today = BusinessDays.dayOnly(now);
    final curStart = today.subtract(const Duration(days: 29));
    final prevEnd = curStart.subtract(const Duration(days: 1));
    final prevStart = prevEnd.subtract(const Duration(days: 29));

    int daysIn(DateTime from, DateTime to) {
      var n = 0;
      for (final a in absences) {
        if (a.status != AbsenceStatus.godkjent) continue;
        if (!EmployeeLeaveSnapshot.kpiAbsenceTypes.contains(a.type)) continue;
        final s = BusinessDays.dayOnly(a.startDate);
        final e = BusinessDays.dayOnly(a.endDate);
        final fromClamped = s.isAfter(from) ? s : from;
        final toClamped = e.isBefore(to) ? e : to;
        if (toClamped.isBefore(fromClamped)) continue;
        n += BusinessDays.countInRange(fromClamped, toClamped);
      }
      return n;
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

// ── Scope filters (shared with overview) ─────────────────────────────────────

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

// ── Private UI pieces ─────────────────────────────────────────────────────────

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
    required this.employeeCount,
    required this.trend,
  });

  final double rate;
  final Color color;
  final double target;
  final int fravaerDays;
  final int sykmeldingDays;
  final int employeeCount;
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
                  '$fravaerDays virkedager'
                  '${sykmeldingDays > 0 ? ' · $sykmeldingDays d sykmelding' : ''}'
                  ' · $employeeCount ansatte',
                  style: DriftProTheme.caption
                      .copyWith(color: const Color(0xFF64748B)),
                ),
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
    final worse = trend.up; // mer fravær = dårligere
    final color = worse ? DriftProTheme.error : DriftProTheme.success;
    final icon = worse ? Icons.trending_up_rounded : Icons.trending_down_rounded;
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

class _FerieSplitCard extends StatelessWidget {
  const _FerieSplitCard({
    required this.used,
    required this.left,
    required this.total,
    required this.usedPct,
    required this.avgLeft,
  });

  final int used;
  final int left;
  final int total;
  final double usedPct;
  final int avgLeft;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : DriftProTheme.absenceVacation.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: DriftProTheme.absenceVacation.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Feriesaldo',
            style: DriftProTheme.labelMd.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            'Snitt $avgLeft d igjen per ansatt',
            style: DriftProTheme.caption.copyWith(
              color: DriftProTheme.absenceVacation,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: 'Brukt',
                  value: '$used',
                  color: const Color(0xFF475569),
                ),
              ),
              Expanded(
                child: _MiniStat(
                  label: 'Igjen',
                  value: '$left',
                  color: DriftProTheme.primaryGreen,
                ),
              ),
              Expanded(
                child: _MiniStat(
                  label: 'Andel brukt',
                  value: '${(usedPct * 100).round()}%',
                  color: DriftProTheme.absenceVacation,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 10,
              child: total <= 0
                  ? Container(color: const Color(0xFFE2E8F0))
                  : Row(
                      children: [
                        if (used > 0)
                          Expanded(
                            flex: used,
                            child: Container(
                              color: DriftProTheme.absenceVacation,
                            ),
                          ),
                        if (left > 0)
                          Expanded(
                            flex: left,
                            child: Container(
                              color: DriftProTheme.primaryGreen
                                  .withValues(alpha: 0.35),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Lilla = brukt · Grønn = igjen (av $total d totalt)',
            style: DriftProTheme.caption.copyWith(
              color: const Color(0xFF94A3B8),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: DriftProTheme.caption.copyWith(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF94A3B8),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: color,
            height: 1.1,
          ),
        ),
      ],
    );
  }
}

class _MonthlyAbsenceChart extends StatelessWidget {
  const _MonthlyAbsenceChart({
    required this.year,
    required this.monthly,
    required this.peakMonth,
    required this.currentMonth,
    required this.isDark,
  });

  final int year;
  final List<double> monthly;
  final int peakMonth;
  final int currentMonth;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final maxY = monthly.fold<double>(0, math.max);
    final spots = <FlSpot>[
      for (var i = 0; i < 12; i++) FlSpot(i.toDouble(), monthly[i]),
    ];
    final peakLabel = ManagerLeaveInsights._monthNames[peakMonth];
    final mom = _monthOverMonth(monthly, currentMonth);

    return Column(
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
                    'Fravær per måned $year',
                    style: DriftProTheme.labelLg
                        .copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    maxY <= 0
                        ? 'Ingen fraværsdager registrert ennå'
                        : 'Mest fravær i $peakLabel (${monthly[peakMonth].round()} virkedager)',
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
        SizedBox(
          height: 180,
          child: maxY <= 0
              ? Center(
                  child: Text(
                    'Ingen data å vise',
                    style: DriftProTheme.caption,
                  ),
                )
              : LineChart(
                  LineChartData(
                    minX: 0,
                    maxX: 11,
                    minY: 0,
                    maxY: (maxY * 1.25).clamp(4, double.infinity),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (v) => FlLine(
                        color: isDark
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
                          reservedSize: 28,
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
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                ManagerLeaveInsights._monthNames[i],
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: i == peakMonth
                                      ? FontWeight.w900
                                      : FontWeight.w600,
                                  color: i == peakMonth
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
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipItems: (spots) => spots
                            .map(
                              (s) => LineTooltipItem(
                                '${ManagerLeaveInsights._monthNames[s.x.toInt()]}: ${s.y.round()} d',
                                const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            )
                            .toList(),
                      ),
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
                            final peak = i == peakMonth;
                            return FlDotCirclePainter(
                              radius: peak ? 5 : 3,
                              color: peak
                                  ? DriftProTheme.error
                                  : DriftProTheme.primaryGreen,
                              strokeWidth: 0,
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
      ],
    );
  }

  /// Null hvis ikke nok data til sammenligning.
  static ({bool up, double pct, String label})? _monthOverMonth(
    List<double> monthly,
    int currentMonth,
  ) {
    if (currentMonth <= 0 || currentMonth >= monthly.length) return null;
    final cur = monthly[currentMonth];
    final prev = monthly[currentMonth - 1];
    final curName = ManagerLeaveInsights._monthNames[currentMonth];
    final prevName = ManagerLeaveInsights._monthNames[currentMonth - 1];
    if (prev <= 0 && cur <= 0) return null;
    if (prev <= 0) {
      return (up: true, pct: 100, label: '$curName vs $prevName');
    }
    final delta = ((cur - prev) / prev) * 100;
    if (delta.abs() < 0.5) {
      return (up: false, pct: 0, label: 'Stabilt $curName');
    }
    return (
      up: delta > 0,
      pct: delta.abs(),
      label: '$curName vs $prevName',
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
            for (var i = 0; i < rows.length; i++)
              _rankRow(rows[i], i + 1),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Snart ferie',
          style: DriftProTheme.labelLg.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 2),
        Text(
          'Godkjent eller ventende ferie de neste 45 dagene',
          style: DriftProTheme.caption.copyWith(color: const Color(0xFF64748B)),
        ),
        const SizedBox(height: 12),
        ...items.map((a) {
          final days = a.vacationDayCount ??
              AbsenceService.vacationDayCount(a.startDate, a.endDate);
          final pending = a.status == AbsenceStatus.ventende;
          UserProfile? emp;
          for (final e in employees) {
            if (e.id == a.userId) {
              emp = e;
              break;
            }
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
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
                  color: DriftProTheme.absenceVacation.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: DriftProTheme.absenceVacation.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.beach_access_rounded,
                      color: DriftProTheme.absenceVacation,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a.userName ?? emp?.fullName ?? 'Ansatt',
                            style: DriftProTheme.bodySm
                                .copyWith(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            '${df.format(a.startDate)} – ${df.format(a.endDate)} · $days d'
                            '${pending ? ' · venter' : ''}',
                            style: DriftProTheme.caption,
                          ),
                        ],
                      ),
                    ),
                    if (pending)
                      const _StatusChip(
                        label: 'Venter',
                        color: DriftProTheme.warning,
                      ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
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
