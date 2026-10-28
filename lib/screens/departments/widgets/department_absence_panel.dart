import 'package:flutter/material.dart';

import '../../../core/theme/absence_palette.dart';
import '../../../core/theme/app_theme.dart';
import 'department_absence_stats.dart';

/// Kompakt fraværspanel under KPI-raden — «i dag» + årstall.
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
      return _shell(
        isDark,
        child: Text(
          'Legg til ansatte for å se tilstedeværelse og fravær.',
          style: DriftProTheme.caption.copyWith(
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
      );
    }

    return _shell(
      isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.today_rounded, size: 14, color: accent),
              const SizedBox(width: 6),
              Text(
                'I dag',
                style: DriftProTheme.labelSm.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text(
                stats.awayToday == 0
                    ? 'Ingen borte'
                    : '${stats.awayToday} borte · ${stats.presentPercent}% til stede',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AbsencePalette.attendanceFill(
                    stats.presentPercent,
                    accent: accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: (stats.presentCount / stats.memberCount).clamp(0.0, 1.0),
              minHeight: 7,
              backgroundColor: isDark ? Colors.white10 : Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation(
                AbsencePalette.attendanceFill(
                  stats.presentPercent,
                  accent: accent,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (stats.onVacationToday > 0)
                _pill('${stats.onVacationToday} ferie', AbsencePalette.sky, isDark),
              if (stats.otherAbsenceToday > 0)
                _pill(
                  '${stats.otherAbsenceToday} syk/annet',
                  AbsencePalette.violet,
                  isDark,
                ),
              if (stats.pendingCount > 0)
                _pill(
                  '${stats.pendingCount} venter',
                  DriftProTheme.warning,
                  isDark,
                ),
              if (stats.upcomingWeek > 0)
                _pill(
                  '${stats.upcomingWeek} neste uke',
                  AbsencePalette.slate,
                  isDark,
                ),
            ],
          ),
          if (stats.hasYtdInsights) ...[
            const SizedBox(height: 10),
            Divider(height: 1, color: AbsencePalette.panelBorder(isDark)),
            const SizedBox(height: 10),
            Text(
              'Fravær ${stats.ytdYear} (KPI · person-virkedager)',
              style: DriftProTheme.caption.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _pill(
                  '${stats.averageAbsencePercent.toStringAsFixed(1)}% · ${stats.totalDaysYtd} person-d',
                  stats.averageAbsencePercent > 9.9
                      ? DriftProTheme.error
                      : AbsencePalette.indigo,
                  isDark,
                ),
                if (stats.registeredSykmeldingDays > 0)
                  _pill(
                    '${stats.registeredSykmeldingDays} d sykmelding',
                    DriftProTheme.absenceSickNote,
                    isDark,
                  ),
                if (stats.registeredEgenDays > 0)
                  _pill(
                    '${stats.registeredEgenDays} d egen',
                    AbsencePalette.violet,
                    isDark,
                  ),
                if (stats.registeredSyktDays > 0)
                  _pill(
                    '${stats.registeredSyktDays} d sykt barn',
                    AbsencePalette.rose,
                    isDark,
                  ),
                if (stats.registeredFerieDays > 0)
                  _pill(
                    '${stats.registeredFerieDays} d ferie (ikke i %)',
                    AbsencePalette.sky,
                    isDark,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _shell(bool isDark, {required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AbsencePalette.panelBackground(isDark),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AbsencePalette.panelBorder(isDark)),
      ),
      child: child,
    );
  }

  Widget _pill(String text, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: isDark ? color.withValues(alpha: 0.95) : color,
        ),
      ),
    );
  }
}
