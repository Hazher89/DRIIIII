import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/company_principals.dart';
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

/// Full saldo for valgt ansatt — vises i bottom sheet / sidepanel.
class LeaveEmployeeStatsPanel extends StatelessWidget {
  final UserProfile employee;
  final AbsenceQuota? quota;
  final CompanyLeaveSettings company;
  final int selectedYear;
  final List<Absence> employeeAbsences;
  final Map<String, String> departmentNames;
  final VoidCallback? onEditQuota;

  const LeaveEmployeeStatsPanel({
    super.key,
    required this.employee,
    required this.quota,
    required this.company,
    required this.selectedYear,
    required this.employeeAbsences,
    required this.departmentNames,
    this.onEditQuota,
  });

  static Future<void> showSheet(
    BuildContext context, {
    required UserProfile employee,
    required AbsenceQuota? quota,
    required CompanyLeaveSettings company,
    required int selectedYear,
    required List<Absence> employeeAbsences,
    required Map<String, String> departmentNames,
    VoidCallback? onEditQuota,
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
        initialChildSize: 0.72,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, scrollCtrl) => SingleChildScrollView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          child: LeaveEmployeeStatsPanel(
            employee: employee,
            quota: quota,
            company: company,
            selectedYear: selectedYear,
            employeeAbsences: employeeAbsences,
            departmentNames: departmentNames,
            onEditQuota: onEditQuota,
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
    final df = DateFormat('dd.MM.yyyy');
    final dfShort = DateFormat('d. MMM', 'nb_NO');

    final pending = employeeAbsences
        .where((a) => a.status == AbsenceStatus.ventende)
        .toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    final recent = [...employeeAbsences]
      ..sort((a, b) => b.startDate.compareTo(a.startDate));
    final onLeaveToday = employeeAbsences.any((a) {
      if (a.status != AbsenceStatus.godkjent) return false;
      final now = DateTime.now();
      final t = DateTime(now.year, now.month, now.day);
      final s = DateTime(a.startDate.year, a.startDate.month, a.startDate.day);
      final e = DateTime(a.endDate.year, a.endDate.month, a.endDate.day);
      return !t.isBefore(s) && !t.isAfter(e);
    });

    final hireMissing = employee.hireDate == null;

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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 22,
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
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (dept != null) dept,
                      if (employee.employeeNumber != null)
                        'nr ${employee.employeeNumber}',
                      employee.displayTitle,
                    ].where((s) => s.toString().trim().isNotEmpty).join(' · '),
                    style: DriftProTheme.caption,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    employee.hireDate != null
                        ? 'Ansatt siden ${df.format(employee.hireDate!)}'
                        : 'Ansettelsesdato mangler',
                    style: DriftProTheme.caption.copyWith(
                      color: hireMissing ? DriftProTheme.warning : null,
                      fontWeight: hireMissing ? FontWeight.w700 : null,
                    ),
                  ),
                ],
              ),
            ),
            if (onEditQuota != null)
              IconButton(
                tooltip: 'Rediger feriekvote',
                onPressed: onEditQuota,
                icon: const Icon(Icons.edit_calendar_outlined),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (onLeaveToday)
              _badge('Borte i dag', DriftProTheme.warning)
            else
              _badge('På jobb', DriftProTheme.primaryGreen),
            if (pending.isNotEmpty)
              _badge('${pending.length} venter', DriftProTheme.warning),
            _badge(
              '${stats.totalFravaerDager} d fravær',
              stats.quotaUsageLevel == LeaveUsageLevel.critical
                  ? DriftProTheme.error
                  : DriftProTheme.absenceSickSelf,
            ),
            AbsenceRateBadge(
              percent: stats.absenceRatePercent(refDate),
              level: stats.absenceRateLevel(refDate),
            ),
          ],
        ),
        if (hireMissing) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: DriftProTheme.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: DriftProTheme.warning.withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              'Uten ansettelsesdato brukes kalenderår ${refDate.year} for '
              'egenmelding/sykt barn. Sett ansettelsesdato på ansattprofilen '
              'for korrekt 12-månedersperiode.',
              style: DriftProTheme.caption.copyWith(height: 1.35),
            ),
          ),
        ],
        const SizedBox(height: 16),
        LeaveEmployeeKpiRow(stats: stats, selectedYear: selectedYear),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? DriftProTheme.surfaceDark : const Color(0xFFF7FBF8),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Periode & kvote',
                style: DriftProTheme.labelSm.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Egenmelding / sykt barn: ${stats.periodUsage.window.formatRangeWithBasis()}',
                style: DriftProTheme.caption,
              ),
              const SizedBox(height: 4),
              Text(
                'Ferie følger kalenderår $selectedYear '
                '(${stats.ferieUsed} brukt · ${stats.ferieRemaining} igjen av ${stats.ferieTotal}).',
                style: DriftProTheme.caption,
              ),
              const SizedBox(height: 4),
              Text(
                'Totalt ${stats.totalFravaerDager} fraværsdager '
                '(${stats.egenDaysTotal} d egen · ${stats.egenTilfeller} tilf. · '
                '${stats.syktDays} d sykt barn). '
                'Fravær YTD: ${stats.absenceRatePercent(refDate).round()}% av virkedager.',
                style: DriftProTheme.caption.copyWith(height: 1.35),
              ),
            ],
          ),
        ),
        if (pending.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Ventende søknader',
            style: DriftProTheme.labelSm.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          ...pending.map(
            (a) => _absenceLine(a, dfShort, highlight: true),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Siste fravær',
          style: DriftProTheme.labelSm.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        if (recent.isEmpty)
          Text('Ingen registrerte søknader', style: DriftProTheme.caption)
        else
          ...recent.take(8).map((a) => _absenceLine(a, dfShort)),
      ],
    );
  }

  Widget _absenceLine(Absence a, DateFormat df, {bool highlight = false}) {
    final days = a.totalDays ??
        a.endDate.difference(a.startDate).inDays + 1;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: highlight
            ? DriftProTheme.warning.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: highlight
              ? DriftProTheme.warning.withValues(alpha: 0.3)
              : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${a.type.label} · ${df.format(a.startDate)}–${df.format(a.endDate)}',
              style: DriftProTheme.bodySm.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Text('$days d', style: DriftProTheme.caption),
          const SizedBox(width: 8),
          Text(a.status.label, style: DriftProTheme.caption),
        ],
      ),
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
