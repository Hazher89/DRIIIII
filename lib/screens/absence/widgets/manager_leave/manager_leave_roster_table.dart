import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../models/absence.dart';
import '../../../../models/user_profile.dart';
import 'manager_leave_helpers.dart';

class ManagerLeaveRosterTable extends StatefulWidget {
  const ManagerLeaveRosterTable({
    super.key,
    required this.employees,
    required this.absences,
    required this.quotas,
    required this.departmentNames,
    required this.year,
    required this.onOpenEmployee,
    this.onYearChanged,
  });

  final List<UserProfile> employees;
  final List<Absence> absences;
  final List<AbsenceQuota> quotas;
  final Map<String, String> departmentNames;
  final int year;
  final void Function(UserProfile employee) onOpenEmployee;
  final ValueChanged<int>? onYearChanged;

  @override
  State<ManagerLeaveRosterTable> createState() =>
      _ManagerLeaveRosterTableState();
}

class _ManagerLeaveRosterTableState extends State<ManagerLeaveRosterTable> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  String? _departmentId;
  ManagerLeaveStatusFilter _status = ManagerLeaveStatusFilter.alle;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  AbsenceQuota? _quota(String userId) {
    for (final q in widget.quotas) {
      if (q.userId == userId && q.year == widget.year) return q;
    }
    return null;
  }

  List<Absence> _absencesFor(String userId) =>
      widget.absences.where((a) => a.userId == userId).toList();

  List<String?> get _departmentOptions {
    final ids = widget.employees
        .map((e) => e.departmentId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    ids.sort((a, b) {
      final na = widget.departmentNames[a] ?? a;
      final nb = widget.departmentNames[b] ?? b;
      return na.compareTo(nb);
    });
    return <String?>[null, ...ids];
  }

  List<UserProfile> get _filtered {
    return widget.employees.where((e) {
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        final match = e.fullName.toLowerCase().contains(q) ||
            (e.employeeNumber ?? '').contains(q) ||
            (widget.departmentNames[e.departmentId] ?? '')
                .toLowerCase()
                .contains(q);
        if (!match) return false;
      }
      if (_departmentId != null && e.departmentId != _departmentId) {
        return false;
      }
      final status = ManagerLeaveHelpers.todayStatusFor(_absencesFor(e.id));
      switch (_status) {
        case ManagerLeaveStatusFilter.alle:
          return true;
        case ManagerLeaveStatusFilter.paJobb:
          return status == ManagerLeaveTodayStatus.paJobb;
        case ManagerLeaveStatusFilter.ferie:
          return status == ManagerLeaveTodayStatus.ferie;
        case ManagerLeaveStatusFilter.sykemeldt:
          return status == ManagerLeaveTodayStatus.sykemeldt ||
              status == ManagerLeaveTodayStatus.egenmelding;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rows = _filtered;

    return Container(
      width: double.infinity,
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
                  blurRadius: 14,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ansattoversikt',
                        style: DriftProTheme.labelLg.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Saldo, status i dag og neste planlagte fravær · ${widget.year}',
                        style: DriftProTheme.caption.copyWith(
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.onYearChanged != null)
                  DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: widget.year,
                      items: [
                        for (final y in [
                          widget.year - 1,
                          widget.year,
                          widget.year + 1,
                        ])
                          DropdownMenuItem(value: y, child: Text('$y')),
                      ],
                      onChanged: (y) {
                        if (y != null) widget.onYearChanged!(y);
                      },
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wrap = constraints.maxWidth < 780;
                final search = TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _search = v.trim()),
                  decoration: InputDecoration(
                    hintText: 'Søk etter ansatt...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: isDark
                            ? DriftProTheme.dividerDark
                            : const Color(0xFFE2E8F0),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: isDark
                            ? DriftProTheme.dividerDark
                            : const Color(0xFFE2E8F0),
                      ),
                    ),
                  ),
                );
                final dept = InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Avdeling',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: _departmentId,
                      isExpanded: true,
                      items: [
                        for (final id in _departmentOptions)
                          DropdownMenuItem(
                            value: id,
                            child: Text(
                              id == null
                                  ? 'Alle avdelinger'
                                  : (widget.departmentNames[id] ?? 'Uten navn'),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _departmentId = v),
                    ),
                  ),
                );
                final status = InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Status',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<ManagerLeaveStatusFilter>(
                      value: _status,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(
                          value: ManagerLeaveStatusFilter.alle,
                          child: Text('Alle'),
                        ),
                        DropdownMenuItem(
                          value: ManagerLeaveStatusFilter.paJobb,
                          child: Text('På jobb'),
                        ),
                        DropdownMenuItem(
                          value: ManagerLeaveStatusFilter.ferie,
                          child: Text('Ferie'),
                        ),
                        DropdownMenuItem(
                          value: ManagerLeaveStatusFilter.sykemeldt,
                          child: Text('Sykemeldt'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _status = v);
                      },
                    ),
                  ),
                );

                if (wrap) {
                  return Column(
                    children: [
                      search,
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: dept),
                          const SizedBox(width: 10),
                          Expanded(child: status),
                        ],
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(flex: 3, child: search),
                    const SizedBox(width: 10),
                    Expanded(flex: 2, child: dept),
                    const SizedBox(width: 10),
                    Expanded(flex: 2, child: status),
                  ],
                );
              },
            ),
          ),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 28, 18, 40),
              child: Center(
                child: Text(
                  'Ingen ansatte matcher søk eller filter',
                  style: DriftProTheme.bodySm.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 820) {
                  return Column(
                    children: [
                      for (final e in rows)
                        _EmployeeMobileRow(
                          employee: e,
                          departmentName: e.departmentId == null
                              ? null
                              : widget.departmentNames[e.departmentId!],
                          status: ManagerLeaveHelpers.todayStatusFor(
                            _absencesFor(e.id),
                          ),
                          quota: _quota(e.id),
                          next: ManagerLeaveHelpers.nextOrOngoingAbsence(
                            _absencesFor(e.id),
                          ),
                          onOpen: () => widget.onOpenEmployee(e),
                          isDark: isDark,
                        ),
                    ],
                  );
                }
                return _DesktopRosterTable(
                  employees: rows,
                  departmentNames: widget.departmentNames,
                  quotaFor: _quota,
                  absencesFor: _absencesFor,
                  onOpen: widget.onOpenEmployee,
                );
              },
            ),
        ],
      ),
    );
  }
}

class _DesktopRosterTable extends StatelessWidget {
  const _DesktopRosterTable({
    required this.employees,
    required this.departmentNames,
    required this.quotaFor,
    required this.absencesFor,
    required this.onOpen,
  });

  final List<UserProfile> employees;
  final Map<String, String> departmentNames;
  final AbsenceQuota? Function(String userId) quotaFor;
  final List<Absence> Function(String userId) absencesFor;
  final void Function(UserProfile) onOpen;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: MediaQuery.sizeOf(context).width - 64,
        ),
        child: DataTable(
          headingRowHeight: 42,
          dataRowMinHeight: 68,
          dataRowMaxHeight: 84,
          horizontalMargin: 18,
          columnSpacing: 20,
          headingTextStyle: DriftProTheme.caption.copyWith(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF64748B),
          ),
          columns: const [
            DataColumn(label: Text('ANSATT')),
            DataColumn(label: Text('STATUS I DAG')),
            DataColumn(label: Text('FERIEDAGER BRUKT')),
            DataColumn(label: Text('GJENSTÅENDE')),
            DataColumn(label: Text('NESTE PLANLAGTE FRAVÆR')),
            DataColumn(label: Text('')),
          ],
          rows: [
            for (final e in employees)
              DataRow(
                cells: [
                  DataCell(
                    _NameCell(
                      name: e.fullName,
                      avatarUrl: e.avatarUrl,
                      department: e.departmentId == null
                          ? null
                          : departmentNames[e.departmentId!],
                    ),
                  ),
                  DataCell(
                    _StatusBadge(
                      ManagerLeaveHelpers.todayStatusFor(absencesFor(e.id)),
                    ),
                  ),
                  DataCell(_VacationProgress(quota: quotaFor(e.id))),
                  DataCell(
                    Text(
                      '${quotaFor(e.id)?.vacationDaysRemaining ?? '—'} dager',
                      style: DriftProTheme.bodySm.copyWith(
                        fontWeight: FontWeight.w800,
                        color: DriftProTheme.primaryGreen,
                      ),
                    ),
                  ),
                  DataCell(
                    Builder(
                      builder: (_) {
                        final next =
                            ManagerLeaveHelpers.nextOrOngoingAbsence(
                          absencesFor(e.id),
                        );
                        if (next == null) {
                          return Text(
                            'Ingen planlagt',
                            style: DriftProTheme.caption.copyWith(
                              color: const Color(0xFF94A3B8),
                            ),
                          );
                        }
                        return Text(
                          ManagerLeaveHelpers.nextAbsenceLabel(next),
                          style: DriftProTheme.bodySm.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      },
                    ),
                  ),
                  DataCell(
                    TextButton(
                      onPressed: () => onOpen(e),
                      style: TextButton.styleFrom(
                        foregroundColor: DriftProTheme.primaryGreen,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Detaljer'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _EmployeeMobileRow extends StatelessWidget {
  const _EmployeeMobileRow({
    required this.employee,
    required this.departmentName,
    required this.status,
    required this.quota,
    required this.next,
    required this.onOpen,
    required this.isDark,
  });

  final UserProfile employee;
  final String? departmentName;
  final ManagerLeaveTodayStatus status;
  final AbsenceQuota? quota;
  final Absence? next;
  final VoidCallback onOpen;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: isDark
                  ? DriftProTheme.dividerDark
                  : const Color(0xFFF1F5F9),
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _NameCell(
                    name: employee.fullName,
                    avatarUrl: employee.avatarUrl,
                    department: departmentName,
                  ),
                ),
                _StatusBadge(status),
              ],
            ),
            const SizedBox(height: 10),
            _VacationProgress(quota: quota),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '${quota?.vacationDaysRemaining ?? '—'} dager igjen',
                  style: DriftProTheme.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    color: DriftProTheme.primaryGreen,
                  ),
                ),
                const Spacer(),
                Flexible(
                  child: Text(
                    next == null
                        ? 'Ingen planlagt'
                        : ManagerLeaveHelpers.nextAbsenceLabel(next!),
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                    style: DriftProTheme.caption,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NameCell extends StatelessWidget {
  const _NameCell({
    required this.name,
    this.avatarUrl,
    this.department,
  });

  final String name;
  final String? avatarUrl;
  final String? department;

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty
        ? '?'
        : name
            .trim()
            .split(RegExp(r'\s+'))
            .take(2)
            .map((p) => p.isEmpty ? '' : p[0].toUpperCase())
            .join();

    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: DriftProTheme.primaryGreen.withValues(alpha: 0.14),
          backgroundImage:
              (avatarUrl != null && avatarUrl!.isNotEmpty)
                  ? NetworkImage(avatarUrl!)
                  : null,
          child: (avatarUrl == null || avatarUrl!.isEmpty)
              ? Text(
                  initials,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: DriftProTheme.primaryGreen,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: DriftProTheme.bodySm.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (department != null && department!.isNotEmpty)
                Text(
                  department!,
                  overflow: TextOverflow.ellipsis,
                  style: DriftProTheme.caption.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge(this.status);

  final ManagerLeaveTodayStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: status.color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _VacationProgress extends StatelessWidget {
  const _VacationProgress({required this.quota});

  final AbsenceQuota? quota;

  @override
  Widget build(BuildContext context) {
    final used = quota?.vacationDaysUsed ?? 0;
    final total = quota?.totalVacationDays ?? 25;
    final pct = total <= 0 ? 0.0 : (used / total).clamp(0.0, 1.0);

    return SizedBox(
      width: 160,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$used / $total dager',
            style: DriftProTheme.caption.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 7,
              backgroundColor: const Color(0xFFE2E8F0),
              color: pct >= 0.9
                  ? DriftProTheme.warning
                  : DriftProTheme.primaryGreen,
            ),
          ),
        ],
      ),
    );
  }
}
