import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/config/driftpro_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/ticket.dart';
import '../../../models/user_profile.dart';
import '../../../widgets/common/team_equal_controls.dart';
import '../../../widgets/common/team_kpi_strip.dart';

enum TicketTeamViewMode { oversikt, liste }

enum _TicketTeamFilter { alle, apne, kritisk, underBeh }

class TicketEmployeeSummary {
  const TicketEmployeeSummary({
    required this.profile,
    required this.tickets,
  });

  final UserProfile profile;
  final List<Ticket> tickets;

  int get openCount => tickets.where((t) => t.isOpen).length;

  int get criticalOpenCount => tickets
      .where((t) => t.isOpen && t.severity == TicketSeverity.kritisk)
      .length;

  int get inProgressCount =>
      tickets.where((t) => t.status == TicketStatus.underBehandling).length;

  Ticket? get latestOpen {
    final open = tickets.where((t) => t.isOpen).toList();
    if (open.isEmpty) return null;
    open.sort((a, b) {
      final ac = a.createdAt;
      final bc = b.createdAt;
      if (ac == null && bc == null) return 0;
      if (ac == null) return 1;
      if (bc == null) return -1;
      return bc.compareTo(ac);
    });
    return open.first;
  }
}

/// Lederoversikt for avvik per ansatt.
class TicketTeamEmployeesHub extends StatefulWidget {
  const TicketTeamEmployeesHub({
    super.key,
    required this.teamProfiles,
    required this.teamTickets,
    required this.leaderProfile,
    required this.onTicketTap,
    required this.onEmployeeSelected,
    this.selectedEmployeeId,
    this.onViewChanged,
    this.initialView = TicketTeamViewMode.oversikt,
    this.listChild,
  });

  final List<UserProfile> teamProfiles;
  final List<Ticket> teamTickets;
  final UserProfile? leaderProfile;
  final void Function(Ticket ticket) onTicketTap;
  final void Function(String? employeeId) onEmployeeSelected;
  final String? selectedEmployeeId;
  final ValueChanged<TicketTeamViewMode>? onViewChanged;
  final TicketTeamViewMode initialView;
  final Widget? listChild;

  @override
  State<TicketTeamEmployeesHub> createState() => _TicketTeamEmployeesHubState();
}

class _TicketTeamEmployeesHubState extends State<TicketTeamEmployeesHub> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  _TicketTeamFilter _filter = _TicketTeamFilter.alle;
  TicketTeamViewMode _view = TicketTeamViewMode.oversikt;

  @override
  void initState() {
    super.initState();
    _view = widget.initialView;
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
    final leaderId = widget.leaderProfile?.id;
    if (leaderId != null) {
      list = list.where((p) => p.id != leaderId).toList();
    }
    list.sort((a, b) => a.fullName.compareTo(b.fullName));
    if (_search.isEmpty) return list;
    return list
        .where((p) =>
            p.fullName.toLowerCase().contains(_search) ||
            (p.employeeNumber ?? '').contains(_search))
        .toList();
  }

  List<TicketEmployeeSummary> get _summaries {
    final byUser = <String, List<Ticket>>{};
    for (final t in widget.teamTickets) {
      byUser.putIfAbsent(t.reportedBy, () => []).add(t);
    }

    final out = <TicketEmployeeSummary>[];
    for (final p in _employees) {
      final tickets = [...(byUser[p.id] ?? const <Ticket>[])];
      tickets.sort((a, b) {
        final ac = a.createdAt;
        final bc = b.createdAt;
        if (ac == null && bc == null) return 0;
        if (ac == null) return 1;
        if (bc == null) return -1;
        return bc.compareTo(ac);
      });
      out.add(TicketEmployeeSummary(profile: p, tickets: tickets));
    }
    return out;
  }

  List<TicketEmployeeSummary> get _filteredSummaries {
    return _summaries.where((s) {
      switch (_filter) {
        case _TicketTeamFilter.alle:
          return true;
        case _TicketTeamFilter.apne:
          return s.openCount > 0;
        case _TicketTeamFilter.kritisk:
          return s.criticalOpenCount > 0;
        case _TicketTeamFilter.underBeh:
          return s.inProgressCount > 0;
      }
    }).toList();
  }

  List<Ticket> get _priorityTickets {
    return widget.teamTickets.where((t) => t.isOpen).toList()
      ..sort((a, b) {
        final sa = a.severity == TicketSeverity.kritisk ? 0 : 1;
        final sb = b.severity == TicketSeverity.kritisk ? 0 : 1;
        if (sa != sb) return sa.compareTo(sb);
        final ac = a.createdAt;
        final bc = b.createdAt;
        if (ac == null && bc == null) return 0;
        if (ac == null) return 1;
        if (bc == null) return -1;
        return bc.compareTo(ac);
      });
  }

  int get _openCount => widget.teamTickets.where((t) => t.isOpen).length;

  int get _criticalCount => widget.teamTickets
      .where((t) => t.isOpen && t.severity == TicketSeverity.kritisk)
      .length;

  int get _inProgressCount => widget.teamTickets
      .where((t) => t.status == TicketStatus.underBehandling)
      .length;

  int get _employeesWithOpen =>
      _summaries.where((s) => s.openCount > 0).length;

  int get _employeesWithCritical =>
      _summaries.where((s) => s.criticalOpenCount > 0).length;

  int get _employeesInProgress =>
      _summaries.where((s) => s.inProgressCount > 0).length;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final summaries = _filteredSummaries;
    final priority = _priorityTickets.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TeamEqualSegmentBar<TicketTeamViewMode>(
            value: _view,
            onChanged: (v) {
              setState(() => _view = v);
              widget.onViewChanged?.call(v);
            },
            items: const [
              TeamEqualSegmentItem(
                value: TicketTeamViewMode.oversikt,
                label: 'Oversikt',
                icon: Icons.dashboard_outlined,
              ),
              TeamEqualSegmentItem(
                value: TicketTeamViewMode.liste,
                label: 'Liste',
                icon: Icons.list_alt,
              ),
            ],
          ),
        ),
        if (_view == TicketTeamViewMode.oversikt)
          Expanded(child: _buildOverview(isDark, summaries, priority))
        else if (widget.listChild != null)
          Expanded(child: widget.listChild!)
        else
          Expanded(
            child: Center(
              child: Text('Ingen liste', style: DriftProTheme.bodySm),
            ),
          ),
      ],
    );
  }

  Widget _buildOverview(
    bool isDark,
    List<TicketEmployeeSummary> summaries,
    List<Ticket> priority,
  ) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        DriftProClient.isMobile ? 8 : 24,
      ),
      children: [
        TeamHubIntro(
          title: 'Mine ansatte',
          subtitle:
              'Følg opp avvik og status for ${_employees.length} ansatte i avdelingen',
        ),
        const SizedBox(height: 14),
        TeamKpiStrip(
          children: [
            TeamKpiTile(
              value: '${_employees.length}',
              label: 'Ansatte',
              color: DriftProTheme.primaryGreen,
              icon: Icons.groups_outlined,
              onTap: () => setState(() => _filter = _TicketTeamFilter.alle),
            ),
            TeamKpiTile(
              value: '$_openCount',
              label: 'Åpne',
              color: DriftProTheme.info,
              icon: Icons.flag_outlined,
              onTap: () => setState(() => _filter = _TicketTeamFilter.apne),
            ),
            TeamKpiTile(
              value: '$_criticalCount',
              label: 'Kritisk',
              color: DriftProTheme.severityCritical,
              icon: Icons.warning_amber_rounded,
              onTap: () => setState(() => _filter = _TicketTeamFilter.kritisk),
            ),
            TeamKpiTile(
              value: '$_inProgressCount',
              label: 'Under beh.',
              color: DriftProTheme.warning,
              icon: Icons.hourglass_top_rounded,
              onTap: () =>
                  setState(() => _filter = _TicketTeamFilter.underBeh),
            ),
          ],
        ),
        const SizedBox(height: 14),
        TeamEqualSearchField(
          controller: _searchCtrl,
          hintText: 'Søk ansatt…',
        ),
        const SizedBox(height: 10),
        TeamEqualFilterGrid<_TicketTeamFilter>(
          value: _filter,
          onChanged: (v) => setState(() => _filter = v),
          items: [
            TeamEqualFilterItem(
              value: _TicketTeamFilter.alle,
              label: 'Alle',
              icon: Icons.people_outline,
              badge: '${_employees.length}',
            ),
            TeamEqualFilterItem(
              value: _TicketTeamFilter.apne,
              label: 'Har åpne',
              icon: Icons.flag_outlined,
              badge: '$_employeesWithOpen',
              accent: DriftProTheme.info,
            ),
            TeamEqualFilterItem(
              value: _TicketTeamFilter.kritisk,
              label: 'Kritisk',
              icon: Icons.warning_amber_rounded,
              badge: '$_employeesWithCritical',
              accent: DriftProTheme.severityCritical,
            ),
            TeamEqualFilterItem(
              value: _TicketTeamFilter.underBeh,
              label: 'Under beh.',
              icon: Icons.hourglass_top_rounded,
              badge: '$_employeesInProgress',
              accent: DriftProTheme.warning,
            ),
          ],
        ),
        if (priority.isNotEmpty) ...[
          const SizedBox(height: 18),
          TeamSectionHeader(
            title: 'Prioritert nå',
            subtitle: 'Kritiske og nylige åpne avvik',
          ),
          ...priority.map((t) => _priorityTicketRow(t, isDark)),
        ],
        const SizedBox(height: 12),
        TeamSectionHeader(
          title: 'Per ansatt',
          subtitle: summaries.isEmpty
              ? 'Ingen treff'
              : '${summaries.length} vist · trykk for å åpne listen',
        ),
        if (summaries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'Ingen ansatte matcher filteret',
                style: DriftProTheme.bodySm,
              ),
            ),
          )
        else
          ...summaries.map((s) => _employeeCard(s, isDark)),
      ],
    );
  }

  Widget _priorityTicketRow(Ticket t, bool isDark) {
    final df = DateFormat('d. MMM', 'nb_NO');
    final sevColor = switch (t.severity) {
      TicketSeverity.kritisk => DriftProTheme.severityCritical,
      TicketSeverity.hoy => DriftProTheme.severityHigh,
      TicketSeverity.middels => DriftProTheme.severityMedium,
      TicketSeverity.lav => DriftProTheme.severityLow,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => widget.onTicketTap(t),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: sevColor.withValues(alpha: 0.28),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: sevColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.report_problem_outlined,
                    color: sevColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DriftProTheme.labelMd.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${t.reporterName ?? 'Ansatt'} · ${t.severity.label} · ${t.status.label}'
                        '${t.createdAt != null ? ' · ${df.format(t.createdAt!)}' : ''}',
                        style: DriftProTheme.caption,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _employeeCard(TicketEmployeeSummary s, bool isDark) {
    final selected = widget.selectedEmployeeId == s.profile.id;
    final latest = s.latestOpen;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected
              ? DriftProTheme.primaryGreen
              : (isDark ? DriftProTheme.dividerDark : Colors.grey.shade200),
          width: selected ? 1.5 : 1,
        ),
        boxShadow: DriftProTheme.cardShadow,
      ),
      child: InkWell(
        onTap: () {
          widget.onEmployeeSelected(selected ? null : s.profile.id);
          setState(() => _view = TicketTeamViewMode.liste);
          widget.onViewChanged?.call(TicketTeamViewMode.liste);
        },
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor:
                    DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                child: Text(
                  s.profile.initials,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: DriftProTheme.primaryGreen,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.profile.fullName,
                      style: DriftProTheme.labelLg.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _statPill(
                            '${s.openCount} åpne',
                            DriftProTheme.info,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _statPill(
                            s.criticalOpenCount > 0
                                ? '${s.criticalOpenCount} kritisk'
                                : '${s.tickets.length} totalt',
                            s.criticalOpenCount > 0
                                ? DriftProTheme.severityCritical
                                : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    if (latest != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        latest.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DriftProTheme.caption,
                      ),
                    ] else
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Ingen åpne avvik',
                          style: DriftProTheme.caption.copyWith(
                            color: DriftProTheme.success,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected ? Icons.check_circle : Icons.chevron_right,
                color: selected
                    ? DriftProTheme.primaryGreen
                    : (isDark ? Colors.white38 : Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statPill(String label, Color color) {
    return Container(
      height: 28,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
