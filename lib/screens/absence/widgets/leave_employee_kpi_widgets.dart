import 'package:flutter/material.dart';

import '../../../core/services/absence/employee_leave_stats.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/leave_usage_colors.dart';

class LeaveEmployeeKpiCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final String sub;
  final Color baseColor;
  final LeaveUsageLevel level;
  final double progress;
  final bool compact;

  const LeaveEmployeeKpiCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.sub,
    required this.baseColor,
    required this.level,
    required this.progress,
    this.compact = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = LeaveUsageColors.colorFor(level, baseColor);

    if (!compact) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? DriftProTheme.surfaceDark : color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: color.withValues(alpha: level == LeaveUsageLevel.ok ? 0.2 : 0.45),
            width: level == LeaveUsageLevel.ok ? 1 : 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: DriftProTheme.labelMd.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(unit, style: DriftProTheme.caption),
                  const SizedBox(height: 2),
                  Text(sub, style: DriftProTheme.caption.copyWith(fontSize: 11)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: color,
                    height: 1,
                  ),
                ),
                if (level != LeaveUsageLevel.ok)
                  Icon(
                    level == LeaveUsageLevel.critical
                        ? Icons.error_outline
                        : Icons.warning_amber_rounded,
                    size: 16,
                    color: color,
                  ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.surfaceDark : color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: level == LeaveUsageLevel.ok ? 0.2 : 0.45),
          width: level == LeaveUsageLevel.ok ? 1 : 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: DriftProTheme.caption.copyWith(fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (level != LeaveUsageLevel.ok)
                Icon(
                  level == LeaveUsageLevel.critical
                      ? Icons.error_outline
                      : Icons.warning_amber_rounded,
                  size: 14,
                  color: color,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color,
              height: 1,
            ),
          ),
          Text(unit, style: DriftProTheme.caption.copyWith(fontSize: 10)),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 3,
              backgroundColor: color.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            sub,
            style: DriftProTheme.caption.copyWith(fontSize: 9),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class LeaveEmployeeKpiRow extends StatelessWidget {
  final EmployeeLeaveSnapshot stats;
  final int selectedYear;

  const LeaveEmployeeKpiRow({
    super.key,
    required this.stats,
    required this.selectedYear,
  });

  @override
  Widget build(BuildContext context) {
    final period = stats.periodUsage.window.formatRangeWithBasis();
    final cards = [
      LeaveEmployeeKpiCard(
        icon: Icons.beach_access,
        label: 'Ferie $selectedYear',
        value: '${stats.ferieRemaining} d',
        unit: 'dager igjen · ${stats.ferieUsed}/${stats.ferieTotal} brukt',
        sub: 'Kalenderår $selectedYear',
        baseColor: DriftProTheme.absenceVacation,
        level: stats.ferieLevel,
        progress: stats.ferieProgress,
      ),
      LeaveEmployeeKpiCard(
        icon: Icons.sick_outlined,
        label: 'Egenmelding',
        value: '${stats.egenDaysTotal} d',
        unit: '${stats.egenTilfeller}/${stats.egenTilfellerMax} tilfeller · max ${stats.egenMax} d',
        sub: period,
        baseColor: DriftProTheme.absenceSickSelf,
        level: stats.egenLevel,
        progress: stats.egenProgress,
      ),
      LeaveEmployeeKpiCard(
        icon: Icons.child_care_outlined,
        label: 'Sykt barn',
        value: '${stats.syktDays} d',
        unit: 'av ${stats.syktMax} dager i perioden',
        sub: period,
        baseColor: DriftProTheme.absenceSickChild,
        level: stats.syktLevel,
        progress: stats.syktProgress,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 640;
        final stacked = constraints.maxWidth < 420;

        if (stacked) {
          return Column(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                LeaveEmployeeKpiCard(
                  icon: cards[i].icon,
                  label: cards[i].label,
                  value: cards[i].value,
                  unit: cards[i].unit,
                  sub: cards[i].sub,
                  baseColor: cards[i].baseColor,
                  level: cards[i].level,
                  progress: cards[i].progress,
                  compact: false,
                ),
              ],
            ],
          );
        }

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) SizedBox(width: wide ? 12 : 8),
                Expanded(child: cards[i]),
              ],
            ],
          ),
        );
      },
    );
  }
}

class LeaveEmployeeCompactStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color baseColor;
  final LeaveUsageLevel level;

  const LeaveEmployeeCompactStat({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.baseColor,
    required this.level,
  });

  @override
  Widget build(BuildContext context) {
    final color = LeaveUsageColors.colorFor(level, baseColor);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: color,
                height: 1.1,
              ),
            ),
            Text(label, style: DriftProTheme.caption.copyWith(fontSize: 9)),
          ],
        ),
      ],
    );
  }
}
