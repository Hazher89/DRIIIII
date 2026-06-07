import 'package:flutter/material.dart';

import '../../../core/services/absence/employee_leave_stats.dart';
import '../../../core/theme/absence_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/leave_usage_colors.dart';

/// Kompakt badge med fraværsprosent.
class AbsenceRateBadge extends StatelessWidget {
  final double percent;
  final LeaveUsageLevel? level;
  final bool compact;

  const AbsenceRateBadge({
    super.key,
    required this.percent,
    this.level,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final pct = percent.round().clamp(0, 100);
    final lv = level ?? LeaveUsageColors.levelFromUsed(pct, 100);
    final color = LeaveUsageColors.colorFor(lv, AbsencePalette.indigo);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.pie_chart_outline_rounded, size: compact ? 11 : 13, color: color),
          SizedBox(width: compact ? 4 : 5),
          Text(
            '$pct%',
            style: TextStyle(
              fontSize: compact ? 10 : 12,
              fontWeight: FontWeight.w900,
              color: color,
              height: 1,
            ),
          ),
          if (!compact) ...[
            const SizedBox(width: 4),
            Text(
              'fravær',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: color.withValues(alpha: 0.85),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Toppstripe med snitt fravær % + dager/tilfeller for team eller bedrift.
class LeaveAbsenceSummaryBar extends StatelessWidget {
  final TeamLeaveSummary summary;
  final String title;
  final String? subtitle;

  const LeaveAbsenceSummaryBar({
    super.key,
    required this.summary,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (summary.employeeCount <= 0) return const SizedBox.shrink();

    return Material(
      color: isDark ? DriftProTheme.surfaceDark : const Color(0xFFF8FAFC),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: DriftProTheme.caption.copyWith(fontWeight: FontWeight.w800),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 9,
                        color: isDark ? Colors.grey[500] : Colors.grey[600],
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    '${summary.totalFravaerDays} dager · '
                    '${summary.totalEgenTilfeller} tilfeller · '
                    '${summary.totalEgenDays} egen · '
                    '${summary.totalSyktDays} sykt',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.grey[400] : Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
            AbsenceRateBadge(
              percent: summary.averageAbsencePercent,
              level: summary.usageLevel,
            ),
          ],
        ),
      ),
    );
  }
}
