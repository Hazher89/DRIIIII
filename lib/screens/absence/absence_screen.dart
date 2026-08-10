import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/routing/app_paths.dart';
import '../../core/layout/mobile_shell_scaffold.dart';
import '../../core/routing/route_url_sync.dart';

import '../../core/utils/nb_date_format.dart';

import '../../core/constants/leave_rules.dart';
import '../../core/constants/vacation_year_window.dart';
import '../../core/services/absence/absence_service.dart';
import '../../core/services/absence/leave_eligibility.dart';
import '../../core/services/absence/leave_period_usage_service.dart';
import 'widgets/leave_egenmelding_blocked_sheet.dart';
import '../../models/leave_period_usage.dart';
import '../../core/services/absence/department_leave_conflict_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/absence.dart';
import '../../models/department.dart';
import '../../models/user_profile.dart';
import '../../core/permissions/permission_gate.dart';
import '../../core/permissions/access_keys.dart';
import '../../core/permissions/user_access.dart';
import 'new_absence_screen.dart';
import 'vacation_admin_screen.dart';
import 'widgets/department_leave_tip_card.dart';
import 'widgets/leave_quick_actions.dart';
import 'widgets/leave_rules_panel.dart';
import 'widgets/leave_saldo_panel.dart';
import 'widgets/leave_team_table.dart';
import 'widgets/leave_unified_team_view.dart';
import '../../widgets/driftpro_loading_indicator.dart';

enum _MineStatusFilter { alle, ventende, godkjent, avvist }

class AbsenceScreen extends StatefulWidget {
  const AbsenceScreen({super.key, this.initialTab});

  final String? initialTab;

  @override
  State<AbsenceScreen> createState() => _AbsenceScreenState();
}

class _AbsenceScreenState extends State<AbsenceScreen> with SingleTickerProviderStateMixin {
  TabController? _tabController;
  List<Tab> _tabs = [];
  int _godkjennTabIndex = -1;
  int _teamCalendarTabIndex = 0;
  _MineStatusFilter _mineFilter = _MineStatusFilter.alle;

  List<Absence> _myAbsences = [];
  List<Absence> _scopedAbsences = [];
  List<Absence> _pendingApprovals = [];
  Map<String, List<DepartmentLeaveOverlap>> _approvalOverlaps = {};
  Map<String, List<DepartmentLeaveOverlap>> _teamOverlaps = {};
  Map<String, String> _departmentNames = {};
  AbsenceQuota? _quota;
  LeavePeriodUsage? _periodUsage;
  CompanyLeaveSettings _companySettings = const CompanyLeaveSettings();
  UserProfile? _profile;
  bool _isLoading = true;
  bool _saldoLoading = false;
  String? _loadError;
  String? _saldoError;
  DateTime _calendarMonth = DateTime.now();
  int _selectedYear = DateTime.now().year;
  List<UserProfile> _teamProfiles = [];
  List<AbsenceQuota> _teamQuotas = [];
  String? _calendarUserFilter;
  String? _pendingTabSlug;

  @override
  void initState() {
    super.initState();
    _pendingTabSlug = widget.initialTab;
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController?.removeListener(_onAbsenceTabChanged);
    _tabController?.dispose();
    super.dispose();
  }

  int _indexForSlug(String? slug, int tabCount) {
    if (slug == null || slug.isEmpty) return 0;
    switch (slug) {
      case 'dashboard':
        return 0;
      case 'mine':
        return 1;
      case 'godkjenn':
        return _godkjennTabIndex >= 0 ? _godkjennTabIndex : 0;
      case 'team':
        return _teamCalendarTabIndex.clamp(0, tabCount - 1);
      case 'roster':
        return tabCount - 1;
      default:
        return 0;
    }
  }

  String _slugForIndex(int index, bool isManager) {
    if (index == 0) return 'dashboard';
    if (index == 1) return 'mine';
    if (isManager && index == _godkjennTabIndex) return 'godkjenn';
    if (index == _teamCalendarTabIndex) return 'team';
    return 'roster';
  }

  void _syncAbsenceUrl(bool isManager) {
    if (!mounted || _tabController == null) return;
    RouteUrlSync.goIfChanged(
      context,
      AppPaths.absencePath(tab: _slugForIndex(_tabController!.index, isManager)),
    );
  }

  void _onAbsenceTabChanged() {
    if (_tabController == null || _tabController!.indexIsChanging || !mounted) return;
    final profile = _profile;
    if (profile == null) return;
    final isManager = profile.access.canApproveLeave ||
        profile.access.canRegisterLeaveForOthers ||
        profile.isAdmin;
    _syncAbsenceUrl(isManager);
  }

  void _rebuildTabs(bool isDark, bool isManager, bool canAdmin) {
    final previousIndex = _tabController?.index ?? 0;
    final previousLength = _tabController?.length ?? 0;

    var idx = 0;
    final tabs = <Tab>[
      const Tab(icon: Icon(Icons.dashboard_outlined, size: 20), text: 'Dashboard'),
      const Tab(icon: Icon(Icons.person_outline, size: 20), text: 'Mine'),
    ];
    idx = 2;
    int godkjennIdx = -1;
    if (isManager) {
      godkjennIdx = idx;
      tabs.add(
        Tab(
          icon: const Icon(Icons.fact_check_outlined, size: 20),
          text: 'Godkjenn (${_pendingApprovals.length})',
        ),
      );
      idx++;
    }
    final teamCalIdx = idx;
    tabs.add(
      const Tab(
        icon: Icon(Icons.calendar_month_outlined, size: 20),
        text: 'Team & kalender',
      ),
    );
    idx++;
    tabs.add(
      Tab(
        icon: Icon(Icons.groups_outlined, size: 20),
        text: isManager ? (canAdmin ? 'Ansatte' : 'Team') : 'Hjelp',
      ),
    );

    if (_tabController == null || previousLength != tabs.length) {
      _tabController?.removeListener(_onAbsenceTabChanged);
      _tabController?.dispose();
      var initialIndex = previousIndex.clamp(0, tabs.length - 1);
      if (_pendingTabSlug != null) {
        initialIndex = _indexForSlug(_pendingTabSlug, tabs.length);
        _pendingTabSlug = null;
      }
      _tabController = TabController(
        length: tabs.length,
        vsync: this,
        initialIndex: initialIndex,
      )..addListener(_onAbsenceTabChanged);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _tabController == null) return;
        _syncAbsenceUrl(isManager);
      });
    }

    _tabs = tabs;
    _godkjennTabIndex = godkjennIdx;
    _teamCalendarTabIndex = teamCalIdx;
  }

  void _goToTab(int index) {
    if (_tabController == null || index < 0 || index >= _tabController!.length) {
      return;
    }
    _tabController!.animateTo(index);
  }

  List<Widget> _buildTabBodies(bool isDark, bool isManager, bool canAdmin) {
    return [
      _buildDashboardTab(isDark, isManager),
      _buildMineTab(isDark, isManager),
      if (isManager) _buildHandlingTab(isDark),
      _buildTeamCalendarTab(isDark, isManager),
      if (isManager) _buildTeamTab(isDark, canAdmin) else _buildRulesTab(isDark),
    ];
  }

  static Map<String, List<DepartmentLeaveOverlap>> _computeTeamOverlaps(
    List<Absence> scoped,
  ) {
    final out = <String, List<DepartmentLeaveOverlap>>{};
    for (final a in scoped.where((x) => x.status == AbsenceStatus.ventende)) {
      out[a.id] = DepartmentLeaveConflictService.forRequest(
        a,
        scoped,
        vacationOnly: a.type == AbsenceType.ferie,
      );
    }
    return out;
  }

  Future<void> _refreshScopedLists() async {
    final profile = _profile;
    if (profile == null || profile.companyId == null) return;

    final results = await Future.wait([
      SupabaseService.fetchAbsences(userId: profile.id),
      SupabaseService.fetchScopedAbsences(profile: profile),
    ]);

    final mine = results[0] as List<Absence>;
    final scoped = results[1] as List<Absence>;
    final canHandleOthers = profile.access.canApproveLeave ||
        profile.access.canRegisterLeaveForOthers ||
        profile.isAdmin;
    final pending = canHandleOthers
        ? scoped
            .where((a) =>
                a.status == AbsenceStatus.ventende && a.userId != profile.id)
            .toList()
        : <Absence>[];

    final overlaps = <String, List<DepartmentLeaveOverlap>>{};
    for (final a in pending) {
      overlaps[a.id] = DepartmentLeaveConflictService.forRequest(
        a,
        scoped,
        vacationOnly: a.type == AbsenceType.ferie,
      );
    }
    final teamOverlaps = _computeTeamOverlaps(scoped);

    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    setState(() {
      _myAbsences = mine;
      _scopedAbsences = scoped;
      _pendingApprovals = pending;
      _approvalOverlaps = overlaps;
      _teamOverlaps = teamOverlaps;
      _rebuildTabs(
        isDark,
        canHandleOthers,
        profile.isAdmin && profile.access.canVacationAdmin,
      );
    });
  }

  Future<void> _loadAllData() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final profile = await SupabaseService.fetchEffectiveUserProfile();
      if (profile == null || profile.companyId == null) {
        setState(() => _loadError =
            'Profilen er ikke koblet til et selskap — data fra Supabase vises ikke. '
            'Logg ut, logg inn på nytt, eller kjør ensure_internal_profile_missing.sql i Supabase.');
        return;
      }

      _profile = profile;
      final companyId = profile.companyId!;

      final results = await Future.wait([
        SupabaseService.fetchAbsences(userId: profile.id),
        SupabaseService.fetchScopedAbsences(profile: profile),
        SupabaseService.fetchCompanyLeaveSettings(companyId),
        SupabaseService.fetchDepartments(companyId: companyId),
      ]);

      final mine = results[0] as List<Absence>;
      final scoped = results[1] as List<Absence>;
      final depts = results[3] as List<Department>;
      final canHandleOthers = profile.access.canApproveLeave ||
        profile.access.canRegisterLeaveForOthers ||
        profile.isAdmin;
      final pending = canHandleOthers
          ? scoped
              .where((a) =>
                  a.status == AbsenceStatus.ventende && a.userId != profile.id)
              .toList()
          : <Absence>[];

      final overlaps = <String, List<DepartmentLeaveOverlap>>{};
      for (final a in pending) {
        overlaps[a.id] = DepartmentLeaveConflictService.forRequest(
          a,
          scoped,
          vacationOnly: a.type == AbsenceType.ferie,
        );
      }
      final teamOverlaps = _computeTeamOverlaps(scoped);

      setState(() {
        _myAbsences = mine;
        _scopedAbsences = scoped;
        _companySettings = results[2] as CompanyLeaveSettings;
        _pendingApprovals = pending;
        _approvalOverlaps = overlaps;
        _teamOverlaps = teamOverlaps;
        _departmentNames = {for (final d in depts) d.id: d.name};
      });

      if (mounted) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        setState(() {
          _rebuildTabs(
            isDark,
            canHandleOthers,
            profile.isAdmin && profile.access.canVacationAdmin,
          );
          // Viktig: ikke la saldo/team blokkere hele siden (fanene viste bare spinner).
          _isLoading = false;
        });
      }

      await Future.wait([
        _loadSaldo(profile),
        _loadTeamOverview(profile),
      ]);
    } catch (e) {
      debugPrint('Error loading absence data: $e');
      setState(() => _loadError = 'Kunne ikke laste fravær: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSaldo(UserProfile profile) async {
    if (profile.companyId == null) return;
    setState(() {
      _saldoLoading = true;
      _saldoError = null;
    });
    try {
      var quota = await SupabaseService.fetchAbsenceQuota(
        userId: profile.id,
        year: _selectedYear,
      );
      quota ??= await SupabaseService.ensureAbsenceQuota(
        userId: profile.id,
        companyId: profile.companyId!,
        year: _selectedYear,
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException(
          'Tidsavbrudd ved henting av feriekvote',
        ),
      );
      final periodUsage = LeavePeriodUsageService.compute(
        absences: _myAbsences,
        hireDate: profile.hireDate,
      );
      if (mounted) {
        setState(() {
          _quota = quota;
          _periodUsage = periodUsage;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _quota = null;
          _periodUsage = null;
          _saldoError = e.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _saldoLoading = false);
    }
  }

  Future<void> _loadTeamOverview(UserProfile profile) async {
    if (profile.companyId == null) return;
    final canHandleOthers = profile.access.canApproveLeave ||
        profile.access.canRegisterLeaveForOthers ||
        profile.isAdmin;
    if (!canHandleOthers) {
      final peers = await SupabaseService.fetchScopedProfiles(profile);
      final deptPeers = profile.departmentId != null
          ? peers
              .where((p) =>
                  p.departmentId == profile.departmentId && !p.isPartnerPortalUser)
              .toList()
          : peers.where((p) => p.id == profile.id).toList();
      if (!mounted) return;
      setState(() {
        _teamProfiles = deptPeers.isNotEmpty ? deptPeers : [profile];
        _teamQuotas = [];
      });
      return;
    }
    final allProfiles = profile.isSuperAdmin || profile.access.dataScopeCompany
        ? await SupabaseService.fetchProfiles()
        : await SupabaseService.fetchProfiles(companyId: profile.companyId);
    final scopedProfiles = profile.access.dataScopeCompany
        ? allProfiles.where((p) => !p.isPartnerPortalUser).toList()
        : allProfiles
            .where((p) =>
                p.departmentId == profile.departmentId && !p.isPartnerPortalUser)
            .toList();
    final quotas = await SupabaseService.fetchAbsenceQuotasForCompany(
      companyId: profile.companyId!,
      year: _selectedYear,
    );
    final teamIds = scopedProfiles.map((p) => p.id).toSet();
    final scopedQuotas = quotas.where((q) => teamIds.contains(q.userId)).toList();

    if (!mounted) return;
    setState(() {
      _teamProfiles = scopedProfiles;
      _teamQuotas = scopedQuotas;
    });
  }

  Color _colorForType(AbsenceType type) {
    switch (type) {
      case AbsenceType.ferie:
        return DriftProTheme.absenceVacation;
      case AbsenceType.egenmelding:
        return DriftProTheme.absenceSickSelf;
      case AbsenceType.syktBarn:
        return DriftProTheme.absenceSickChild;
      case AbsenceType.permisjon:
        return DriftProTheme.absenceLeave;
      case AbsenceType.sykmelding:
        return DriftProTheme.absenceSickNote;
    }
  }

  IconData _iconForType(AbsenceType t) {
    switch (t) {
      case AbsenceType.ferie:
        return Icons.wb_sunny_rounded;
      case AbsenceType.egenmelding:
        return Icons.person_outline_rounded;
      case AbsenceType.syktBarn:
        return Icons.child_care_rounded;
      case AbsenceType.permisjon:
        return Icons.timer_outlined;
      case AbsenceType.sykmelding:
        return Icons.medical_services_outlined;
    }
  }

  int _days(Absence a) {
    if (a.type == AbsenceType.ferie) {
      return a.vacationDayCount ??
          AbsenceService.vacationDayCount(a.startDate, a.endDate);
    }
    return a.totalDays ?? (a.endDate.difference(a.startDate).inDays + 1);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _profile == null) {
      return const DriftProLoadingPage();
    }

    if (!_isLoading && (_tabController == null || _tabs.isEmpty)) {
      final msg = _loadError ??
          (_profile != null ? 'Kunne ikke laste innhold på fraværssiden.' : 'Fant ikke pålogget bruker eller bedrift.');
      return MobileShellScaffold(
        title: 'Fravær & Ferie',
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.warning_amber_rounded, size: 52, color: DriftProTheme.warning),
                const SizedBox(height: 16),
                Text(msg, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: _loadAllData, child: const Text('Prøv igjen')),
              ],
            ),
          ),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final access = _profile?.access;
    final profile = _profile!;
    final isManager = profile.access.canApproveLeave ||
        profile.access.canRegisterLeaveForOthers ||
        profile.isAdmin;
    final canAdmin = profile.isAdmin && profile.access.canVacationAdmin;

    return PermissionGuard(
      profile: _profile,
      accessKey: AccessKeys.fravaer,
      child: MobileShellScaffold(
      title: 'Fravær & Ferie',
      actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () => showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Regler og hjelp'),
                content: const SingleChildScrollView(child: LeaveRulesPanel()),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Lukk'),
                  ),
                ],
              ),
            ),
            tooltip: 'Regler (Lovdata)',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAllData,
            tooltip: 'Oppdater',
          ),
        ],
      bottom: TabBar(
        controller: _tabController,
        isScrollable: true,
        indicatorColor: DriftProTheme.primaryGreen,
        tabs: _tabs,
      ),
      backgroundColor:
          isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      floatingActionButton: access?.canFravaer != false
            ? FloatingActionButton.extended(
                onPressed: () => _showRegisterOptions(context),
                icon: const Icon(Icons.add_task),
                label: const Text('Ny registrering'),
              )
            : null,
      body: TabBarView(
        controller: _tabController,
        children: _buildTabBodies(isDark, isManager, canAdmin),
      ),
    ),
    );
  }

  Widget _buildDashboardTab(bool isDark, bool isManager) {
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off, size: 48, color: DriftProTheme.error),
              const SizedBox(height: 16),
              Text(_loadError!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _loadAllData, child: const Text('Prøv igjen')),
            ],
          ),
        ),
      );
    }

    final todayOut = AbsenceService.filterActiveOnDate(
      _scopedAbsences.where((a) => a.status == AbsenceStatus.godkjent).toList(),
      DateTime.now(),
    );
    final pendingVacation = _scopedAbsences
        .where((a) => a.type == AbsenceType.ferie && a.status == AbsenceStatus.ventende)
        .length;
    final approvedVacationDays =
        AbsenceService.approvedVacationDaysInYear(_scopedAbsences, _selectedYear);
    final ferieIgjen = _quota?.vacationDaysRemaining;

    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? DriftProTheme.cardDark : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200,
              ),
              boxShadow: DriftProTheme.cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Fraværssenter', style: DriftProTheme.headingSm),
                const SizedBox(height: 4),
                Text(
                  isManager
                      ? 'Godkjenn søknader, se teamoversikt og planlegg ferie i to kalendere.'
                      : 'Søk ferie og fravær — full oversikt over saldo, status og kollegaer i avdelingen.',
                  style: DriftProTheme.bodySm,
                ),
                const SizedBox(height: 12),
                _statRow(isDark, [
                  _StatChip(
                    label: 'Fravær i dag',
                    value: '${todayOut.length}',
                    icon: Icons.people_outline,
                    color: DriftProTheme.primaryGreen,
                  ),
                  _StatChip(
                    label: 'Venter godkjenning',
                    value: '${_pendingApprovals.length}',
                    icon: Icons.hourglass_top,
                    color: DriftProTheme.warning,
                  ),
                  _StatChip(
                    label: 'Ferie igjen',
                    value: ferieIgjen != null ? '$ferieIgjen d' : '—',
                    icon: Icons.beach_access,
                    color: DriftProTheme.absenceVacation,
                  ),
                  _StatChip(
                    label: 'Ferie venter',
                    value: '$pendingVacation',
                    icon: Icons.pending_actions,
                    color: Colors.blue,
                  ),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 14),
          LeaveQuickActions(
            onTypeSelected: (t) => _openNewRequest(t),
            egenmeldingBlocked: _egenmeldingBlockedForSelf,
            onEgenmeldingBlocked: () {
              if (_periodUsage == null) return;
              showLeaveEgenmeldingBlockedSheet(
                context,
                periodUsage: _periodUsage!,
                maxDays: _companySettings.egenmeldingDaysPerYear,
                onChooseAlternative: _openNewRequest,
              );
            },
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Text('Din saldo $_selectedYear', style: DriftProTheme.headingSm),
              const Spacer(),
              DropdownButton<int>(
                value: _selectedYear,
                items: VacationYearWindow.years
                    .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                    .toList(),
                onChanged: (v) async {
                  if (v == null || _profile == null) return;
                  setState(() => _selectedYear = v);
                  await _loadSaldo(_profile!);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          LeaveSaldoPanel(
            quota: _quota,
            periodUsage: _periodUsage,
            childrenUnder12: _profile?.childrenUnder12Count ?? 0,
            selectedYear: _selectedYear,
            company: _companySettings,
            onChooseAlternative: _openNewRequest,
            isLoading: _saldoLoading,
            error: _saldoError,
            onRetry: () {
              if (_profile != null) _loadSaldo(_profile!);
            },
            onRequestSetup: _profile == null
                ? null
                : () async {
                    try {
                      final q = await SupabaseService.ensureAbsenceQuota(
                        userId: _profile!.id,
                        companyId: _profile!.companyId!,
                        year: _selectedYear,
                      );
                      setState(() => _quota = q);
                    } catch (e) {
                      setState(() => _saldoError = e.toString());
                    }
                  },
          ),
          const SizedBox(height: 20),
          Text('På fravær i dag', style: DriftProTheme.headingSm),
          const SizedBox(height: 8),
          if (todayOut.isEmpty)
            Text('Ingen godkjent fravær i dag.', style: DriftProTheme.bodySm)
          else
            ...todayOut.take(8).map((a) => _absenceListTile(a, isDark)),
          if (isManager && _pendingApprovals.isNotEmpty) ...[
            const SizedBox(height: 16),
            _actionBanner(
              isDark,
              icon: Icons.fact_check_outlined,
              color: DriftProTheme.warning,
              title: '${_pendingApprovals.length} søknader venter på deg',
              subtitle: _overlapPendingCount() > 0
                  ? '${_overlapPendingCount()} har overlapp med kollegaer i avdelingen'
                  : 'Trykk for å godkjenne eller avvise',
              onTap: () => _goToTab(_godkjennTabIndex),
            ),
          ],
          if (isManager) ...[
            const SizedBox(height: 10),
            _actionBanner(
              isDark,
              icon: Icons.calendar_month_outlined,
              color: DriftProTheme.absenceVacation,
              title: 'Team & kalender',
              subtitle: 'Saldo, kalender og alle søknader for ansatte',
              onTap: () => _goToTab(_teamCalendarTabIndex),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Godkjente feriedager i $_selectedYear: $approvedVacationDays',
            style: DriftProTheme.caption,
          ),
        ],
      ),
    );
  }

  Widget _statRow(bool isDark, List<_StatChip> chips) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: chips
              .map(
                (c) => SizedBox(
                  width: w,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? DriftProTheme.cardDark : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade100,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(c.icon, color: c.color, size: 22),
                        const SizedBox(height: 6),
                        Text(c.value, style: DriftProTheme.labelLg),
                        Text(
                          c.label,
                          textAlign: TextAlign.center,
                          style: DriftProTheme.caption,
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  int _overlapPendingCount() {
    return _pendingApprovals
        .where((a) => (_approvalOverlaps[a.id] ?? []).isNotEmpty)
        .length;
  }

  Widget _actionBanner(
    bool isDark, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: DriftProTheme.labelMd.copyWith(fontWeight: FontWeight.w700)),
                    Text(subtitle, style: DriftProTheme.caption),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: color.withValues(alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMineTab(bool isDark, bool isManager) {
    var list = [..._myAbsences]..sort((a, b) => b.startDate.compareTo(a.startDate));
    list = list.where((a) {
      switch (_mineFilter) {
        case _MineStatusFilter.alle:
          return true;
        case _MineStatusFilter.ventende:
          return a.status == AbsenceStatus.ventende;
        case _MineStatusFilter.godkjent:
          return a.status == AbsenceStatus.godkjent;
        case _MineStatusFilter.avvist:
          return a.status == AbsenceStatus.avvist;
      }
    }).toList();

    if (_myAbsences.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.event_available, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text('Ingen søknader ennå', style: DriftProTheme.headingSm),
              const SizedBox(height: 8),
              Text(
                'Bruk hurtigvalg på Dashboard for å søke ferie, egenmelding eller sykt barn.',
                textAlign: TextAlign.center,
                style: DriftProTheme.bodySm,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => _openNewRequest(AbsenceType.ferie),
                icon: const Icon(Icons.add),
                label: const Text('Ny søknad'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: DriftProTheme.primaryGreen.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: DriftProTheme.primaryGreen.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Mine søknader', style: DriftProTheme.labelLg),
              const SizedBox(height: 4),
              Text(
                isManager
                    ? 'Dette er kun dine egne søknader. Teamets oversikt finner du under Team & kalender og Godkjenn.'
                    : 'Full oversikt over alt du har søkt — ventende, godkjent og avvist.',
                style: DriftProTheme.bodySm,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _MineStatusFilter.values.map((f) {
              final selected = _mineFilter == f;
              final label = switch (f) {
                _MineStatusFilter.alle => 'Alle',
                _MineStatusFilter.ventende => 'Ventende',
                _MineStatusFilter.godkjent => 'Godkjent',
                _MineStatusFilter.avvist => 'Avvist',
              };
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text(label),
                  selected: selected,
                  onSelected: (_) => setState(() => _mineFilter = f),
                  selectedColor: DriftProTheme.primaryGreen.withValues(alpha: 0.15),
                  checkmarkColor: DriftProTheme.primaryGreen,
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              'Ingen søknader med valgt filter.',
              textAlign: TextAlign.center,
              style: DriftProTheme.bodySm,
            ),
          )
        else
          ...list.map((a) => _buildAbsenceCard(a, _days(a), isDark)),
      ],
    );
  }

  Widget _buildTeamCalendarTab(bool isDark, bool isManager) {
    return LeaveUnifiedTeamView(
      isManager: isManager,
      initialUserFilter: _calendarUserFilter,
      month: _calendarMonth,
      scopedAbsences: _scopedAbsences,
      teamProfiles: _teamProfiles,
      teamQuotas: _teamQuotas,
      companySettings: _companySettings,
      selectedYear: _selectedYear,
      departmentNames: _departmentNames,
      overlapsByAbsenceId: _teamOverlaps,
      profile: _profile,
      colorForType: _colorForType,
      iconForType: _iconForType,
      daysFor: _days,
      excludeSelfFromList: isManager,
      onRefresh: _loadAllData,
      onDayTap: isManager ? _onCalendarDayTap : null,
      onApprove: isManager ? (a) => _updateStatus(a.id, AbsenceStatus.godkjent) : null,
      onReject: isManager ? (a) => _updateStatus(a.id, AbsenceStatus.avvist) : null,
      onMonthChanged: (m) {
        setState(() => _calendarMonth = m);
        if (m.year != _selectedYear && _profile != null) {
          _selectedYear = m.year;
          _loadTeamOverview(_profile!);
          _loadSaldo(_profile!);
        }
      },
    );
  }

  bool get _egenmeldingBlockedForSelf {
    if (_profile == null || _periodUsage == null) return false;
    return LeaveEligibility.isEgenmeldingExhausted(
      usage: _periodUsage,
      maxDays: _companySettings.egenmeldingDaysPerYear,
    );
  }

  void _openNewRequest(AbsenceType type) {
    final profile = _profile;
    if (type == AbsenceType.egenmelding && _egenmeldingBlockedForSelf) {
      showLeaveEgenmeldingBlockedSheet(
        context,
        periodUsage: _periodUsage!,
        maxDays: _companySettings.egenmeldingDaysPerYear,
        onChooseAlternative: _openNewRequest,
      );
      return;
    }
    final allowPick = profile != null &&
        (profile.access.canRegisterLeaveForOthers || profile.isAdmin);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NewAbsenceScreen(
          type: type,
          allowPickEmployee: allowPick,
        ),
      ),
    ).then((v) {
      if (v == true) _loadAllData();
    });
  }

  Widget _buildHandlingTab(bool isDark) {
    if (_pendingApprovals.isEmpty) {
      return _empty('Ingen ventende forespørsler.');
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: DriftProTheme.warning.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'Du har ${_pendingApprovals.length} saker som krever handling.',
            style: DriftProTheme.bodySm.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 12),
        ..._pendingApprovals.map(
          (a) => _buildAbsenceCard(a, _days(a), isDark, showActions: true),
        ),
      ],
    );
  }

  void _onCalendarDayTap(DateTime date, List<Absence> dayAbsences) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  NbDateFormat.format(date, 'EEEE d. MMMM yyyy'),
                  style: DriftProTheme.headingSm,
                ),
                const SizedBox(height: 12),
                if (dayAbsences.isEmpty)
                  const Text('Ingen registrert fravær denne dagen.')
                else
                  ...dayAbsences.map(
                    (a) => ListTile(
                      leading: Icon(_iconForType(a.type), color: _colorForType(a.type)),
                      title: Text(a.userName ?? 'Ansatt'),
                      subtitle: Text('${a.type.label} · ${_days(a)} dager'),
                    ),
                  ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openRegisterForDate(date);
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Legg inn fravær / ferie'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openRegisterForDate(DateTime date) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: AbsenceType.values
            .map(
              (t) => ListTile(
                leading: Icon(_iconForType(t), color: _colorForType(t)),
                title: Text(t.label),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NewAbsenceScreen(
                        type: t,
                        initialStart: date,
                        initialEnd: date,
                        allowPickEmployee: _profile != null &&
                            (_profile!.role == UserRole.leder ||
                                _profile!.isAdmin),
                      ),
                    ),
                  ).then((v) {
                    if (v == true) _loadAllData();
                  });
                },
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildRulesTab(bool isDark) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        LeaveRulesPanel(),
        SizedBox(height: 16),
        _InfoBox(
          title: 'Automatisk registrering',
          body:
              'Når du søker om fravær, får avdelingsleder og admin beskjed. '
              'Ved godkjenning trekkes dager fra kvoten og fraværet vises i kalenderen.',
        ),
        SizedBox(height: 12),
        _InfoBox(
          title: 'Ferie over nyttår',
          body:
              'Eksempel: 35 dager tildelt, 30 brukt → 5 dager kan overføres (maks '
              '${LeaveRules.defaultMaxCarryoverDays} etter avtale). Neste år: 35 nye + 5 overført = 40 dager totalt.',
        ),
      ],
    );
  }

  Widget _buildTeamTab(bool isDark, bool canAdmin) {
    return Column(
      children: [
        if (canAdmin)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Material(
              color: DriftProTheme.primaryGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => VacationAdminScreen(
                        companyId: _profile!.companyId!,
                        companySettings: _companySettings,
                      ),
                    ),
                  );
                  await _loadAllData();
                },
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: DriftProTheme.primaryGreen.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.admin_panel_settings_outlined,
                          color: DriftProTheme.primaryGreen,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Avansert ferieadministrasjon',
                              style: DriftProTheme.labelLg.copyWith(
                                color: DriftProTheme.primaryGreen,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Enkel oversikt: velg år, del ut feriedager til alle eller valgte ansatte, '
                              'se hvem som har dager igjen.',
                              style: DriftProTheme.bodySm,
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, size: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: LeaveTeamTable(
              employees: _teamProfiles,
              quotas: _teamQuotas,
              absences: _scopedAbsences,
              company: _companySettings,
              year: _selectedYear,
              canEdit: canAdmin,
              onEditQuota: _editTeamQuota,
              onTapEmployee: (u) {
                setState(() => _calendarUserFilter = u.id);
                _tabController?.animateTo(_teamCalendarTabIndex);
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _editTeamQuota(UserProfile user, AbsenceQuota? existing) async {
    if (_profile?.role == UserRole.leder && user.id == _profile?.id) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Avdelingsleder kan ikke endre egen ferie/fraværskvote.'),
          ),
        );
      }
      return;
    }
    final totalCtrl =
        TextEditingController(text: '${existing?.vacationDaysTotal ?? 25}');
    final carryCtrl =
        TextEditingController(text: '${existing?.vacationDaysCarriedOver ?? 0}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Feriekvote · ${user.fullName} ($_selectedYear)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: totalCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Tildelte feriedager i år',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: carryCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Overført fra i fjor',
                border: OutlineInputBorder(),
              ),
            ),
            if (existing != null) ...[
              const SizedBox(height: 12),
              Text(
                'Brukt: ${existing.vacationDaysUsed} · '
                'Totalt: ${existing.totalVacationDays} · '
                'Igjen: ${existing.vacationDaysRemaining}',
                style: DriftProTheme.caption,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lagre')),
        ],
      ),
    );
    if (ok != true || _profile?.companyId == null) return;
    try {
      await SupabaseService.upsertAbsenceQuota(
        userId: user.id,
        companyId: _profile!.companyId!,
        year: _selectedYear,
        vacationDaysTotal: int.tryParse(totalCtrl.text) ?? 25,
        vacationDaysCarriedOver: int.tryParse(carryCtrl.text) ?? 0,
      );
      await _loadAllData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Feriekvote oppdatert')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e')),
        );
      }
    }
  }

  Widget _buildAbsenceCard(
    Absence a,
    int days,
    bool isDark, {
    bool showActions = false,
  }) {
    final color = _colorForType(a.type);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade100,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _absenceListTile(a, isDark, days: days, color: color),
          if (showActions) ...[
            if ((_approvalOverlaps[a.id] ?? []).isNotEmpty)
              DepartmentLeaveTipCard(
                overlaps: _approvalOverlaps[a.id]!,
                departmentName: a.departmentId != null
                    ? _departmentNames[a.departmentId!]
                    : null,
                compact: true,
                isApprovalContext: true,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _updateStatus(a.id, AbsenceStatus.avvist),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('Avvis'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _updateStatus(a.id, AbsenceStatus.godkjent),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: DriftProTheme.success,
                      ),
                      child: const Text('Godkjenn'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _absenceListTile(Absence a, bool isDark, {int? days, Color? color}) {
    final d = days ?? _days(a);
    final c = color ?? _colorForType(a.type);
    return ListTile(
      contentPadding: const EdgeInsets.all(16),
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(_iconForType(a.type), color: c),
      ),
      title: Row(
        children: [
          Expanded(child: Text(a.type.label, style: DriftProTheme.labelLg)),
          _statusBadge(a.status),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (a.userName != null)
            Text('${a.userName}', style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(
            '${DateFormat('d. MMM').format(a.startDate)} – '
            '${DateFormat('d. MMM').format(a.endDate)} ($d dager)',
            style: DriftProTheme.bodySm,
          ),
          if (a.comment != null)
            Text('"${a.comment!}"', style: DriftProTheme.bodySm.copyWith(fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  Future<void> _updateStatus(String id, AbsenceStatus status) async {
    if (status == AbsenceStatus.godkjent) {
      final overlaps = _approvalOverlaps[id] ?? [];
      final approved = DepartmentLeaveConflictService.approvedVacation(overlaps);
      if (approved.isNotEmpty) {
        Absence? request;
        for (final a in _pendingApprovals) {
          if (a.id == id) {
            request = a;
            break;
          }
        }
        final names = approved
            .map((o) => o.other.userName ?? 'Kollega')
            .take(4)
            .join(', ');
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.groups_2_outlined, color: Colors.orange),
            title: const Text('Overlappende ferie i avdelingen'),
            content: Text(
              '${approved.length} kollega${approved.length == 1 ? "" : "er"} har '
              'allerede godkjent ferie i samme periode'
              '${request != null ? " som ${request.userName ?? "søkeren"}" : ""}:\n\n'
              '$names\n\n'
              'Vil du likevel godkjenne?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Avbryt'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Godkjenn likevel'),
              ),
            ],
          ),
        );
        if (go != true) return;
      }
    }

    setState(() {
      _pendingApprovals.removeWhere((a) => a.id == id);
      _approvalOverlaps.remove(id);
    });

    try {
      await SupabaseService.updateAbsenceStatus(id, status);
      await _refreshScopedLists();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status == AbsenceStatus.godkjent
                  ? 'Godkjent — registrert i kalender og kvote'
                  : 'Avvist',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Feil: $e')));
      }
    }
  }

  Widget _statusBadge(AbsenceStatus status) {
    Color color;
    switch (status) {
      case AbsenceStatus.godkjent:
        color = DriftProTheme.success;
        break;
      case AbsenceStatus.avvist:
        color = DriftProTheme.error;
        break;
      case AbsenceStatus.ventende:
        color = DriftProTheme.warning;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  void _showRegisterOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LeaveQuickActions(
            onTypeSelected: (t) {
              Navigator.pop(ctx);
              _openNewRequest(t);
            },
            egenmeldingBlocked: _egenmeldingBlockedForSelf,
            onEgenmeldingBlocked: () {
              Navigator.pop(ctx);
              if (_periodUsage == null) return;
              showLeaveEgenmeldingBlockedSheet(
                context,
                periodUsage: _periodUsage!,
                maxDays: _companySettings.egenmeldingDaysPerYear,
                onChooseAlternative: _openNewRequest,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _empty(String msg) => Center(child: Text(msg, style: DriftProTheme.bodyMd.copyWith(color: Colors.grey)));
}

class _StatChip {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
}

class _InfoBox extends StatelessWidget {
  final String title;
  final String body;
  const _InfoBox({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: DriftProTheme.labelLg),
          const SizedBox(height: 6),
          Text(body, style: DriftProTheme.bodySm),
        ],
      ),
    );
  }
}
