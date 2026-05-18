import 'package:flutter/material.dart';

import '../../../core/constants/leave_rules.dart';
import '../../../core/services/absence/absence_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/absence.dart';

class VacationBalanceCard extends StatelessWidget {
  final AbsenceQuota quota;
  final CompanyLeaveSettings company;
  final int? plannedNextYearDays;

  const VacationBalanceCard({
    super.key,
    required this.quota,
    required this.company,
    this.plannedNextYearDays,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final total = quota.totalVacationDays;
    final used = quota.vacationDaysUsed;
    final remaining = quota.vacationDaysRemaining;
    final carry = quota.carryoverEligible(company.maxVacationCarryover);
    final nextTotal = plannedNextYearDays != null
        ? AbsenceService.projectedNextYearTotal(
            quota: quota,
            newYearAllocation: plannedNextYearDays!,
            maxCarryover: company.maxVacationCarryover,
          )
        : null;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF0A192F), const Color(0xFF112240)]
              : [const Color(0xFFE8F5E9), const Color(0xFFC8E6C9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: DriftProTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ferie ${quota.year}', style: DriftProTheme.labelLg),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$remaining',
                style: DriftProTheme.headingXl.copyWith(
                  fontSize: 52,
                  color: DriftProTheme.primaryGreen,
                  height: 1,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('dager igjen', style: DriftProTheme.bodyMd),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Tildelt: ${quota.vacationDaysTotal} · Overført: ${quota.vacationDaysCarriedOver} · '
            'Brukt: $used · Totalt: $total',
            style: DriftProTheme.caption,
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: total > 0 ? (used / total).clamp(0.0, 1.0) : 0,
              minHeight: 10,
              backgroundColor: Colors.white.withValues(alpha: 0.3),
              valueColor: const AlwaysStoppedAnimation(DriftProTheme.primaryGreen),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(Icons.swap_horiz, 'Kan overføres: $carry dager', isDark),
              if (nextTotal != null)
                _chip(
                  Icons.calendar_month,
                  'Neste år (est.): $nextTotal dager',
                  isDark,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: DriftProTheme.primaryGreen),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class QuotaMiniRow extends StatelessWidget {
  final String label;
  final int used;
  final int total;
  final Color color;

  const QuotaMiniRow({
    super.key,
    required this.label,
    required this.used,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade100,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: DriftProTheme.labelMd),
              Text('$used / $total dager', style: DriftProTheme.caption),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total > 0 ? (used / total).clamp(0.0, 1.0) : 0,
              minHeight: 6,
              backgroundColor: color.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}
