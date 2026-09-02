import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/config/driftpro_client.dart';
import '../../../core/constants/leave_rules.dart';
import '../../../core/services/absence/employee_leave_stats.dart';
import '../../../core/theme/absence_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/absence.dart';
import '../../../models/user_profile.dart';
import '../../../widgets/common/team_equal_controls.dart';
import '../../../widgets/common/team_kpi_strip.dart';
import '../../departments/widgets/department_member_leave_card.dart';
import 'leave_employee_stats_panel.dart';
import 'team_leave_calendar.dart';

enum _EmployeeFilter { alle, borte, ventende, kommende }

enum _TeamLeaveView { oversikt, kalender }

/// Ryddig lederoversikt — ansatte, saldo og handling på ett sted.
class LeaveTeamEmployeesHub extends StatefulWidget {
  const LeaveTeamEmployeesHub({
    super.key,
    required this.teamProfiles,
    required this.scopedAbsences,
    required this.teamQuotas,
    required this.companySettings,
    required this.selectedYear,
    required this.departmentNames,
    required this.leaderProfile,
    required this.month,
    required this.onMonthChanged,
    required this.onRefresh,
    required this.colorForType,
    required this.iconForType,
    required this.daysFor,
    this.onAbsenceTap,
    this.onApprove,
    this.onReject,
    this.onEditQuota,
    this.excludeSelf = true,
    this.canEditQuota = false,
  });

  final List<UserProfile> teamProfiles;
  final List<Absence> scopedAbsences;
  final List<AbsenceQuota> teamQuotas;
  final CompanyLeaveSettings companySettings;
  final int selectedYear;
  final Map<String, String> departmentNames;
  final UserProfile? leaderProfile;
  final DateTime month;
  final ValueChanged<DateTime> onMonthChanged;
  final Future<void> Function() onRefresh;
  final Color Function(AbsenceType) colorForType;
  final IconData Function(AbsenceType) iconForType;
  final int Function(Absence) daysFor;
  final void Function(Absence)? onAbsenceTap;
  final void Function(Absence)? onApprove;
  final void Function(Absence)? onReject;
  final void Function(UserProfile user, AbsenceQuota? quota)? onEditQuota;
  final bool excludeSelf;
  final bool canEditQuota;

  @override
  State<LeaveTeamEmployeesHub> createState() => _LeaveTeamEmployeesHubState();
}

class _LeaveTeamEmployeesHubState extends State<LeaveTeamEmployeesHub> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  _EmployeeFilter _filter = _EmployeeFilter.alle;
  _TeamLeaveView _view = _TeamLeaveView.oversikt;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(
      () => setState(() => _search = _searchCtrl.text.trim().toLowerCase()),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<UserProfile> get _employees {
    var list = widget.teamProfiles.where((p) => !p.isPartnerPortalUser).toList();
    if (widget.excludeSelf && widget.leaderProfile != null) {
      list = list.where((p) => p.id != widget.leaderProfile!.id).toList();
    }
    list.sort((a, b) => a.fullName.compareTo(b.fullName));
    if (_search.isEmpty) return list;
    return list
        .where((p) =>
            p.fullName.toLowerCase().contains(_search) ||
            (p.employeeNumber ?? '').contains(_search))
        .toList();
  }

  List<Absence> _absencesFor(String userId) =>
      widget.scopedAbsences.where((a) => a.userId == userId).toList();

  AbsenceQuota? _quotaFor(String userId) {
    for (final q in widget.teamQuotas) {
      if (q.userId == userId) return q;
    }
    return null;
  }

  static bool _activeToday(Absence a) {
    if (a.status != AbsenceStatus.godkjent) return false;
    final now = DateTime.now();
    final t = DateTime(now.year, now.month, now.day);
    final s = DateTime(a.startDate.year, a.startDate.month, a.startDate.day);
    final e = DateTime(a.endDate.year, a.endDate.month, a.endDate.day);
    return !t.isBefore(s) && !t.isAfter(e);
  }

  static bool _upcomingWithin(Absence a, int days) {
    if (a.status != AbsenceStatus.godkjent && a.status != AbsenceStatus.ventende) {
      return false;
    }
    final now = DateTime.now();
    final t = DateTime(now.year, now.month, now.day);
    final start = DateTime(a.startDate.year, a.startDate.month, a.startDate.day);
    if (start.isBefore(t)) return false;
    return start.difference(t).inDays <= days;
  }

  List<Absence> get _pendingTeam {
    final leaderId = widget.leaderProfile?.id;
    return widget.scopedAbsences
        .where((a) =>
            a.status == AbsenceStatus.ventende &&
            (leaderId == null || a.userId != leaderId))
        .toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
  }

  int get _awayTodayCount => widget.scopedAbsences.where(_activeToday).length;

  int get _upcomingVacationCount => widget.scopedAbsences
      .where((a) =>
          a.type == AbsenceType.ferie &&
          _upcomingWithin(a, 14) &&
          a.status == AbsenceStatus.godkjent)
      .length;

  int get _pendingEmployeeCount => _employees
      .where((p) =>
          _absencesFor(p.id).any((a) => a.status == AbsenceStatus.ventende))
      .length;

  int get _awayEmployeeCount =>
      _employees.where((p) => _absencesFor(p.id).any(_activeToday)).length;

  int get _upcomingEmployeeCount => _employees
      .where((p) => _absencesFor(p.id).any((a) => _upcomingWithin(a, 21)))
      .length;

  List<UserProfile> get _filteredEmployees {
    return _employees.where((p) {
      final abs = _absencesFor(p.id);
      switch (_filter) {
        case _EmployeeFilter.alle:
          return true;
        case _EmployeeFilter.borte:
          return abs.any(_activeToday);
        case _EmployeeFilter.ventende:
          return abs.any((a) => a.status == AbsenceStatus.ventende);
        case _EmployeeFilter.kommende:
          return abs.any((a) => _upcomingWithin(a, 21));
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pending = _pendingTeam;
    final employees = _filteredEmployees;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TeamEqualSegmentBar<_TeamLeaveView>(
            value: _view,
            onChanged: (v) => setState(() => _view = v),
            items: const [
              TeamEqualSegmentItem(
                value: _TeamLeaveView.oversikt,
                label: 'Oversikt',
                icon: Icons.dashboard_outlined,
              ),
              TeamEqualSegmentItem(
                value: _TeamLeaveView.kalender,
                label: 'Kalender',
                icon: Icons.calendar_month_outlined,
              ),
            ],
          ),
        ),
        Expanded(
          child: _view == _TeamLeaveView.kalender
              ? RefreshIndicator(
                  onRefresh: widget.onRefresh,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      8,
                      16,
                      DriftProClient.isMobile ? 88 : 24,
                    ),
                    children: [
                      TeamLeaveCalendar(
                        month: widget.month,
                        absences: widget.scopedAbsences
                            .where((a) =>
                                a.status == AbsenceStatus.godkjent ||
                                a.status == AbsenceStatus.ventende)
                            .toList(),
                        employees: _employees,
                        colorForType: widget.colorForType,
                        includePending: true,
                        onMonthChanged: widget.onMonthChanged,
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: widget.onRefresh,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      8,
                      16,
                      DriftProClient.isMobile ? 88 : 24,
                    ),
                    children: [
                      TeamHubIntro(
                        title: 'Mine ansatte',
                        subtitle:
                            'Saldo ${widget.selectedYear} · egenmelding/sykt barn følger 12 mnd fra ansettelse · ${_employees.length} ansatte',
                      ),
                      const SizedBox(height: 14),
                      TeamKpiStrip(
                        children: [
                          TeamKpiTile(
                            value: '${_employees.length}',
                            label: 'Ansatte',
                            color: DriftProTheme.primaryGreen,
                            icon: Icons.groups_outlined,
                            onTap: () => setState(
                              () => _filter = _EmployeeFilter.alle,
                            ),
                          ),
                          TeamKpiTile(
                            value: '$_awayTodayCount',
                            label: 'Borte i dag',
                            color: AbsencePalette.indigo,
                            icon: Icons.event_busy_outlined,
                            onTap: () => setState(
                              () => _filter = _EmployeeFilter.borte,
                            ),
                          ),
                          TeamKpiTile(
                            value: '${pending.length}',
                            label: 'Ventende',
                            color: DriftProTheme.warning,
                            icon: Icons.pending_actions_outlined,
                            onTap: () => setState(
                              () => _filter = _EmployeeFilter.ventende,
                            ),
                          ),
                          TeamKpiTile(
                            value: '$_upcomingVacationCount',
                            label: 'Ferie snart',
                            color: DriftProTheme.absenceVacation,
                            icon: Icons.beach_access_outlined,
                            onTap: () => setState(
                              () => _filter = _EmployeeFilter.kommende,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TeamEqualSearchField(
                        controller: _searchCtrl,
                        hintText: 'Søk navn eller ansattnr…',
                      ),
                      const SizedBox(height: 10),
                      TeamEqualFilterGrid<_EmployeeFilter>(
                        value: _filter,
                        onChanged: (v) => setState(() => _filter = v),
                        items: [
                          TeamEqualFilterItem(
                            value: _EmployeeFilter.alle,
                            label: 'Alle',
                            icon: Icons.people_outline,
                            badge: '${_employees.length}',
                          ),
                          TeamEqualFilterItem(
                            value: _EmployeeFilter.borte,
                            label: 'Borte nå',
                            icon: Icons.event_busy_outlined,
                            badge: '$_awayEmployeeCount',
                            accent: AbsencePalette.indigo,
                          ),
                          TeamEqualFilterItem(
                            value: _EmployeeFilter.ventende,
                            label: 'Ventende',
                            icon: Icons.hourglass_top_rounded,
                            badge: '$_pendingEmployeeCount',
                            accent: DriftProTheme.warning,
                          ),
                          TeamEqualFilterItem(
                            value: _EmployeeFilter.kommende,
                            label: 'Kommende',
                            icon: Icons.upcoming_outlined,
                            badge: '$_upcomingEmployeeCount',
                            accent: DriftProTheme.absenceVacation,
                          ),
                        ],
                      ),
                      if (pending.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        TeamSectionHeader(
                          title: 'Trenger handling',
                          subtitle: '${pending.length} søknader venter på deg',
                        ),
                        ...pending.take(5).map((a) => _pendingCard(a, isDark)),
                        if (pending.length > 5)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '+ ${pending.length - 5} til under Inkommende',
                              style: DriftProTheme.caption,
                            ),
                          ),
                      ],
                      const SizedBox(height: 12),
                      TeamSectionHeader(
                        title: 'Ansatte',
                        subtitle: employees.isEmpty
                            ? 'Ingen treff — prøv et annet filter'
                            : '${employees.length} vist · trykk for detaljer',
                      ),
                      if (employees.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: Center(
                            child: Text(
                              'Ingen ansatte matcher filteret',
                              style: DriftProTheme.bodySm,
                            ),
                          ),
                        )
                      else
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final useTable = constraints.maxWidth >= 900;
                            if (useTable) {
                              return _EmployeesDataTable(
                                employees: employees,
                                selectedYear: widget.selectedYear,
                                company: widget.companySettings,
                                canEditQuota: widget.canEditQuota,
                                absencesFor: _absencesFor,
                                quotaFor: _quotaFor,
                                onOpen: _openEmployee,
                                onEditQuota: widget.onEditQuota,
                              );
                            }
                            return Column(
                              children: employees.map((p) {
                                final abs = _absencesFor(p.id);
                                final stats = EmployeeLeaveSnapshot.compute(
                                  employee: p,
                                  employeeAbsences: abs,
                                  quota: _quotaFor(p.id),
                                  company: widget.companySettings,
                                  referenceDate: DateTime.now(),
                                );
                                return InkWell(
                                  onTap: () => _openEmployee(p),
                                  borderRadius: BorderRadius.circular(16),
                                  child: DepartmentMemberLeaveCard(
                                    member: p,
                                    stats: stats,
                                    selectedYear: widget.selectedYear,
                                    recentAbsences: abs,
                                    onEditQuota: widget.canEditQuota &&
                                            widget.onEditQuota != null
                                        ? () => widget.onEditQuota!(
                                              p,
                                              _quotaFor(p.id),
                                            )
                                        : null,
                                  ),
                                );
                              }).toList(),
                            );
                          },
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  void _openEmployee(UserProfile p) {
    LeaveEmployeeStatsPanel.showSheet(
      context,
      employee: p,
      quota: _quotaFor(p.id),
      company: widget.companySettings,
      selectedYear: widget.selectedYear,
      employeeAbsences: _absencesFor(p.id),
      departmentNames: widget.departmentNames,
      onEditQuota: widget.canEditQuota && widget.onEditQuota != null
          ? () {
              Navigator.of(context).maybePop();
              widget.onEditQuota!(p, _quotaFor(p.id));
            }
          : null,
    );
  }

  Widget _pendingCard(Absence a, bool isDark) {
    final df = DateFormat('d. MMM', 'nb_NO');
    final days = widget.daysFor(a);
    final color = widget.colorForType(a.type);
    final canAct = widget.onApprove != null && widget.onReject != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DriftProTheme.warning.withValues(alpha: 0.35)),
        boxShadow: DriftProTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: widget.onAbsenceTap != null
                ? () => widget.onAbsenceTap!(a)
                : null,
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(widget.iconForType(a.type), color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.userName ?? 'Ansatt',
                        style: DriftProTheme.labelMd.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${a.type.label} · ${df.format(a.startDate)}–${df.format(a.endDate)} · $days d',
                        style: DriftProTheme.caption,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 20),
              ],
            ),
          ),
          if (canAct) ...[
            const SizedBox(height: 12),
            TeamEqualActionRow(
              secondaryLabel: 'Avvis',
              primaryLabel: 'Godkjenn',
              onSecondary: () => widget.onReject!(a),
              onPrimary: () => widget.onApprove!(a),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmployeesDataTable extends StatelessWidget {
  const _EmployeesDataTable({
    required this.employees,
    required this.selectedYear,
    required this.company,
    required this.canEditQuota,
    required this.absencesFor,
    required this.quotaFor,
    required this.onOpen,
    this.onEditQuota,
  });

  final List<UserProfile> employees;
  final int selectedYear;
  final CompanyLeaveSettings company;
  final bool canEditQuota;
  final List<Absence> Function(String userId) absencesFor;
  final AbsenceQuota? Function(String userId) quotaFor;
  final void Function(UserProfile) onOpen;
  final void Function(UserProfile user, AbsenceQuota? quota)? onEditQuota;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200,
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 44,
          dataRowMinHeight: 56,
          dataRowMaxHeight: 72,
          columns: const [
            DataColumn(label: Text('Ansatt')),
            DataColumn(label: Text('Ferie igjen'), numeric: true),
            DataColumn(label: Text('Egenmelding')),
            DataColumn(label: Text('Sykt barn')),
            DataColumn(label: Text('Fravær YTD')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('')),
          ],
          rows: employees.map((p) {
            final abs = absencesFor(p.id);
            final stats = EmployeeLeaveSnapshot.compute(
              employee: p,
              employeeAbsences: abs,
              quota: quotaFor(p.id),
              company: company,
              referenceDate: DateTime.now(),
            );
            final pending =
                abs.where((a) => a.status == AbsenceStatus.ventende).length;
            final onLeave = abs.any((a) {
              if (a.status != AbsenceStatus.godkjent) return false;
              final now = DateTime.now();
              final t = DateTime(now.year, now.month, now.day);
              final s = DateTime(a.startDate.year, a.startDate.month, a.startDate.day);
              final e = DateTime(a.endDate.year, a.endDate.month, a.endDate.day);
              return !t.isBefore(s) && !t.isAfter(e);
            });
            return DataRow(
              onSelectChanged: (_) => onOpen(p),
              cells: [
                DataCell(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        p.fullName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        [
                          if (p.employeeNumber != null) 'nr ${p.employeeNumber}',
                          if (p.hireDate == null) 'mangler ansettelsesdato',
                        ].join(' · '),
                        style: DriftProTheme.caption,
                      ),
                    ],
                  ),
                ),
                DataCell(Text('${stats.ferieRemaining}/${stats.ferieTotal}')),
                DataCell(
                  Text(
                    '${stats.egenDaysTotal}d · ${stats.egenTilfeller}/${stats.egenTilfellerMax}',
                  ),
                ),
                DataCell(Text('${stats.syktDays}/${stats.syktMax}')),
                DataCell(
                  Text('${stats.absenceRatePercent().round()}%'),
                ),
                DataCell(
                  Text(
                    onLeave
                        ? 'Borte'
                        : pending > 0
                            ? '$pending venter'
                            : 'OK',
                  ),
                ),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (canEditQuota && onEditQuota != null)
                        IconButton(
                          tooltip: 'Rediger feriekvote $selectedYear',
                          icon: const Icon(Icons.edit_calendar_outlined, size: 20),
                          onPressed: () => onEditQuota!(p, quotaFor(p.id)),
                        ),
                      const Icon(Icons.chevron_right, size: 18),
                    ],
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

