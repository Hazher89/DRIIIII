import 'package:flutter/material.dart';

import '../../../core/theme/absence_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../absence/widgets/leave_absence_rate_widgets.dart';
import 'department_absence_charts.dart';
import 'department_absence_stats.dart';

/// Fraværsstripe inne i avdelingskort — kompakt og lesbar.
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _todaySection(isDark),
          if (stats.hasYtdInsights) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: AbsencePalette.panelBorder(isDark)),
            const SizedBox(height: 12),
            _registeredSection(isDark),
            if (stats.topByAbsence.isNotEmpty) ...[
              const SizedBox(height: 12),
              AbsenceLeaderboard(entries: stats.topByAbsence),
            ],
          ],
        ],
      ),
    );
  }

  Widget _todaySection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.today_rounded, size: 15, color: AbsencePalette.slateDark),
            const SizedBox(width: 6),
            Text(
              'I dag',
              style: DriftProTheme.labelSm.copyWith(fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            _attendanceBadge(stats.presentPercent),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: stats.memberCount > 0
                ? (stats.presentCount / stats.memberCount).clamp(0.0, 1.0)
                : 1,
            minHeight: 6,
            backgroundColor: isDark ? Colors.white10 : Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation(
              AbsencePalette.attendanceFill(stats.presentPercent, accent: accent),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          stats.awayToday > 0
              ? '${stats.presentCount} av ${stats.memberCount} på jobb · '
                  '${stats.awayToday} borte'
                  '${stats.onVacationToday > 0 ? ' (${stats.onVacationToday} ferie)' : ''}'
                  '${stats.otherAbsenceToday > 0 ? ' (${stats.otherAbsenceToday} fravær)' : ''}'
              : '${stats.presentCount} av ${stats.memberCount} på jobb',
          style: DriftProTheme.caption.copyWith(
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.grey[400] : Colors.grey[700],
          ),
        ),
        if (stats.pendingCount > 0) ...[
          const SizedBox(height: 6),
          _infoLine(
            Icons.pending_actions_outlined,
            '${stats.pendingCount} venter godkjenning',
            AbsencePalette.indigo,
          ),
        ] else if (stats.upcomingWeek > 0) ...[
          const SizedBox(height: 6),
          _infoLine(
            Icons.date_range_outlined,
            '${stats.upcomingWeek} planlagt neste 7 dager',
            accent,
          ),
        ],
      ],
    );
  }

  Widget _registeredSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Registrert fravær',
                    style: DriftProTheme.caption.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${stats.totalDaysYtd} d · ${stats.totalEgenTilfeller} tilf. · '
                    '${stats.registeredEgenDays} egen · ${stats.registeredSyktDays} sykt',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.grey[500] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            if (stats.memberCount > 0)
              AbsenceRateBadge(
                percent: stats.averageAbsencePercent,
                compact: true,
              ),
          ],
        ),
        if (stats.typeBreakdownYtd.isNotEmpty) ...[
          const SizedBox(height: 10),
          AbsenceTypeBreakdownBar(
            breakdown: stats.typeBreakdownYtd,
            totalDays: stats.totalDaysYtd,
          ),
        ],
        if (stats.registeredFerieDays > 0) ...[
          const SizedBox(height: 8),
          _infoLine(
            Icons.beach_access_outlined,
            '${stats.registeredFerieDays} feriedager registrert i ${stats.ytdYear}',
            DriftProTheme.absenceVacation,
          ),
        ],
      ],
    );
  }

  Widget _infoLine(IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: DriftProTheme.caption.copyWith(
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _panelShell(bool isDark, {required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AbsencePalette.panelBackground(isDark),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AbsencePalette.panelBorder(isDark)),
      ),
      child: child,
    );
  }

  Widget _attendanceBadge(int percent) {
    final color = AbsencePalette.attendanceBadge(percent);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$percent% tilstede',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}
