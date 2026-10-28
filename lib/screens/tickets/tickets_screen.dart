import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/case_trace/case_trace.dart';
import '../../core/case_trace/case_trace_chip.dart';
import '../../core/config/driftpro_client.dart';
import '../../core/layout/mobile_layout.dart';
import '../../core/layout/mobile_shell_scaffold.dart';
import '../../core/constants/app_icons.dart';
import '../../core/constants/app_strings.dart';
import '../../core/permissions/access_keys.dart';
import '../../core/permissions/permission_gate.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/ticket_service.dart';
import '../../core/services/org/department_leader_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../models/ticket.dart';
import '../../models/user_profile.dart';
import '../../widgets/common/team_scope_segment.dart';
import '../../widgets/driftpro_loading_indicator.dart';
import 'new_ticket_screen.dart';
import 'ticket_admin_dashboard_screen.dart';
import 'ticket_detail_screen.dart';
import 'widgets/ticket_team_employees_hub.dart';

/// Avvik — én ryddig arbeidsflate: scope, KPI-filter, søk og liste.
class TicketsScreen extends StatefulWidget {
  const TicketsScreen({super.key});

  @override
  State<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends State<TicketsScreen> {
  TicketStatus? _filterStatus;
  bool _showDeleted = false;
  final _searchController = TextEditingController();

  List<Ticket> _tickets = const [];
  bool _isLoading = true;
  String? _error;
  UserProfile? _profile;
  bool _canManageTeam = false;
  TeamDataScope _dataScope = TeamDataScope.mine;
  List<UserProfile> _teamProfiles = const [];
  String? _teamEmployeeFilter;
  /// false = ansatt-oversikt, true = saksliste (team).
  bool _teamShowList = false;

  @override
  void initState() {
    super.initState();
    _loadProfileAndTickets();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesSearch(Ticket t) {
    return CaseTrace.matchesQuery(
          query: _searchController.text,
          traceRef: t.displayTraceRef,
          id: t.id,
          title: t.title,
          ticketNumber: t.ticketNumber,
        ) ||
        t.description
            .toLowerCase()
            .contains(_searchController.text.trim().toLowerCase()) ||
        (t.reporterName ?? '')
            .toLowerCase()
            .contains(_searchController.text.trim().toLowerCase()) ||
        (t.assigneeName ?? '')
            .toLowerCase()
            .contains(_searchController.text.trim().toLowerCase()) ||
        (t.category ?? '')
            .toLowerCase()
            .contains(_searchController.text.trim().toLowerCase());
  }

  Future<void> _loadProfileAndTickets() async {
    final p = await SupabaseService.fetchEffectiveUserProfile();
    final canManage =
        p != null ? await DepartmentLeaderScope.canManageTeam(p) : false;
    if (mounted) {
      setState(() {
        _profile = p;
        _canManageTeam = canManage;
      });
    }
    await Future.wait([
      _loadTickets(),
      _loadTeamProfiles(canManage),
    ]);
  }

  Future<void> _loadTeamProfiles(bool canManage) async {
    final profile = _profile;
    if (profile == null || profile.companyId == null || !canManage) {
      if (mounted) setState(() => _teamProfiles = const []);
      return;
    }
    final deptIds = await DepartmentLeaderScope.managedDepartmentIds(profile);
    final all = await SupabaseService.fetchProfiles(
      companyId: profile.companyId,
    );
    final scoped = all
        .where((p) =>
            p.departmentId != null &&
            deptIds.contains(p.departmentId) &&
            !p.isPartnerPortalUser)
        .toList();
    if (mounted) setState(() => _teamProfiles = scoped);
  }

  List<Ticket> get _teamTickets {
    final profile = _profile;
    if (profile == null) return const [];
    return _tickets.where((t) => t.reportedBy != profile.id).toList();
  }

  List<Ticket> get _scopedVisibleTickets {
    final profile = _profile;
    if (profile == null) return _tickets;
    if (!_canManageTeam || _dataScope == TeamDataScope.mine) {
      return _tickets
          .where((t) =>
              t.reportedBy == profile.id || t.assignedTo == profile.id)
          .toList();
    }
    var list = _teamTickets;
    if (_teamEmployeeFilter != null) {
      list = list.where((t) => t.reportedBy == _teamEmployeeFilter).toList();
    }
    return list;
  }

  List<Ticket> get _filteredTickets => _scopedVisibleTickets
      .where((t) => _showDeleted ? t.isDeleted : !t.isDeleted)
      .where((t) => _filterStatus == null || t.status == _filterStatus)
      .where(_matchesSearch)
      .toList();

  void _openTicketDetail(Ticket t) {
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => TicketDetailScreen(
          ticket: t,
          coordinatorProfile: _profile,
        ),
      ),
    )
        .then((_) => _loadTickets());
  }

  Future<void> _loadTickets() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final profile = _profile;
      if (profile == null) {
        throw StateError('Fant ikke brukerprofil.');
      }
      final scoped = _showDeleted && profile.isAdmin
          ? await SupabaseService.fetchScopedTicketsIncludingDeleted(
              profile: profile)
          : await SupabaseService.fetchScopedTickets(profile: profile);
      setState(() => _tickets = scoped);
    } catch (e) {
      setState(() => _error = 'Kunne ikke hente avvik fra Supabase.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openNewTicket() {
    Navigator.of(context, rootNavigator: true)
        .push<bool>(
      MaterialPageRoute(builder: (_) => const NewTicketScreen()),
    )
        .then((created) {
      if (created == true) _loadTickets();
    });
  }

  void _openControlCenter() {
    Navigator.of(context)
        .push(
      MaterialPageRoute(builder: (_) => const TicketAdminDashboardScreen()),
    )
        .then((_) => _loadTickets());
  }

  void _setScope(TeamDataScope s) {
    setState(() {
      _dataScope = s;
      _teamEmployeeFilter = null;
      _teamShowList = false;
      _filterStatus = null;
      _searchController.clear();
    });
  }

  Color _sevColor(TicketSeverity s) => switch (s) {
        TicketSeverity.lav => DriftProTheme.severityLow,
        TicketSeverity.middels => DriftProTheme.severityMedium,
        TicketSeverity.hoy => DriftProTheme.severityHigh,
        TicketSeverity.kritisk => DriftProTheme.severityCritical,
      };

  Color _statColor(TicketStatus s) => switch (s) {
        TicketStatus.aapen => DriftProTheme.info,
        TicketStatus.underBehandling => DriftProTheme.warning,
        TicketStatus.tiltakUtfort => DriftProTheme.success,
        TicketStatus.lukket => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final stats = TicketDashboardStats.fromTickets(_scopedVisibleTickets);
    final coord = _canManageTeam || _profile?.isAdmin == true;
    final showTeamHub =
        _canManageTeam && _dataScope == TeamDataScope.team && !_teamShowList;

    return PermissionGuard(
      profile: _profile,
      accessKey: AccessKeys.avvik,
      child: MobileShellScaffold(
        title: AppStrings.navTickets,
        hideMobileTitleBar: DriftProClient.isMobile,
        backgroundColor:
            isDark ? DriftProTheme.surfaceDark : const Color(0xFFF4F7F5),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _openNewTicket,
          icon: const Icon(AppIcons.add),
          label: const Text(AppStrings.reportDeviation),
        ),
        body: showTeamHub
            ? _buildTeamOverview(isDark, coord)
            : _buildTicketWorkspace(isDark, stats, coord),
      ),
    );
  }

  Widget _buildTeamOverview(bool isDark, bool coord) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TopBar(
          canManageTeam: _canManageTeam,
          scope: _dataScope,
          onScopeChanged: _setScope,
          showControlCenter: coord && !DriftProClient.isMobile,
          onControlCenter: _openControlCenter,
          onRefresh: _loadProfileAndTickets,
        ),
        Expanded(
          child: _isLoading
              ? const DriftProLoadingCenter()
              : _error != null
                  ? Center(child: Text(_error!, textAlign: TextAlign.center))
                  : TicketTeamEmployeesHub(
                      teamProfiles: _teamProfiles,
                      teamTickets: _teamTickets,
                      leaderProfile: _profile,
                      selectedEmployeeId: _teamEmployeeFilter,
                      onTicketTap: _openTicketDetail,
                      onEmployeeSelected: (id) {
                        setState(() {
                          _teamEmployeeFilter = id;
                          _teamShowList = true;
                        });
                      },
                      onShowAllTickets: () {
                        setState(() {
                          _teamEmployeeFilter = null;
                          _teamShowList = true;
                        });
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildTicketWorkspace(
    bool isDark,
    TicketDashboardStats stats,
    bool coord,
  ) {
    final filtered = _filteredTickets;
    final df = DateFormat('d. MMM', 'nb_NO');

    return RefreshIndicator(
      onRefresh: _loadProfileAndTickets,
      color: DriftProTheme.primaryGreen,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          SliverToBoxAdapter(
            child: _TopBar(
              canManageTeam: _canManageTeam,
              scope: _dataScope,
              onScopeChanged: _setScope,
              showControlCenter: coord && !DriftProClient.isMobile,
              onControlCenter: _openControlCenter,
              onRefresh: _loadProfileAndTickets,
              teamListActive: _canManageTeam &&
                  _dataScope == TeamDataScope.team &&
                  _teamShowList,
              onBackToTeamOverview: () => setState(() {
                _teamShowList = false;
                _teamEmployeeFilter = null;
              }),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: _KpiFilterStrip(
                stats: stats,
                filterStatus: _filterStatus,
                onSelect: (s) => setState(() {
                  _filterStatus = _filterStatus == s ? null : s;
                }),
                onClear: () => setState(() => _filterStatus = null),
                isDark: isDark,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: _SearchBar(
                controller: _searchController,
                onChanged: () => setState(() {}),
                showDeleted: _showDeleted,
                canShowDeleted: _profile?.isAdmin == true,
                onToggleDeleted: () {
                  setState(() => _showDeleted = !_showDeleted);
                  _loadTickets();
                },
              ),
            ),
          ),
          if (_teamEmployeeFilter != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _EmployeeFilterBanner(
                  name: _teamProfiles
                          .where((p) => p.id == _teamEmployeeFilter)
                          .map((p) => p.fullName)
                          .firstOrNull ??
                      'Ansatt',
                  onClear: () => setState(() => _teamEmployeeFilter = null),
                ),
              ),
            ),
          if (_isLoading)
            const SliverFillRemaining(child: DriftProLoadingCenter())
          else if (_error != null)
            SliverFillRemaining(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, textAlign: TextAlign.center),
                ),
              ),
            )
          else if (filtered.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(
                hasSearch: _searchController.text.trim().isNotEmpty,
                onNew: _openNewTicket,
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                16,
                0,
                16,
                100 + MobileLayout.shellBottomInset(context),
              ),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          '${filtered.length} ${filtered.length == 1 ? 'sak' : 'saker'}'
                          '${_filterStatus != null ? ' · ${_filterStatus!.label}' : ''}',
                          style: DriftProTheme.caption.copyWith(
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      );
                    }
                    final t = filtered[i - 1];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _TicketRow(
                        ticket: t,
                        isDark: isDark,
                        dateLabel: t.createdAt != null
                            ? df.format(t.createdAt!)
                            : null,
                        sevColor: _sevColor(t.severity),
                        statusColor: _statColor(t.status),
                        onTap: () => _openTicketDetail(t),
                      ),
                    );
                  },
                  childCount: filtered.length + 1,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Top bar ───────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.canManageTeam,
    required this.scope,
    required this.onScopeChanged,
    required this.showControlCenter,
    required this.onControlCenter,
    required this.onRefresh,
    this.teamListActive = false,
    this.onBackToTeamOverview,
  });

  final bool canManageTeam;
  final TeamDataScope scope;
  final ValueChanged<TeamDataScope> onScopeChanged;
  final bool showControlCenter;
  final VoidCallback onControlCenter;
  final Future<void> Function() onRefresh;
  final bool teamListActive;
  final VoidCallback? onBackToTeamOverview;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (teamListActive && onBackToTeamOverview != null) ...[
                IconButton(
                  tooltip: 'Tilbake til oversikt',
                  onPressed: onBackToTeamOverview,
                  icon: const Icon(Icons.arrow_back_rounded),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      teamListActive ? 'Saker hos ansatte' : 'Avvik',
                      style: DriftProTheme.headingSm.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      teamListActive
                          ? 'Liste over meldte saker'
                          : scope == TeamDataScope.team
                              ? 'Følg opp teamets saker'
                              : 'Dine saker og tildelte',
                      style: DriftProTheme.caption.copyWith(
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Oppdater',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
              if (showControlCenter)
                IconButton(
                  tooltip: 'Kontrollsenter',
                  onPressed: onControlCenter,
                  icon: const Icon(Icons.analytics_outlined),
                ),
            ],
          ),
          if (canManageTeam) ...[
            const SizedBox(height: 10),
            _CompactScope(
              scope: scope,
              onChanged: onScopeChanged,
            ),
          ],
        ],
      ),
    );
  }
}

class _CompactScope extends StatelessWidget {
  const _CompactScope({required this.scope, required this.onChanged});
  final TeamDataScope scope;
  final ValueChanged<TeamDataScope> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFE8EEE9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _seg(
            label: 'Meg',
            icon: Icons.person_outline,
            selected: scope == TeamDataScope.mine,
            onTap: () => onChanged(TeamDataScope.mine),
          ),
          _seg(
            label: 'Team',
            icon: Icons.groups_outlined,
            selected: scope == TeamDataScope.team,
            onTap: () => onChanged(TeamDataScope.team),
          ),
        ],
      ),
    );
  }

  Widget _seg({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        elevation: selected ? 1 : 0,
        shadowColor: Colors.black26,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected
                      ? DriftProTheme.primaryGreen
                      : const Color(0xFF64748B),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: selected
                        ? DriftProTheme.primaryGreen
                        : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── KPI as filters ────────────────────────────────────────────────────────────

class _KpiFilterStrip extends StatelessWidget {
  const _KpiFilterStrip({
    required this.stats,
    required this.filterStatus,
    required this.onSelect,
    required this.onClear,
    required this.isDark,
  });

  final TicketDashboardStats stats;
  final TicketStatus? filterStatus;
  final ValueChanged<TicketStatus> onSelect;
  final VoidCallback onClear;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final items = <({TicketStatus? status, String label, String value, Color color, IconData icon})>[
      (
        status: null,
        label: 'Alle',
        value: '${stats.total}',
        color: DriftProTheme.primaryGreen,
        icon: Icons.inbox_outlined,
      ),
      (
        status: TicketStatus.aapen,
        label: 'Åpne',
        value: '${stats.aapen}',
        color: DriftProTheme.info,
        icon: Icons.flag_outlined,
      ),
      (
        status: TicketStatus.underBehandling,
        label: 'Behandles',
        value: '${stats.underBehandling}',
        color: DriftProTheme.warning,
        icon: Icons.hourglass_top_rounded,
      ),
      (
        status: null,
        label: 'Kritisk',
        value: '${stats.kritiskAapne}',
        color: DriftProTheme.severityCritical,
        icon: Icons.warning_amber_rounded,
      ),
    ];

    // Kritisk is special: filter open+critical via status aapen if value > 0 —
    // keep as info chip only when tapping sets aapen for simplicity,
    // or we just highlight. For "Kritisk" tap set filter to aapen (user sees open ones).
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 520;
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isDark ? DriftProTheme.cardDark : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? DriftProTheme.dividerDark : const Color(0xFFE2E8F0),
            ),
          ),
          child: wide
              ? Row(
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(child: _kpiTile(items[i])),
                    ],
                  ],
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final item in items)
                      SizedBox(
                        width: (c.maxWidth - 8) / 2,
                        child: _kpiTile(item),
                      ),
                  ],
                ),
        );
      },
    );
  }

  Widget _kpiTile(
    ({TicketStatus? status, String label, String value, Color color, IconData icon}) item,
  ) {
    final isKritisk = item.label == 'Kritisk';
    final selected = isKritisk
        ? false
        : item.status == null
            ? filterStatus == null && item.label == 'Alle'
            : filterStatus == item.status;

    return Material(
      color: selected
          ? item.color.withValues(alpha: 0.14)
          : item.color.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (item.label == 'Alle') {
            onClear();
            return;
          }
          if (isKritisk) {
            // Vis åpne (kritisk er delmengde) — bruker ser kritiske i lista.
            onSelect(TicketStatus.aapen);
            return;
          }
          if (item.status != null) onSelect(item.status!);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? item.color.withValues(alpha: 0.55)
                  : item.color.withValues(alpha: 0.18),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(item.icon, size: 18, color: item.color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.value,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        color: item.color,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: item.color.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.onChanged,
    required this.showDeleted,
    required this.canShowDeleted,
    required this.onToggleDeleted,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;
  final bool showDeleted;
  final bool canShowDeleted;
  final VoidCallback onToggleDeleted;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: (_) => onChanged(),
            decoration: InputDecoration(
              hintText: 'Søk ID, tittel, person…',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () {
                        controller.clear();
                        onChanged();
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.white,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
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
        ),
        if (canShowDeleted) ...[
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Slettet'),
            selected: showDeleted,
            onSelected: (_) => onToggleDeleted(),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ],
    );
  }
}

class _EmployeeFilterBanner extends StatelessWidget {
  const _EmployeeFilterBanner({required this.name, required this.onClear});
  final String name;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: DriftProTheme.primaryGreen.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_outline,
              size: 16, color: DriftProTheme.primaryGreen),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Filtrert: $name',
              style: DriftProTheme.caption.copyWith(
                fontWeight: FontWeight.w800,
                color: DriftProTheme.primaryGreen,
              ),
            ),
          ),
          TextButton(onPressed: onClear, child: const Text('Fjern')),
        ],
      ),
    );
  }
}

class _TicketRow extends StatelessWidget {
  const _TicketRow({
    required this.ticket,
    required this.isDark,
    required this.sevColor,
    required this.statusColor,
    required this.onTap,
    this.dateLabel,
  });

  final Ticket ticket;
  final bool isDark;
  final Color sevColor;
  final Color statusColor;
  final VoidCallback onTap;
  final String? dateLabel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark ? DriftProTheme.cardDark : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: ticket.severity == TicketSeverity.kritisk
                  ? sevColor.withValues(alpha: 0.45)
                  : (isDark
                      ? DriftProTheme.dividerDark
                      : const Color(0xFFE8EEF0)),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 52,
                decoration: BoxDecoration(
                  color: sevColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _pill(ticket.severity.label, sevColor),
                        const SizedBox(width: 6),
                        _pill(ticket.status.label, statusColor),
                        const Spacer(),
                        if (dateLabel != null)
                          Text(
                            dateLabel!,
                            style: DriftProTheme.caption.copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      ticket.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DriftProTheme.labelMd.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        ticket.reporterName ?? 'Ukjent',
                        if ((ticket.category ?? '').isNotEmpty) ticket.category!,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DriftProTheme.caption,
                    ),
                    const SizedBox(height: 6),
                    CaseTraceChip(
                      traceRef: ticket.displayTraceRef,
                      id: ticket.id,
                      compact: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, size: 20, color: Color(0xFF94A3B8)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 10,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasSearch, required this.onNew});
  final bool hasSearch;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasSearch ? Icons.search_off_rounded : Icons.inventory_2_outlined,
            size: 48,
            color: const Color(0xFF94A3B8),
          ),
          const SizedBox(height: 14),
          Text(
            hasSearch ? 'Ingen treff' : 'Ingen saker her',
            style: DriftProTheme.labelLg.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            hasSearch
                ? 'Prøv et annet søk eller nullstill filter.'
                : 'Meld et avvik når noe skjer — det dukker opp her.',
            textAlign: TextAlign.center,
            style: DriftProTheme.caption,
          ),
          if (!hasSearch) ...[
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onNew,
              icon: const Icon(Icons.add),
              label: const Text('Meld avvik'),
            ),
          ],
        ],
      ),
    );
  }
}
