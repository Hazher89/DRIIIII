import 'package:flutter/material.dart';

import '../../../core/constants/leave_rules.dart';
import '../../../core/services/absence/absence_excel_export_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/absence.dart';
import '../../../models/user_profile.dart';
import 'leave_period_scope.dart';

Future<void> showAbsenceExcelExportSheet(
  BuildContext context, {
  required List<UserProfile> employees,
  required List<Absence> absences,
  required List<AbsenceQuota> quotas,
  required Map<String, String> departmentNames,
  required Map<String, String> approverNames,
  required LeavePeriodScope initialScope,
  CompanyLeaveSettings company = const CompanyLeaveSettings(),
  String? companyName,
  String? lockedEmployeeId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _AbsenceExcelExportSheet(
      employees: employees,
      absences: absences,
      quotas: quotas,
      departmentNames: departmentNames,
      approverNames: approverNames,
      initialScope: initialScope,
      company: company,
      companyName: companyName,
      lockedEmployeeId: lockedEmployeeId,
    ),
  );
}

class _AbsenceExcelExportSheet extends StatefulWidget {
  const _AbsenceExcelExportSheet({
    required this.employees,
    required this.absences,
    required this.quotas,
    required this.departmentNames,
    required this.approverNames,
    required this.initialScope,
    required this.company,
    this.companyName,
    this.lockedEmployeeId,
  });

  final List<UserProfile> employees;
  final List<Absence> absences;
  final List<AbsenceQuota> quotas;
  final Map<String, String> departmentNames;
  final Map<String, String> approverNames;
  final LeavePeriodScope initialScope;
  final CompanyLeaveSettings company;
  final String? companyName;
  final String? lockedEmployeeId;

  @override
  State<_AbsenceExcelExportSheet> createState() =>
      _AbsenceExcelExportSheetState();
}

class _AbsenceExcelExportSheetState extends State<_AbsenceExcelExportSheet> {
  late LeavePeriodScope _scope;
  AbsenceExportTypeFilter _type = AbsenceExportTypeFilter.alle;
  late bool _allEmployees;
  String? _employeeId;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scope = widget.initialScope;
    _allEmployees = widget.lockedEmployeeId == null;
    _employeeId = widget.lockedEmployeeId ??
        (widget.employees.isEmpty ? null : widget.employees.first.id);
  }

  List<UserProfile> get _employeeOptions => widget.employees
      .where((e) => !e.isPartnerPortalUser)
      .toList()
    ..sort((a, b) => a.fullName.compareTo(b.fullName));

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AbsenceExcelExportService.export(
        employees: widget.employees,
        absences: widget.absences,
        quotas: widget.quotas,
        departmentNames: widget.departmentNames,
        approverNames: widget.approverNames,
        rangeStart: _scope.rangeStart,
        rangeEnd: _scope.rangeEnd,
        typeFilter: _type,
        company: widget.company,
        companyName: widget.companyName,
        singleEmployeeId: _allEmployees ? null : _employeeId,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Eksporter til Excel',
            style: DriftProTheme.headingSm.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            'Velg type, periode og om du vil ha én ansatt eller hele teamet.',
            style: DriftProTheme.caption,
          ),
          const SizedBox(height: 16),
          Text('Type', style: DriftProTheme.labelMd.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in AbsenceExportTypeFilter.values)
                ChoiceChip(
                  label: Text(t.label),
                  selected: _type == t,
                  onSelected: (_) => setState(() => _type = t),
                  selectedColor:
                      DriftProTheme.primaryGreen.withValues(alpha: 0.2),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Periode',
              style: DriftProTheme.labelMd.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          LeavePeriodScopeButton(
            scope: _scope,
            onChanged: (s) => setState(() => _scope = s),
          ),
          const SizedBox(height: 16),
          Text('Ansatte',
              style: DriftProTheme.labelMd.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (widget.lockedEmployeeId != null)
            Text(
              () {
                for (final e in _employeeOptions) {
                  if (e.id == widget.lockedEmployeeId) return e.fullName;
                }
                return 'Valgt ansatt';
              }(),
              style: DriftProTheme.bodySm.copyWith(fontWeight: FontWeight.w700),
            )
          else ...[
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Alle')),
                ButtonSegment(value: false, label: Text('Én ansatt')),
              ],
              selected: {_allEmployees},
              onSelectionChanged: (s) =>
                  setState(() => _allEmployees = s.first),
            ),
            if (!_allEmployees) ...[
              const SizedBox(height: 10),
              InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Velg ansatt',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _employeeId,
                    isExpanded: true,
                    items: [
                      for (final e in _employeeOptions)
                        DropdownMenuItem(
                          value: e.id,
                          child: Text(e.fullName),
                        ),
                    ],
                    onChanged: (v) => setState(() => _employeeId = v),
                  ),
                ),
              ),
            ],
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: DriftProTheme.error)),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _busy ? null : _export,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.file_download_outlined),
            label: Text(_busy ? 'Lager fil…' : 'Last ned Excel'),
            style: FilledButton.styleFrom(
              backgroundColor: DriftProTheme.primaryGreen,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}
