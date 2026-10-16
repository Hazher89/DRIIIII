import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/leave_rules.dart';
import '../../core/theme/app_theme.dart';
import '../../models/absence.dart';
import '../../models/user_profile.dart';
import 'new_absence_screen.dart';
import 'widgets/leave_employee_stats_panel.dart';
import 'widgets/leave_quick_actions.dart';

/// Full side for én ansatt — saldo, historikk og registrering låst til personen.
class LeaveEmployeeDetailScreen extends StatefulWidget {
  const LeaveEmployeeDetailScreen({
    super.key,
    required this.employee,
    required this.quotaOf,
    required this.company,
    required this.selectedYear,
    required this.absencesOf,
    required this.departmentNames,
    required this.canRegister,
    required this.canEditQuota,
    this.onEditQuota,
    this.onAbsenceTap,
    this.onChanged,
  });

  final UserProfile employee;
  final AbsenceQuota? Function() quotaOf;
  final CompanyLeaveSettings company;
  final int selectedYear;
  final List<Absence> Function() absencesOf;
  final Map<String, String> departmentNames;
  final bool canRegister;
  final bool canEditQuota;
  final VoidCallback? onEditQuota;
  final void Function(Absence absence)? onAbsenceTap;
  final Future<void> Function()? onChanged;

  @override
  State<LeaveEmployeeDetailScreen> createState() =>
      _LeaveEmployeeDetailScreenState();
}

class _LeaveEmployeeDetailScreenState extends State<LeaveEmployeeDetailScreen> {
  Future<void> _openRegister() async {
    final type = await showLeaveTypePickerSheet(
      context,
      employeeName: widget.employee.fullName,
    );
    if (type == null || !mounted) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => NewAbsenceScreen(
          type: type,
          lockedEmployee: widget.employee,
        ),
      ),
    );
    if (saved == true) {
      await widget.onChanged?.call();
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final df = DateFormat('d. MMM yyyy', 'nb_NO');
    final employeeAbsences = widget.absencesOf();
    final quota = widget.quotaOf();
    final sorted = [...employeeAbsences]
      ..sort((a, b) => b.startDate.compareTo(a.startDate));

    return Scaffold(
      backgroundColor:
          isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(
        title: Text(widget.employee.fullName),
        actions: [
          if (widget.canEditQuota && widget.onEditQuota != null)
            IconButton(
              tooltip: 'Rediger feriekvote',
              onPressed: () async {
                widget.onEditQuota!();
                await widget.onChanged?.call();
                if (mounted) setState(() {});
              },
              icon: const Icon(Icons.edit_calendar_outlined),
            ),
        ],
      ),
      floatingActionButton: widget.canRegister
          ? FloatingActionButton.extended(
              onPressed: _openRegister,
              icon: const Icon(Icons.add_task),
              label: const Text('Ny registrering'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: DriftProTheme.primaryGreen.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: DriftProTheme.primaryGreen.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor:
                      DriftProTheme.primaryGreen.withValues(alpha: 0.15),
                  child: Text(
                    widget.employee.fullName.isNotEmpty
                        ? widget.employee.fullName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: DriftProTheme.primaryGreen,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ansattvisning',
                        style: DriftProTheme.caption.copyWith(
                          color: DriftProTheme.primaryGreen,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'All registrering og oversikt gjelder kun denne personen.',
                        style: DriftProTheme.bodySm,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          LeaveEmployeeStatsPanel(
            employee: widget.employee,
            quota: quota,
            company: widget.company,
            selectedYear: widget.selectedYear,
            employeeAbsences: employeeAbsences,
            departmentNames: widget.departmentNames,
            onEditQuota: widget.canEditQuota ? widget.onEditQuota : null,
          ),
          const SizedBox(height: 20),
          Text(
            'Alle registreringer',
            style: DriftProTheme.labelLg.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (sorted.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Ingen ferie eller fravær registrert.',
                style: DriftProTheme.caption,
                textAlign: TextAlign.center,
              ),
            )
          else
            ...sorted.map((a) {
              final days = a.totalDays ??
                  a.endDate.difference(a.startDate).inDays + 1;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: isDark ? DriftProTheme.cardDark : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: widget.onAbsenceTap == null
                        ? null
                        : () => widget.onAbsenceTap!(a),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark
                              ? DriftProTheme.dividerDark
                              : Colors.grey.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  a.type.label,
                                  style: DriftProTheme.labelMd.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${df.format(a.startDate)} – ${df.format(a.endDate)}',
                                  style: DriftProTheme.bodySm,
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '$days d',
                                style: DriftProTheme.labelMd.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(a.status.label, style: DriftProTheme.caption),
                            ],
                          ),
                          if (widget.onAbsenceTap != null) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.chevron_right, size: 20),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
