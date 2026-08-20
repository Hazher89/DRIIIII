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

/// Bedrifts-/teamstripe med ekte fraværstall — lett å skanne.
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
    final border = isDark ? DriftProTheme.dividerDark : const Color(0xFFE2E8F0);
    final pct = summary.averageAbsencePercentRounded;

    return Material(
      color: isDark ? DriftProTheme.cardDark : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
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
                        title,
                        style: DriftProTheme.labelLg.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                AbsenceRateBadge(
                  percent: summary.averageAbsencePercent,
                  level: summary.usageLevel,
                ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, c) {
                final wide = c.maxWidth >= 520;
                final tiles = [
                  _SummaryKpi(
                    label: 'Ansatte',
                    value: '${summary.employeeCount}',
                    color: DriftProTheme.primaryGreen,
                  ),
                  _SummaryKpi(
                    label: 'Snitt fravær',
                    value: '$pct%',
                    color: AbsencePalette.indigo,
                  ),
                  _SummaryKpi(
                    label: 'Dager i år',
                    value: '${summary.totalFravaerDays}',
                    color: AbsencePalette.sky,
                  ),
                  _SummaryKpi(
                    label: 'Egenmelding',
                    value: '${summary.totalEgenDays} d',
                    hint: '${summary.totalEgenTilfeller} tilf.',
                    color: AbsencePalette.violet,
                  ),
                  _SummaryKpi(
                    label: 'Sykt barn',
                    value: '${summary.totalSyktDays} d',
                    color: AbsencePalette.rose,
                  ),
                ];
                if (wide) {
                  return Row(
                    children: [
                      for (var i = 0; i < tiles.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(child: tiles[i]),
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
        ),
      ),
    );
  }
}

class _SummaryKpi extends StatelessWidget {
  const _SummaryKpi({
    required this.label,
    required this.value,
    required this.color,
    this.hint,
  });

  final String label;
  final String value;
  final String? hint;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.grey[500] : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: color,
              height: 1.1,
              letterSpacing: -0.3,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(
              hint!,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.grey[500] : Colors.grey[600],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
