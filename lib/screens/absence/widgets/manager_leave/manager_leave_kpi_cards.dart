import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../models/absence.dart';
import 'manager_leave_helpers.dart';

/// Kompakt statusstripe — uten dobbelt «ingen ventende» / «alle på jobb».
class ManagerLeaveKpiCards extends StatelessWidget {
  const ManagerLeaveKpiCards({
    super.key,
    required this.pendingCount,
    required this.awayToday,
    required this.onJobCount,
    required this.totalEmployees,
    required this.nextWeekAwayCount,
    required this.onScrollToApprovals,
  });

  final int pendingCount;
  final List<Absence> awayToday;
  final int onJobCount;
  final int totalEmployees;
  final int nextWeekAwayCount;
  final VoidCallback onScrollToApprovals;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final capacityPct = totalEmployees == 0
        ? 100
        : (((totalEmployees - nextWeekAwayCount) / totalEmployees) * 100)
            .round()
            .clamp(0, 100);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pendingCount > 0) ...[
          _PendingBanner(
            isDark: isDark,
            count: pendingCount,
            onTap: onScrollToApprovals,
          ),
          const SizedBox(height: 12),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 720;
            final staffing = _StatusTile(
              isDark: isDark,
              icon: Icons.groups_outlined,
              accent: awayToday.isEmpty
                  ? DriftProTheme.primaryGreen
                  : DriftProTheme.warning,
              label: 'I dag',
              value: '$onJobCount / $totalEmployees',
              hint: awayToday.isEmpty
                  ? 'ingen borte'
                  : '${awayToday.length} borte',
              child: awayToday.isEmpty
                  ? null
                  : Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: awayToday.take(5).map((a) {
                        final status =
                            ManagerLeaveHelpers.todayStatusFor([a]);
                        return _AwayChip(
                          name: a.userName ?? 'Ansatt',
                          color: status.color,
                          label: a.type.label,
                        );
                      }).toList(),
                    ),
            );
            final week = _StatusTile(
              isDark: isDark,
              icon: Icons.event_available_outlined,
              accent: DriftProTheme.absenceVacation,
              label: 'Neste uke',
              value: nextWeekAwayCount == 0
                  ? '$capacityPct%'
                  : '$nextWeekAwayCount fri',
              hint: nextWeekAwayCount == 0
                  ? 'kapasitet'
                  : '$capacityPct% kapasitet',
            );

            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: staffing),
                  const SizedBox(width: 12),
                  Expanded(child: week),
                ],
              );
            }
            return Column(
              children: [
                staffing,
                const SizedBox(height: 10),
                week,
              ],
            );
          },
        ),
        if (pendingCount == 0) ...[
          const SizedBox(height: 10),
          _QuietOkLine(isDark: isDark),
        ],
      ],
    );
  }
}

class _PendingBanner extends StatelessWidget {
  const _PendingBanner({
    required this.isDark,
    required this.count,
    required this.onTap,
  });

  final bool isDark;
  final int count;
  final VoidCallback onTap;

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
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: DriftProTheme.warning.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.pending_actions_rounded,
                  color: Color(0xFFB45309),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$count ${count == 1 ? 'søknad' : 'søknader'} venter',
                      style: DriftProTheme.labelLg.copyWith(
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF9A3412),
                      ),
                    ),
                    Text(
                      'Godkjenn eller avslå under',
                      style: DriftProTheme.caption.copyWith(
                        color: const Color(0xFF9A3412).withValues(alpha: 0.8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
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

class _QuietOkLine extends StatelessWidget {
  const _QuietOkLine({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? DriftProTheme.success.withValues(alpha: 0.1)
            : DriftProTheme.success.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: DriftProTheme.success.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: 18,
            color: DriftProTheme.success.withValues(alpha: 0.9),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Ingen ventende søknader — alt er behandlet',
              style: DriftProTheme.caption.copyWith(
                fontWeight: FontWeight.w700,
                color: isDark
                    ? Colors.white70
                    : DriftProTheme.primaryGreenDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.isDark,
    required this.icon,
    required this.accent,
    required this.label,
    required this.value,
    required this.hint,
    this.child,
  });

  final bool isDark;
  final IconData icon;
  final Color accent;
  final String label;
  final String value;
  final String hint;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? DriftProTheme.dividerDark : const Color(0xFFE8EEF0),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.035),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accent, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: DriftProTheme.caption.copyWith(
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white60 : const Color(0xFF64748B),
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: DriftProTheme.headingSm.copyWith(
                  fontWeight: FontWeight.w900,
                  fontSize: 26,
                  height: 1,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  hint,
                  style: DriftProTheme.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          if (child != null) ...[
            const SizedBox(height: 12),
            child!,
          ],
        ],
      ),
    );
  }
}

class _AwayChip extends StatelessWidget {
  const _AwayChip({
    required this.name,
    required this.color,
    required this.label,
  });

  final String name;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            name.split(' ').first,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color.withValues(alpha: 0.95),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: color.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}
