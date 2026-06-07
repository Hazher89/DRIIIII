import 'package:flutter/material.dart';

import '../../../core/constants/leave_rules.dart';
import '../../../core/services/absence/absence_service.dart';
import '../../../core/services/absence/leave_period_usage_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/absence.dart';
import '../../../models/user_profile.dart';

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
    final periodUsage = LeavePeriodUsageService.compute(
      absences: employeeAbsences,
      hireDate: employee.hireDate,
    );
    final approved = employeeAbsences
        .where((a) => a.status == AbsenceStatus.godkjent)
        .toList();
    final egenDays = approved
        .where((a) => a.type == AbsenceType.egenmelding)
        .fold<int>(
          0,
          (s, a) =>
              s + (a.totalDays ?? AbsenceService.dayCount(a.startDate, a.endDate)),
        );
    final syktDays = periodUsage.syktBarnDaysUsed;
    final syktMax = company.syktBarnDaysLimit(
      childrenUnder12: employee.childrenUnder12Count,
    );
    final ferieIgjen = quota?.vacationDaysRemaining ?? 0;
    final egenMax = company.egenmeldingDaysPerYear;
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
              _miniStat(
                Icons.beach_access,
                '$ferieIgjen',
                'ferie',
                DriftProTheme.absenceVacation,
              ),
              _divider(isDark),
              _miniStat(
                Icons.sick_outlined,
                '$egenDays/$egenMax',
                'egen',
                DriftProTheme.absenceSickSelf,
              ),
              _divider(isDark),
              _miniStat(
                Icons.child_care_outlined,
                '$syktDays/$syktMax',
                'sykt',
                DriftProTheme.absenceSickChild,
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

  Widget _miniStat(IconData icon, String value, String label, Color color) {
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
    final periodUsage = LeavePeriodUsageService.compute(
      absences: employeeAbsences,
      hireDate: employee.hireDate,
    );
    final approved = employeeAbsences
        .where((a) => a.status == AbsenceStatus.godkjent)
        .toList();
    final egenRecords =
        approved.where((a) => a.type == AbsenceType.egenmelding).toList();
    final egenDaysTotal = egenRecords.fold<int>(
      0,
      (sum, a) =>
          sum + (a.totalDays ?? AbsenceService.dayCount(a.startDate, a.endDate)),
    );
    final egenTilfeller = egenRecords.length;
    final syktDays = periodUsage.syktBarnDaysUsed;
    final totalFravaerDager = egenDaysTotal + syktDays;
    final syktMax = company.syktBarnDaysLimit(
      childrenUnder12: employee.childrenUnder12Count,
    );
    final egenMax = company.egenmeldingDaysPerYear;
    final dept = employee.departmentId != null
        ? departmentNames[employee.departmentId!]
        : null;

    final ferieIgjen = quota?.vacationDaysRemaining ?? 0;
    final ferieTotal = quota?.totalVacationDays ?? 25;
    final ferieBrukt = quota?.vacationDaysUsed ?? 0;

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
              _badge('$totalFravaerDager dager fravær', DriftProTheme.primaryGreen),
          ],
        ),
        const SizedBox(height: 14),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _kpiCard(
                  isDark,
                  icon: Icons.beach_access,
                  label: 'Ferie $selectedYear',
                  value: '$ferieIgjen',
                  unit: 'dager igjen',
                  sub: '$ferieBrukt av $ferieTotal brukt',
                  color: DriftProTheme.absenceVacation,
                  progress: ferieTotal > 0 ? ferieBrukt / ferieTotal : 0,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _kpiCard(
                  isDark,
                  icon: Icons.sick_outlined,
                  label: 'Egenmelding',
                  value: '$egenDaysTotal',
                  unit: 'av $egenMax dager',
                  sub:
                      '$egenTilfeller/${LeaveRules.egenmeldingMaxPeriodsPerYear} tilfeller',
                  color: DriftProTheme.absenceSickSelf,
                  progress: egenMax > 0 ? egenDaysTotal / egenMax : 0,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _kpiCard(
                  isDark,
                  icon: Icons.child_care_outlined,
                  label: 'Sykt barn',
                  value: '$syktDays',
                  unit: 'av $syktMax dager',
                  sub: periodUsage.window.formatRange(),
                  color: DriftProTheme.absenceSickChild,
                  progress: syktMax > 0 ? syktDays / syktMax : 0,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Totalt $totalFravaerDager fraværsdager ($egenDaysTotal egenmelding + '
          '$syktDays sykt barn). Sykt barn telles i perioden '
          '${periodUsage.window.formatRange()}.',
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

  Widget _kpiCard(
    bool isDark, {
    required IconData icon,
    required String label,
    required String value,
    required String unit,
    required String sub,
    required Color color,
    required double progress,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.surfaceDark : color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
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
                  style: DriftProTheme.caption.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
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
          const SizedBox(height: 2),
          Text(
            sub,
            style: DriftProTheme.caption.copyWith(fontSize: 8),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
