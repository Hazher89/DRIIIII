import 'package:flutter/material.dart';

import '../../../core/constants/leave_rules.dart';
import '../../../core/services/absence/employee_leave_stats.dart';
import '../../../core/theme/absence_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/leave_usage_colors.dart';
import '../../../models/absence.dart';
import '../../../models/user_profile.dart';
import '../../absence/widgets/leave_employee_kpi_widgets.dart';

/// Ansattkort med fraværssaldo — samme data som Team & kalender.
class DepartmentMemberLeaveCard extends StatelessWidget {
  final UserProfile member;
  final EmployeeLeaveSnapshot stats;
  final int selectedYear;
  final VoidCallback? onEditQuota;
  final List<Absence> recentAbsences;

  const DepartmentMemberLeaveCard({
    super.key,
    required this.member,
    required this.stats,
    required this.selectedYear,
    this.onEditQuota,
    this.recentAbsences = const [],
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onLeaveToday = recentAbsences.any((a) {
      if (a.status != AbsenceStatus.godkjent) return false;
      final now = DateTime.now();
      return !now.isBefore(a.startDate) && !now.isAfter(a.endDate);
    });
    final pending =
        recentAbsences.where((a) => a.status == AbsenceStatus.ventende).length;
    final worst = LeaveUsageColors.worst(
      LeaveUsageColors.worst(stats.ferieLevel, stats.egenLevel),
      stats.syktLevel,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: worst == LeaveUsageLevel.critical
              ? AbsencePalette.usageCritical.withValues(alpha: 0.35)
              : worst == LeaveUsageLevel.warning
                  ? AbsencePalette.usageWarning.withValues(alpha: 0.3)
                  : (isDark ? DriftProTheme.dividerDark : Colors.grey.shade100),
          width: worst == LeaveUsageLevel.ok ? 1 : 1.5,
        ),
        boxShadow: DriftProTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AbsencePalette.indigo.withValues(alpha: 0.12),
                child: Text(
                  member.initials,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AbsencePalette.indigo,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(member.fullName, style: DriftProTheme.labelLg),
                    Text(
                      [
                        if (member.employeeNumber != null)
                          'nr ${member.employeeNumber}',
                        member.role.name,
                      ].join(' · '),
                      style: DriftProTheme.caption,
                    ),
                  ],
                ),
              ),
              if (onLeaveToday)
                _statusChip('Borte i dag', AbsencePalette.indigo)
              else if (pending > 0)
                _statusChip('$pending venter', AbsencePalette.violet)
              else if (onEditQuota != null)
                IconButton(
                  tooltip: 'Endre feriekvote',
                  icon: const Icon(Icons.edit_note_rounded, size: 20),
                  onPressed: onEditQuota,
                ),
            ],
          ),
          const SizedBox(height: 12),
          LeaveEmployeeKpiRow(stats: stats, selectedYear: selectedYear),
          const SizedBox(height: 8),
          Text(
            '${stats.totalFravaerDager} dager fravær totalt · '
            '${stats.egenTilfeller}/${LeaveRules.egenmeldingMaxPeriodsPerYear} egenm.tilfeller',
            style: DriftProTheme.caption.copyWith(fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
      ),
    );
  }
}
