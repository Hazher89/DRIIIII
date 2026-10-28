import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/config/driftpro_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/ticket.dart';
import '../../../models/user_profile.dart';

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

enum _TeamFilter { alle, apne, kritisk }

/// Kompakt ledervisning: KPI, prioritert, ansatte — uten ekstra faner.
class TicketTeamEmployeesHub extends StatefulWidget {
  const TicketTeamEmployeesHub({
    super.key,
    required this.teamProfiles,
    required this.teamTickets,
    required this.leaderProfile,
    required this.onTicketTap,
    required this.onEmployeeSelected,
    this.onShowAllTickets,
    this.selectedEmployeeId,
  });

  final List<UserProfile> teamProfiles;
  final List<Ticket> teamTickets;
  final UserProfile? leaderProfile;
  final void Function(Ticket ticket) onTicketTap;
  final void Function(String? employeeId) onEmployeeSelected;
  final VoidCallback? onShowAllTickets;
  final String? selectedEmployeeId;

  @override
  State<TicketTeamEmployeesHub> createState() => _TicketTeamEmployeesHubState();
}

class _TicketTeamEmployeesHubState extends State<TicketTeamEmployeesHub> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  _TeamFilter _filter = _TeamFilter.alle;

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
        case _TeamFilter.alle:
          return true;
        case _TeamFilter.apne:
          return s.openCount > 0;
        case _TeamFilter.kritisk:
          return s.criticalOpenCount > 0;
      }
    }).toList()
      ..sort((a, b) {
        final byOpen = b.openCount.compareTo(a.openCount);
        if (byOpen != 0) return byOpen;
        return a.profile.fullName.compareTo(b.profile.fullName);
      });
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final summaries = _filteredSummaries;
    final priority = _priorityTickets.take(4).toList();
    final df = DateFormat('d. MMM', 'nb_NO');

    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        DriftProClient.isMobile ? 100 : 32,
      ),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? DriftProTheme.cardDark : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color:
                  isDark ? DriftProTheme.dividerDark : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            children: [
              _kpi(
                '${_employees.length}',
                'Ansatte',
                DriftProTheme.primaryGreen,
                selected: _filter == _TeamFilter.alle,
                onTap: () => setState(() => _filter = _TeamFilter.alle),
              ),
              const SizedBox(width: 8),
              _kpi(
                '$_openCount',
                'Åpne',
                DriftProTheme.info,
                selected: _filter == _TeamFilter.apne,
                onTap: () => setState(() => _filter = _TeamFilter.apne),
              ),
              const SizedBox(width: 8),
              _kpi(
                '$_criticalCount',
                'Kritisk',
                DriftProTheme.severityCritical,
                selected: _filter == _TeamFilter.kritisk,
                onTap: () => setState(() => _filter = _TeamFilter.kritisk),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _searchCtrl,
          decoration: InputDecoration(
            hintText: 'Søk ansatt…',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            isDense: true,
            filled: true,
            fillColor: isDark ? DriftProTheme.cardDark : Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
          ),
        ),
        if (priority.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Trenger oppfølging',
                  style: DriftProTheme.labelMd
                      .copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              if (widget.onShowAllTickets != null)
                TextButton(
                  onPressed: widget.onShowAllTickets,
                  child: const Text('Se alle'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          ...priority.map((t) => _priorityRow(t, isDark, df)),
        ] else if (widget.onShowAllTickets != null) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: widget.onShowAllTickets,
              icon: const Icon(Icons.list_alt, size: 18),
              label: const Text('Se alle saker'),
            ),
          ),
        ],
        const SizedBox(height: 14),
        Text(
          'Ansatte',
          style: DriftProTheme.labelMd.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 2),
        Text(
          summaries.isEmpty
              ? 'Ingen treff'
              : 'Trykk en ansatt for å se sakene deres',
          style: DriftProTheme.caption.copyWith(color: const Color(0xFF64748B)),
        ),
        const SizedBox(height: 10),
        if (summaries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: Text('Ingen ansatte matcher', style: DriftProTheme.caption),
            ),
          )
        else
          ...summaries.map((s) => _employeeRow(s, isDark)),
      ],
    );
  }

  Widget _kpi(
    String value,
    String label,
    Color color, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: selected
            ? color.withValues(alpha: 0.16)
            : color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? color.withValues(alpha: 0.5)
                    : color.withValues(alpha: 0.15),
              ),
            ),
            child: Column(
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    color: color,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _priorityRow(Ticket t, bool isDark, DateFormat df) {
    final sevColor = switch (t.severity) {
      TicketSeverity.kritisk => DriftProTheme.severityCritical,
      TicketSeverity.hoy => DriftProTheme.severityHigh,
      TicketSeverity.middels => DriftProTheme.severityMedium,
      TicketSeverity.lav => DriftProTheme.severityLow,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => widget.onTicketTap(t),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: sevColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.report_problem_outlined, color: sevColor, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DriftProTheme.bodySm
                            .copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${t.reporterName ?? 'Ansatt'} · ${t.severity.label}'
                        '${t.createdAt != null ? ' · ${df.format(t.createdAt!)}' : ''}',
                        style: DriftProTheme.caption,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _employeeRow(TicketEmployeeSummary s, bool isDark) {
    final selected = widget.selectedEmployeeId == s.profile.id;
    final latest = s.latestOpen;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => widget.onEmployeeSelected(s.profile.id),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? DriftProTheme.primaryGreen
                    : (isDark
                        ? DriftProTheme.dividerDark
                        : const Color(0xFFE8EEF0)),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor:
                      DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                  child: Text(
                    s.profile.initials,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: DriftProTheme.primaryGreen,
                      fontSize: 12,
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DriftProTheme.bodySm
                            .copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        s.openCount > 0
                            ? '${s.openCount} åpne'
                                '${s.criticalOpenCount > 0 ? ' · ${s.criticalOpenCount} kritisk' : ''}'
                                '${latest != null ? ' · ${latest.title}' : ''}'
                            : 'Ingen åpne avvik',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DriftProTheme.caption.copyWith(
                          color: s.openCount > 0
                              ? DriftProTheme.info
                              : DriftProTheme.success,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
