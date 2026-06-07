import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import 'department_absence_charts.dart';
import 'department_absence_stats.dart';

/// Moderne fraværsstripe inne i avdelingskort.
class DepartmentAbsencePanel extends StatelessWidget {
  final DepartmentAbsenceOverview stats;
  final Color accent;

  const DepartmentAbsencePanel({
    super.key,
    required this.stats,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (stats.memberCount == 0) {
      return _panelShell(
        isDark,
        child: Row(
          children: [
            Icon(Icons.people_outline, size: 16, color: Colors.grey[500]),
            const SizedBox(width: 8),
            Text(
              'Ingen ansatte — ingen fraværsdata',
              style: DriftProTheme.caption.copyWith(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return _panelShell(
      isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_busy_rounded, size: 16, color: accent),
              const SizedBox(width: 6),
              Text(
                'Fravær i dag',
                style: DriftProTheme.labelSm.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              _attendanceBadge(stats.presentPercent),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: stats.memberCount > 0
                  ? (stats.presentCount / stats.memberCount).clamp(0.0, 1.0)
                  : 1,
              minHeight: 8,
              backgroundColor: isDark ? Colors.white10 : Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation(
                stats.presentPercent >= 80
                    ? DriftProTheme.success
                    : stats.presentPercent >= 50
                        ? DriftProTheme.warning
                        : DriftProTheme.error,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${stats.presentCount} av ${stats.memberCount} på jobb i dag',
            style: DriftProTheme.caption.copyWith(
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.grey[400] : Colors.grey[700],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _miniStat(
                  Icons.beach_access_outlined,
                  '${stats.onVacationToday}',
                  'Ferie',
                  DriftProTheme.absenceVacation,
                  isDark,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _miniStat(
                  AppIcons.absence,
                  '${stats.otherAbsenceToday}',
                  'Fravær',
                  DriftProTheme.absenceSickSelf,
                  isDark,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _miniStat(
                  Icons.pending_actions_outlined,
                  '${stats.pendingCount}',
                  'Venter',
                  stats.pendingCount > 0 ? DriftProTheme.warning : Colors.grey,
                  isDark,
                  highlight: stats.pendingCount > 0,
                ),
              ),
            ],
          ),
          if (stats.upcomingWeek > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.date_range_outlined, size: 14, color: accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${stats.upcomingWeek} planlagt neste 7 dager',
                    style: DriftProTheme.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                ),
              ],
            ),
          ] else if (stats.allPresent) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.check_circle_outline,
                    size: 14, color: DriftProTheme.success),
                const SizedBox(width: 6),
                Text(
                  'Full bemanning i dag',
                  style: DriftProTheme.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: DriftProTheme.success,
                  ),
                ),
              ],
            ),
          ],
          if (stats.hasYtdInsights) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: accent.withValues(alpha: 0.15)),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (stats.typeBreakdownYtd.isNotEmpty)
                  AbsenceTypeDonut(
                    breakdown: stats.typeBreakdownYtd,
                    totalDays: stats.totalDaysYtd,
                    accent: accent,
                  ),
                if (stats.typeBreakdownYtd.isNotEmpty) const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (stats.typeBreakdownYtd.isNotEmpty)
                        _ytdBreakdownHeader(stats, accent),
                      if (stats.topByAbsence.isNotEmpty) ...[
                        if (stats.typeBreakdownYtd.isNotEmpty) const SizedBox(height: 10),
                        AbsenceLeaderboard(
                          entries: stats.topByAbsence,
                          accent: accent,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (stats.monthlyTrend.any((p) => p.days > 0)) ...[
              const SizedBox(height: 12),
              AbsenceMonthlySparkline(
                points: stats.monthlyTrend,
                accent: accent,
              ),
            ],
            if (stats.typeBreakdownYtd.isNotEmpty) ...[
              const SizedBox(height: 12),
              AbsenceTypeBreakdownBar(
                breakdown: stats.typeBreakdownYtd,
                totalDays: stats.totalDaysYtd,
                accent: accent,
                year: stats.ytdYear,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _ytdBreakdownHeader(DepartmentAbsenceOverview stats, Color accent) {
    return Row(
      children: [
        Icon(Icons.calendar_month_outlined, size: 14, color: accent),
        const SizedBox(width: 6),
        Text(
          'Hittil ${stats.ytdYear}',
          style: DriftProTheme.caption.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }

  Widget _panelShell(bool isDark, {required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: isDark ? 0.12 : 0.08),
            isDark ? Colors.white.withValues(alpha: 0.03) : Colors.grey.shade50,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: child,
    );
  }

  Widget _attendanceBadge(int percent) {
    final color = percent >= 80
        ? DriftProTheme.success
        : percent >= 50
            ? DriftProTheme.warning
            : DriftProTheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$percent% tilstede',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Widget _miniStat(
    IconData icon,
    String value,
    String label,
    Color color,
    bool isDark, {
    bool highlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.black26 : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: highlight
              ? color.withValues(alpha: 0.45)
              : (isDark ? Colors.white10 : Colors.grey.shade200),
        ),
      ),
      child: Column(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: color,
              height: 1,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
