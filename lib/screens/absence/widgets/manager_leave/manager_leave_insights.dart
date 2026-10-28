import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/constants/strategic_goals_2026.dart';
import '../../../../core/services/absence/employee_leave_stats.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/business_days.dart';
import '../../../../core/utils/leave_usage_colors.dart';
import '../../../../models/absence.dart';
import '../../../../models/user_profile.dart';
import 'manager_leave_helpers.dart';

/// Strategisk fraværs-/ferieinnsikt med ekte data, mål ≤ 9,9 % og fargekoding.
class ManagerLeaveInsights extends StatelessWidget {
  const ManagerLeaveInsights({
    super.key,
    required this.employees,
    required this.absences,
    required this.quotas,
    required this.year,
    required this.pendingCount,
    required this.awayToday,
    required this.nextWeekAwayCount,
    required this.onScrollToApprovals,
    this.onOpenEmployee,
  });

  final List<UserProfile> employees;
  final List<Absence> absences;
  final List<AbsenceQuota> quotas;
  final int year;
  final int pendingCount;
  final List<Absence> awayToday;
  final int nextWeekAwayCount;
  final VoidCallback onScrollToApprovals;
  final void Function(UserProfile employee)? onOpenEmployee;

  static const _targetPct = 9.9;

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

    var ferieUsed = 0;
    var ferieTotal = 0;
    var ferieLeft = 0;
    final lowLeft = <({UserProfile user, int left, int total})>[];

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
      ferieUsed += used;
      ferieTotal += total;
      ferieLeft += left;
      if (left <= 5) {
        lowLeft.add((user: e, left: left, total: total));
      }
    }
    lowLeft.sort((a, b) => a.left.compareTo(b.left));

    final rate = summary.averageAbsencePercent;
    final overTarget = rate > _targetPct;
    final nearTarget = rate >= _targetPct * 0.75 && !overTarget;
    final rateColor = overTarget
        ? DriftProTheme.error
        : nearTarget
            ? DriftProTheme.warning
            : DriftProTheme.success;

    final feriePct = ferieTotal <= 0 ? 0.0 : ferieUsed / ferieTotal;
    final ferieLevel = LeaveUsageColors.levelFromUsed(
      feriePct >= 1 ? 100 : (feriePct * 100).round(),
      100,
    );
    final ferieColor = LeaveUsageColors.colorFor(
      ferieLevel,
      DriftProTheme.absenceVacation,
    );

    final onJob =
        (employees.length - ManagerLeaveHelpers.uniqueUsers(awayToday).length)
            .clamp(0, employees.length);
    final capacityPct = employees.isEmpty
        ? 100
        : (((employees.length - nextWeekAwayCount) / employees.length) * 100)
            .round()
            .clamp(0, 100);

    StrategicGoal? goal;
    for (final g in StrategicGoals2026.goals) {
      if (g.id == 'fravaer') {
        goal = g;
        break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pendingCount > 0) ...[
          _ActionBanner(
            count: pendingCount,
            onTap: onScrollToApprovals,
            isDark: isDark,
          ),
          const SizedBox(height: 12),
        ],
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: isDark ? DriftProTheme.cardDark : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? DriftProTheme.dividerDark
                  : const Color(0xFFE8EEF0),
            ),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
          ),
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
                          style: DriftProTheme.labelLg.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          goal?.description ??
                              'Fravær og ferie mot strategiske mål',
                          style: DriftProTheme.caption.copyWith(
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: rateColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: rateColor.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      overTarget
                          ? 'Over mål'
                          : nearTarget
                              ? 'Nær mål'
                              : 'Innenfor mål',
                      style: TextStyle(
                        color: rateColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, c) {
                  final wide = c.maxWidth >= 860;
                  final gauges = [
                    _GaugeCard(
                      title: 'Fravær',
                      valueLabel: '${rate.toStringAsFixed(1)}%',
                      subtitle: 'Mål ≤ ${_targetPct.toStringAsFixed(1)}%',
                      progress: (rate / (_targetPct * 1.5)).clamp(0.0, 1.0),
                      color: rateColor,
                      detail:
                          '${summary.totalFravaerDays} fraværsdager · ${employees.length} ansatte',
                    ),
                    _GaugeCard(
                      title: 'Ferie brukt',
                      valueLabel: '$ferieUsed',
                      subtitle: 'av $ferieTotal dager',
                      progress: feriePct.clamp(0.0, 1.0),
                      color: ferieColor,
                      detail:
                          '${(feriePct * 100).round()}% av årets feriekvote',
                    ),
                    _GaugeCard(
                      title: 'Ferie igjen',
                      valueLabel: '$ferieLeft',
                      subtitle: 'dager totalt',
                      progress: ferieTotal <= 0
                          ? 0
                          : (ferieLeft / ferieTotal).clamp(0.0, 1.0),
                      color: ferieLeft <= employees.length * 5
                          ? DriftProTheme.warning
                          : DriftProTheme.primaryGreen,
                      detail: employees.isEmpty
                          ? '—'
                          : '~${(ferieLeft / employees.length).round()} d snitt per ansatt',
                    ),
                  ];

                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < gauges.length; i++) ...[
                          if (i > 0) const SizedBox(width: 12),
                          Expanded(child: gauges[i]),
                        ],
                      ],
                    );
                  }
                  return Column(
                    children: [
                      for (var i = 0; i < gauges.length; i++) ...[
                        if (i > 0) const SizedBox(height: 10),
                        gauges[i],
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetricPill(
                    icon: Icons.groups_outlined,
                    label: 'På jobb i dag',
                    value: '$onJob/${employees.length}',
                    color: DriftProTheme.primaryGreen,
                  ),
                  _MetricPill(
                    icon: Icons.event_busy_outlined,
                    label: 'Borte i dag',
                    value: '${awayToday.length}',
                    color: awayToday.isEmpty
                        ? DriftProTheme.primaryGreen
                        : DriftProTheme.warning,
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
                  if (pendingCount == 0)
                    _MetricPill(
                      icon: Icons.check_circle_outline,
                      label: 'Godkjenning',
                      value: 'OK',
                      color: DriftProTheme.success,
                    ),
                ],
              ),
              if (awayToday.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'Borte nå',
                  style: DriftProTheme.caption.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: awayToday.take(8).map((a) {
                    final st = ManagerLeaveHelpers.todayStatusFor([a]);
                    return _PersonChip(
                      name: a.userName ?? 'Ansatt',
                      label: a.type.label,
                      color: st.color,
                    );
                  }).toList(),
                ),
              ],
              if (lowLeft.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Lite ferie igjen (≤ 5 d)',
                  style: DriftProTheme.caption.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 8),
                ...lowLeft.take(5).map((row) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: onOpenEmployee == null
                            ? null
                            : () => onOpenEmployee!(row.user),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: DriftProTheme.warning.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color:
                                  DriftProTheme.warning.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  row.user.fullName,
                                  style: DriftProTheme.bodySm.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Text(
                                '${row.left} d igjen',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: row.left <= 0
                                      ? DriftProTheme.error
                                      : DriftProTheme.warning,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
              const SizedBox(height: 8),
              Text(
                'Beregnet på virkedager hittil i $year'
                '${year == now.year ? ' (YTD)' : ''} · '
                '${BusinessDays.countInRange(DateTime(year, 1, 1), ref)} virkedager i perioden',
                style: DriftProTheme.caption.copyWith(
                  color: const Color(0xFF94A3B8),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

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

class _ActionBanner extends StatelessWidget {
  const _ActionBanner({
    required this.count,
    required this.onTap,
    required this.isDark,
  });

  final int count;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                DriftProTheme.warning.withValues(alpha: isDark ? 0.22 : 0.16),
                DriftProTheme.warning.withValues(alpha: isDark ? 0.08 : 0.06),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: DriftProTheme.warning.withValues(alpha: 0.45),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.pending_actions_rounded, color: Color(0xFFB45309)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '$count ${count == 1 ? 'søknad' : 'søknader'} venter på godkjenning',
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
        ),
      ),
    );
  }
}

class _GaugeCard extends StatelessWidget {
  const _GaugeCard({
    required this.title,
    required this.valueLabel,
    required this.subtitle,
    required this.progress,
    required this.color,
    required this.detail,
  });

  final String title;
  final String valueLabel;
  final String subtitle;
  final double progress;
  final Color color;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            height: 78,
            child: CustomPaint(
              painter: _RingPainter(
                progress: progress,
                color: color,
                track: color.withValues(alpha: 0.15),
              ),
              child: Center(
                child: Text(
                  valueLabel,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: valueLabel.length > 5 ? 13 : 16,
                    color: color,
                    height: 1.05,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: DriftProTheme.labelMd.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: DriftProTheme.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: DriftProTheme.caption.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
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
    final sweep = 2 * math.pi * progress.clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
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

class _PersonChip extends StatelessWidget {
  const _PersonChip({
    required this.name,
    required this.label,
    required this.color,
  });

  final String name;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        '${name.split(' ').first} · $label',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
