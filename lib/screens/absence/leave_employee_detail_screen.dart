import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/leave_rules.dart';
import '../../core/services/absence/employee_leave_stats.dart';
import '../../core/services/absence/leave_period_usage_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/leave_period_window.dart';
import '../../models/absence.dart';
import '../../models/user_profile.dart';
import 'new_absence_screen.dart';
import 'widgets/absence_excel_export_sheet.dart';
import 'widgets/leave_employee_stats_panel.dart';
import 'widgets/leave_period_scope.dart';
import 'widgets/leave_quick_actions.dart';
import 'widgets/leave_type_dates_sheet.dart';

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
    this.onYearChanged,
    this.teamProfiles = const [],
    this.teamQuotas = const [],
    this.allAbsences = const [],
    this.approverNames = const {},
    this.companyName,
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
  final ValueChanged<int>? onYearChanged;
  final List<UserProfile> teamProfiles;
  final List<AbsenceQuota> teamQuotas;
  final List<Absence> allAbsences;
  final Map<String, String> approverNames;
  final String? companyName;

  @override
  State<LeaveEmployeeDetailScreen> createState() =>
      _LeaveEmployeeDetailScreenState();
}

class _LeaveEmployeeDetailScreenState extends State<LeaveEmployeeDetailScreen> {
  late LeavePeriodScope _scope;

  @override
  void initState() {
    super.initState();
    _scope = LeavePeriodScope.year(widget.selectedYear);
  }

  @override
  void didUpdateWidget(covariant LeaveEmployeeDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedYear != widget.selectedYear &&
        _scope.mode == LeavePeriodMode.year &&
        _scope.year != widget.selectedYear) {
      _scope = LeavePeriodScope.year(widget.selectedYear);
    }
  }

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

  void _onScopeChanged(LeavePeriodScope scope) {
    setState(() => _scope = scope);
    if (scope.mode == LeavePeriodMode.year) {
      widget.onYearChanged?.call(scope.year);
    } else {
      widget.onYearChanged?.call(scope.year);
    }
  }

  List<Absence> get _allEmployeeAbsences => widget.absencesOf();

  List<Absence> get _scopedAbsences => _scope.filter(_allEmployeeAbsences);

  EmployeeLeaveSnapshot _stats(AbsenceQuota? quota) {
    // År/periode-velger styrer alltid vinduet (kalenderår eller fra–til),
    // ikke jubileumsperiode — så egenmelding ikke summerer alle år.
    final usage = LeavePeriodUsageService.computeForWindow(
      absences: _allEmployeeAbsences,
      window: LeavePeriodWindow(
        periodStart: _scope.rangeStart,
        periodEnd: _scope.rangeEnd,
      ),
    );
    return EmployeeLeaveSnapshot.compute(
      employee: widget.employee,
      employeeAbsences: _allEmployeeAbsences,
      quota: quota,
      company: widget.company,
      referenceDate: _scope.referenceDate,
      periodUsageOverride: usage,
    );
  }

  Future<void> _showTypeDates(AbsenceType type, String title) {
    final list = _scopedAbsences.where((a) => a.type == type).toList();
    return showLeaveTypeDatesSheet(
      context,
      title: title,
      absences: list,
      approverNames: widget.approverNames,
      onTap: widget.onAbsenceTap,
    );
  }

  Future<void> _exportExcel() {
    final employees = widget.teamProfiles.isEmpty
        ? [widget.employee]
        : widget.teamProfiles;
    final absences =
        widget.allAbsences.isEmpty ? _allEmployeeAbsences : widget.allAbsences;
    final quotas =
        widget.teamQuotas.isEmpty && widget.quotaOf() != null
            ? [widget.quotaOf()!]
            : widget.teamQuotas;
    return showAbsenceExcelExportSheet(
      context,
      employees: employees,
      absences: absences,
      quotas: quotas,
      departmentNames: widget.departmentNames,
      approverNames: widget.approverNames,
      initialScope: _scope,
      company: widget.company,
      companyName: widget.companyName,
      lockedEmployeeId: widget.employee.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final df = DateFormat('d. MMM yyyy', 'nb_NO');
    final quota = widget.quotaOf();
    final scoped = [..._scopedAbsences]
      ..sort((a, b) => b.startDate.compareTo(a.startDate));
    final stats = _stats(quota);

    return Scaffold(
      backgroundColor:
          isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(
        title: Text(widget.employee.fullName),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Flere valg',
            onSelected: (v) async {
              switch (v) {
                case 'quota':
                  widget.onEditQuota?.call();
                  await widget.onChanged?.call();
                  if (mounted) setState(() {});
                case 'export':
                  await _exportExcel();
              }
            },
            itemBuilder: (_) => [
              if (widget.canEditQuota && widget.onEditQuota != null)
                const PopupMenuItem(
                  value: 'quota',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.tune_rounded),
                    title: Text('Rediger feriekvote'),
                  ),
                ),
              const PopupMenuItem(
                value: 'export',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.file_download_outlined),
                  title: Text('Eksporter Excel'),
                ),
              ),
            ],
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
          Row(
            children: [
              Expanded(
                child: Text(
                  'Ansattvisning',
                  style: DriftProTheme.caption.copyWith(
                    color: DriftProTheme.primaryGreen,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              LeavePeriodScopeButton(
                scope: _scope,
                onChanged: _onScopeChanged,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: DriftProTheme.primaryGreen.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: DriftProTheme.primaryGreen.withValues(alpha: 0.25),
              ),
            ),
            child: Text(
              'Saldo og liste følger ${_scope.shortLabel.toLowerCase()}. '
              'Trykk info på kortene for å se datoene.',
              style: DriftProTheme.bodySm,
            ),
          ),
          const SizedBox(height: 16),
          LeaveEmployeeStatsPanel(
            employee: widget.employee,
            quota: quota,
            company: widget.company,
            selectedYear: _scope.year,
            employeeAbsences: scoped,
            departmentNames: widget.departmentNames,
            statsOverride: stats,
            hideDragHandle: true,
            hideRecentList: true,
            onFerieInfo: () => _showTypeDates(
              AbsenceType.ferie,
              'Ferie · ${_scope.shortLabel}',
            ),
            onEgenmeldingInfo: () => _showTypeDates(
              AbsenceType.egenmelding,
              'Egenmelding · ${_scope.shortLabel}',
            ),
            onSyktBarnInfo: () => _showTypeDates(
              AbsenceType.syktBarn,
              'Sykt barn · ${_scope.shortLabel}',
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _exportExcel,
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: const Text('Eksporter Excel'),
              style: OutlinedButton.styleFrom(
                foregroundColor: DriftProTheme.primaryGreen,
                side: BorderSide(
                  color: DriftProTheme.primaryGreen.withValues(alpha: 0.45),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Registreringer i perioden',
            style: DriftProTheme.labelLg.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (scoped.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Ingen ferie eller fravær i ${_scope.shortLabel.toLowerCase()}.',
                style: DriftProTheme.caption,
                textAlign: TextAlign.center,
              ),
            )
          else
            ...scoped.map((a) {
              final days = a.totalDays ??
                  a.endDate.difference(a.startDate).inDays + 1;
              final approver = a.approvedBy == null
                  ? null
                  : widget.approverNames[a.approvedBy!];
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
                                if (approver != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Godkjent av $approver',
                                    style: DriftProTheme.caption,
                                  ),
                                ],
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
                              Text(a.status.label,
                                  style: DriftProTheme.caption),
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
