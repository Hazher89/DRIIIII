import 'package:flutter/material.dart';

import '../../../core/constants/leave_rules.dart';
import '../../../core/services/absence/employee_leave_stats.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/leave_usage_colors.dart';
import '../../../models/absence.dart';
import '../../../models/user_profile.dart';
import 'leave_absence_rate_widgets.dart';
import 'leave_employee_kpi_widgets.dart';

DateTime _leaveStatsReferenceDate(int selectedYear) {
  final now = DateTime.now();
  if (selectedYear < now.year) return DateTime(selectedYear, 12, 31);
  if (selectedYear > now.year) return DateTime(selectedYear, 1, 1);
  return now;
}

/// Én-linje KPI-stripe — trykk for full saldo.
class LeaveEmployeeStatsCompactBar extends StatelessWidget {
  final UserProfile employee;
  final AbsenceQuota? quota;
  final CompanyLeaveSettings company;
  final int selectedYear;
  final List<Absence> employeeAbsences;
  final VoidCallback? onTapDetails;

  const LeaveEmployeeStatsCompactBar({
    super.key,
    required this.employee,
    required this.quota,
    required this.company,
    required this.selectedYear,
    required this.employeeAbsences,
    this.onTapDetails,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final refDate = _leaveStatsReferenceDate(selectedYear);
    final stats = EmployeeLeaveSnapshot.compute(
      employee: employee,
      employeeAbsences: employeeAbsences,
      quota: quota,
      company: company,
      referenceDate: refDate,
    );
    final pending = employeeAbsences
        .where((a) => a.status == AbsenceStatus.ventende)
        .length;

    return Material(
      color: isDark ? DriftProTheme.surfaceDark : const Color(0xFFF7FBF8),
      child: InkWell(
        onTap: onTapDetails,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              LeaveEmployeeCompactStat(
                icon: Icons.beach_access,
                value: '${stats.ferieRemaining} d',
                label: 'ferie igjen',
                baseColor: DriftProTheme.absenceVacation,
                level: stats.ferieLevel,
              ),
              _divider(isDark),
              LeaveEmployeeCompactStat(
                icon: Icons.sick_outlined,
                value: '${stats.egenDaysTotal} d',
                label: '${stats.egenTilfeller} tilf.',
                baseColor: DriftProTheme.absenceSickSelf,
                level: stats.egenLevel,
              ),
              _divider(isDark),
              LeaveEmployeeCompactStat(
                icon: Icons.child_care_outlined,
                value: '${stats.syktDays} d',
                label: 'av ${stats.syktMax} d',
                baseColor: DriftProTheme.absenceSickChild,
                level: stats.syktLevel,
              ),
              _divider(isDark),
              AbsenceRateBadge(
                percent: stats.absenceRatePercent(refDate),
                level: stats.absenceRateLevel(refDate),
                compact: true,
              ),
              const Spacer(),
              if (pending > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: DriftProTheme.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$pending venter',
                    style: TextStyle(
                      color: DriftProTheme.warning,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else
                Icon(
                  Icons.expand_more,
                  size: 18,
                  color: isDark ? Colors.white38 : Colors.grey.shade500,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _divider(bool isDark) {
    return Container(
      width: 1,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200,
    );
  }
}

/// Full saldo for valgt ansatt — vises i bottom sheet.
class LeaveEmployeeStatsPanel extends StatelessWidget {
  final UserProfile employee;
  final AbsenceQuota? quota;
  final CompanyLeaveSettings company;
  final int selectedYear;
  final List<Absence> employeeAbsences;
  final Map<String, String> departmentNames;

  const LeaveEmployeeStatsPanel({
    super.key,
    required this.employee,
    required this.quota,
    required this.company,
    required this.selectedYear,
    required this.employeeAbsences,
    required this.departmentNames,
  });

  static Future<void> showSheet(
    BuildContext context, {
    required UserProfile employee,
    required AbsenceQuota? quota,
    required CompanyLeaveSettings company,
    required int selectedYear,
    required List<Absence> employeeAbsences,
    required Map<String, String> departmentNames,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        builder: (_, scrollCtrl) => SingleChildScrollView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: LeaveEmployeeStatsPanel(
            employee: employee,
            quota: quota,
            company: company,
            selectedYear: selectedYear,
            employeeAbsences: employeeAbsences,
            departmentNames: departmentNames,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final refDate = _leaveStatsReferenceDate(selectedYear);
    final stats = EmployeeLeaveSnapshot.compute(
      employee: employee,
      employeeAbsences: employeeAbsences,
      quota: quota,
      company: company,
      referenceDate: refDate,
    );
    final dept = employee.departmentId != null
        ? departmentNames[employee.departmentId!]
        : null;

    final pending = employeeAbsences
        .where((a) => a.status == AbsenceStatus.ventende)
        .length;
    final onLeaveToday = employeeAbsences.any((a) {
      if (a.status != AbsenceStatus.godkjent) return false;
      final now = DateTime.now();
      return !now.isBefore(a.startDate) && !now.isAfter(a.endDate);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: DriftProTheme.primaryGreen.withValues(alpha: 0.12),
              child: Text(
                employee.fullName.isNotEmpty
                    ? employee.fullName[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  color: DriftProTheme.primaryGreen,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(employee.fullName, style: DriftProTheme.labelLg),
                  Text(
                    [
                      if (dept != null) dept,
                      if (employee.employeeNumber != null)
                        'nr ${employee.employeeNumber}',
                    ].join(' · '),
                    style: DriftProTheme.caption,
                  ),
                ],
              ),
            ),
            if (onLeaveToday)
              _badge('Borte i dag', DriftProTheme.warning)
            else if (pending > 0)
              _badge('$pending venter', DriftProTheme.warning)
            else
              _badge(
                '${stats.totalFravaerDager} dager fravær',
                stats.egenLevel == LeaveUsageLevel.critical ||
                        stats.syktLevel == LeaveUsageLevel.critical
                    ? DriftProTheme.error
                    : stats.egenLevel == LeaveUsageLevel.warning ||
                            stats.syktLevel == LeaveUsageLevel.warning
                        ? Colors.orange.shade700
                        : DriftProTheme.primaryGreen,
              ),
          ],
        ),
        const SizedBox(height: 14),
        LeaveEmployeeKpiRow(stats: stats, selectedYear: selectedYear),
        const SizedBox(height: 10),
        Text(
          'Totalt ${stats.totalFravaerDager} fraværsdager '
          '(${stats.egenDaysTotal} d egen · ${stats.egenTilfeller} tilf. · '
          '${stats.syktDays} d sykt barn). '
          'Egen kvote: ${stats.egenQuotaPercent.round()}% · '
          'Sykt barn: ${stats.syktQuotaPercent.round()}% · '
          'Fravær YTD: ${stats.absenceRatePercent(refDate).round()}% av virkedager.',
          style: DriftProTheme.caption.copyWith(
            color: isDark ? Colors.white54 : Colors.grey.shade600,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
      ),
    );
  }
}
