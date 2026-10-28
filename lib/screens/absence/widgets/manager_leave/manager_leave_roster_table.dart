import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/leave_rules.dart';
import '../../../../core/services/absence/employee_leave_stats.dart';
import '../../../../core/services/absence/leave_period_usage_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/leave_period_window.dart';
import '../../../../models/absence.dart';
import '../../../../models/user_profile.dart';
import '../leave_period_scope.dart';
import 'manager_leave_helpers.dart';

enum _RosterFilter { alle, borte, ferieLav }

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
    this.scope,
    this.company = const CompanyLeaveSettings(),
  });

  final List<UserProfile> employees;
  final List<Absence> absences;
  final List<AbsenceQuota> quotas;
  final Map<String, String> departmentNames;
  final int year;
  final LeavePeriodScope? scope;
  final CompanyLeaveSettings company;
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
  _RosterFilter _filter = _RosterFilter.alle;

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

  LeavePeriodScope get _scope =>
      widget.scope ?? LeavePeriodScope.year(widget.year);

  EmployeeLeaveSnapshot _statsFor(UserProfile e) {
    final abs = _absencesFor(e.id);
    final usage = LeavePeriodUsageService.computeForWindow(
      absences: abs,
      window: LeavePeriodWindow(
        periodStart: _scope.rangeStart,
        periodEnd: _scope.rangeEnd,
      ),
    );
    return EmployeeLeaveSnapshot.compute(
      employee: e,
      employeeAbsences: abs,
      quota: _quota(e.id),
      company: widget.company,
      referenceDate: _scope.referenceDate,
      periodUsageOverride: usage,
    );
  }

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
    final list = widget.employees.where((e) {
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
      final quota = _quota(e.id);
      switch (_filter) {
        case _RosterFilter.alle:
          return true;
        case _RosterFilter.borte:
          return status != ManagerLeaveTodayStatus.paJobb;
        case _RosterFilter.ferieLav:
          return (quota?.vacationDaysRemaining ?? 25) <= 5;
      }
    }).toList();

    list.sort((a, b) {
      final qa = _quota(a.id)?.vacationDaysRemaining ?? 999;
      final qb = _quota(b.id)?.vacationDaysRemaining ?? 999;
      final byLeft = qa.compareTo(qb);
      if (byLeft != 0) return byLeft;
      return a.fullName.compareTo(b.fullName);
    });
    return list;
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
                        '${_scope.shortLabel} · ferie, egenmelding, sykt barn og sykmelding',
                        style: DriftProTheme.caption.copyWith(
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.onYearChanged != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : const Color(0xFFF1F5F2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: DropdownButtonHideUnderline(
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
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Column(
              children: [
                TextField(
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
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
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
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: InputDecorator(
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
                                        ? 'Alle'
                                        : (widget.departmentNames[id] ??
                                            'Uten navn'),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (v) =>
                                setState(() => _departmentId = v),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        alignment: WrapAlignment.end,
                        children: [
                          _FilterChip(
                            label: 'Alle',
                            selected: _filter == _RosterFilter.alle,
                            onTap: () =>
                                setState(() => _filter = _RosterFilter.alle),
                          ),
                          _FilterChip(
                            label: 'Borte nå',
                            selected: _filter == _RosterFilter.borte,
                            onTap: () =>
                                setState(() => _filter = _RosterFilter.borte),
                          ),
                          _FilterChip(
                            label: '≤ 5 d igjen',
                            selected: _filter == _RosterFilter.ferieLav,
                            onTap: () => setState(
                              () => _filter = _RosterFilter.ferieLav,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
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
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 6),
              child: Text(
                '${rows.length} ansatte',
                style: DriftProTheme.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF94A3B8),
                ),
              ),
            ),
            for (final e in rows)
              _EmployeeRow(
                employee: e,
                departmentName: e.departmentId == null
                    ? null
                    : widget.departmentNames[e.departmentId!],
                quota: _quota(e.id),
                stats: _statsFor(e),
                year: widget.year,
                status: ManagerLeaveHelpers.todayStatusFor(_absencesFor(e.id)),
                next: ManagerLeaveHelpers.nextOrOngoingAbsence(
                  _absencesFor(e.id),
                ),
                onOpen: () => widget.onOpenEmployee(e),
                isDark: isDark,
              ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? DriftProTheme.primaryGreen.withValues(alpha: 0.14)
          : const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? DriftProTheme.primaryGreen.withValues(alpha: 0.45)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: selected
                  ? DriftProTheme.primaryGreen
                  : const Color(0xFF64748B),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmployeeRow extends StatelessWidget {
  const _EmployeeRow({
    required this.employee,
    required this.departmentName,
    required this.quota,
    required this.stats,
    required this.year,
    required this.status,
    required this.next,
    required this.onOpen,
    required this.isDark,
  });

  final UserProfile employee;
  final String? departmentName;
  final AbsenceQuota? quota;
  final EmployeeLeaveSnapshot stats;
  final int year;
  final ManagerLeaveTodayStatus status;
  final Absence? next;
  final VoidCallback onOpen;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final used = quota?.vacationDaysUsed ?? stats.ferieUsed;
    final total = quota?.totalVacationDays ?? stats.ferieTotal;
    final left = quota?.vacationDaysRemaining ?? stats.ferieRemaining;
    final pct = total <= 0 ? 0.0 : (used / total).clamp(0.0, 1.0);
    final low = left <= 5;
    final away = status != ManagerLeaveTodayStatus.paJobb;
    final df = DateFormat('d. MMM', 'nb_NO');
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.03)
                : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: away
                  ? status.color.withValues(alpha: 0.35)
                  : (isDark
                      ? DriftProTheme.dividerDark
                      : const Color(0xFFEEF2F6)),
            ),
          ),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: _identity(away)),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 150,
                      child: _daysBlock(
                        used: used,
                        left: left,
                        total: total,
                        pct: pct,
                        low: low,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(flex: 4, child: _absenceStats()),
                    const SizedBox(width: 12),
                    Expanded(flex: 3, child: _nextBlock(df)),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: DriftProTheme.primaryGreen.withValues(alpha: 0.55),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _identity(away),
                    const SizedBox(height: 12),
                    _daysBlock(
                      used: used,
                      left: left,
                      total: total,
                      pct: pct,
                      low: low,
                    ),
                    const SizedBox(height: 10),
                    _absenceStats(),
                    const SizedBox(height: 10),
                    _nextBlock(df),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _absenceStats() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _StatChip(
          label: 'Egen',
          value: '${stats.egenDaysTotal} d · ${stats.egenTilfeller} tilf.',
          color: DriftProTheme.absenceSickSelf,
          emphasize: stats.egenDaysTotal > 0,
        ),
        _StatChip(
          label: 'Sykt barn',
          value: '${stats.syktDays} d',
          color: DriftProTheme.absenceSickChild,
          emphasize: stats.syktDays > 0,
        ),
        _StatChip(
          label: 'Sykm.',
          value: '${stats.sykmeldingDays} d',
          color: DriftProTheme.absenceSickNote,
          emphasize: stats.sykmeldingDays > 0,
        ),
      ],
    );
  }

  Widget _identity(bool away) {
    final initials = employee.fullName.trim().isEmpty
        ? '?'
        : employee.fullName
            .trim()
            .split(RegExp(r'\s+'))
            .take(2)
            .map((p) => p.isEmpty ? '' : p[0].toUpperCase())
            .join();

    return Row(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: DriftProTheme.primaryGreen.withValues(alpha: 0.14),
          backgroundImage:
              (employee.avatarUrl != null && employee.avatarUrl!.isNotEmpty)
                  ? NetworkImage(employee.avatarUrl!)
                  : null,
          child: (employee.avatarUrl == null || employee.avatarUrl!.isEmpty)
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
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                employee.fullName,
                overflow: TextOverflow.ellipsis,
                style: DriftProTheme.bodySm.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                [
                  if (departmentName != null && departmentName!.isNotEmpty)
                    departmentName!,
                  if (away) status.label,
                ].join(' · '),
                overflow: TextOverflow.ellipsis,
                style: DriftProTheme.caption.copyWith(
                  color: away ? status.color : const Color(0xFF64748B),
                  fontWeight: away ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _daysBlock({
    required int used,
    required int left,
    required int total,
    required double pct,
    required bool low,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _DayStat(label: 'Brukt', value: '$used', muted: true),
            const SizedBox(width: 10),
            _DayStat(
              label: 'Igjen',
              value: '$left',
              accent: low ? DriftProTheme.warning : DriftProTheme.primaryGreen,
            ),
            const SizedBox(width: 10),
            Text(
              '/ $total d',
              style: DriftProTheme.caption.copyWith(
                color: const Color(0xFF94A3B8),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 6,
            backgroundColor: const Color(0xFFE2E8F0),
            color: low ? DriftProTheme.warning : DriftProTheme.primaryGreen,
          ),
        ),
      ],
    );
  }

  Widget _nextBlock(DateFormat df) {
    if (next == null) {
      return Text(
        'Ingen planlagt fravær',
        style: DriftProTheme.caption.copyWith(
          color: const Color(0xFF94A3B8),
        ),
      );
    }
    final days = ManagerLeaveHelpers.daysFor(next!);
    final pending = next!.status == AbsenceStatus.ventende;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${next!.type.label} · $days dager${pending ? ' (venter)' : ''}',
          style: DriftProTheme.bodySm.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(
          '${df.format(next!.startDate)} – ${df.format(next!.endDate)}',
          style: DriftProTheme.caption.copyWith(
            color: const Color(0xFF64748B),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _DayStat extends StatelessWidget {
  const _DayStat({
    required this.label,
    required this.value,
    this.accent,
    this.muted = false,
  });

  final String label;
  final String value;
  final Color? accent;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: DriftProTheme.caption.copyWith(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF94A3B8),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            height: 1.1,
            color: muted
                ? const Color(0xFF475569)
                : (accent ?? DriftProTheme.primaryGreen),
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final Color color;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: emphasize ? 0.14 : 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withValues(alpha: emphasize ? 0.4 : 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: color.withValues(alpha: 0.9),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: emphasize ? color : const Color(0xFF475569),
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }
}
