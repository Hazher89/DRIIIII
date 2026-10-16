import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/routing/app_paths.dart';
import '../../core/layout/mobile_shell_scaffold.dart';
import '../../core/routing/route_url_sync.dart';

import '../../core/utils/nb_date_format.dart';

import '../../core/config/driftpro_client.dart';
import '../../core/constants/company_principals.dart';
import '../../core/constants/leave_rules.dart';
import '../../core/constants/vacation_year_window.dart';
import '../../core/services/absence/absence_service.dart';
import '../../core/services/absence/leave_eligibility.dart';
import '../../core/services/absence/leave_period_usage_service.dart';
import 'widgets/leave_egenmelding_blocked_sheet.dart';
import 'widgets/leave_usage_meter.dart';
import '../../models/leave_period_usage.dart';
import '../../core/services/absence/department_leave_conflict_service.dart';
import '../../core/services/org/department_leader_scope.dart';
import '../../core/services/nav_badge_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/absence.dart';
import '../../models/department.dart';
import '../../models/user_profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/permissions/access_session_cache.dart';
import '../../core/permissions/permission_gate.dart';
import '../../core/permissions/access_keys.dart';
import '../../core/permissions/user_access.dart';
import 'leave_employee_detail_screen.dart';
import 'new_absence_screen.dart';
import 'vacation_admin_screen.dart';
import 'widgets/absence_detail_sheet.dart';
import 'widgets/department_leave_tip_card.dart';
import 'widgets/leave_quick_actions.dart';
import 'widgets/leave_rules_panel.dart';
import 'widgets/leave_saldo_panel.dart';
import 'widgets/leave_team_table.dart';
import 'widgets/leave_unified_team_view.dart';
import 'widgets/leave_team_employees_hub.dart';
import '../../widgets/driftpro_loading_indicator.dart';
import '../../core/layout/web_layout.dart';

enum _MineTypeFilter { alle, ferie, egenmelding, syktBarn, annet }

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
  _MineTypeFilter _mineTypeFilter = _MineTypeFilter.alle;

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
  Set<String> _managedDepartmentIds = {};
  bool _canManageTeamLeave = false;
  String? _calendarUserFilter;
  String? _pendingTabSlug;

  RealtimeChannel? _absenceChannel;
  Timer? _absenceDebounce;
  bool _absenceRefreshing = false;

  bool _manageTeamSync(UserProfile profile) {
    if (profile.isAdmin || CompanyPrincipal.isPrincipal(profile)) return true;
    if (profile.access.canApproveLeave ||
        profile.access.canRegisterLeaveForOthers) {
      return true;
    }
    return profile.role == UserRole.leder;
  }

  void _seedFromProfile(UserProfile profile) {
    _profile = profile;
    _canManageTeamLeave = _manageTeamSync(profile);
    _rebuildTabs(
      false,
      _canManageTeamLeave,
      profile.isAdmin && profile.access.canVacationAdmin,
    );
  }

  @override
  void initState() {
    super.initState();
    _pendingTabSlug = widget.initialTab;
    final cached = AccessSessionCache.profile;
    if (cached != null && (cached.companyId ?? '').isNotEmpty) {
      _seedFromProfile(cached);
    }
    _loadAllData();
  }

  @override
  void dispose() {
    _stopAbsenceRealtime();
    _absenceDebounce?.cancel();
    _tabController?.removeListener(_onAbsenceTabChanged);
    _tabController?.dispose();
    super.dispose();
  }

  void _stopAbsenceRealtime() {
    final ch = _absenceChannel;
    _absenceChannel = null;
    if (ch != null) {
      unawaited(SupabaseService.client.removeChannel(ch));
    }
  }

  void _startAbsenceRealtime(String companyId) {
    _stopAbsenceRealtime();
    void bump() {
      _absenceDebounce?.cancel();
      _absenceDebounce = Timer(const Duration(milliseconds: 350), () {
        if (!mounted) return;
        unawaited(_softRefreshAbsences());
      });
    }

    _absenceChannel = SupabaseService.client
        .channel('absences_live_$companyId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'absences',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'company_id',
            value: companyId,
          ),
          callback: (_) => bump(),
        )
        .subscribe();
  }

  /// Lett refresh uten fullskjerm-spinner — for kalender live-oppdatering.
  Future<void> _softRefreshAbsences() async {
    if (_absenceRefreshing) return;
    _absenceRefreshing = true;
    try {
      await _refreshScopedLists();
      final profile = _profile;
      if (profile != null) {
        unawaited(_loadSaldo(profile));
        if (_canManageTeamLeave) {
          unawaited(_loadTeamOverview(profile));
        }
      }
      unawaited(NavBadgeService.refresh());
    } finally {
      _absenceRefreshing = false;
    }
  }

  void _patchLocalAbsenceStatus(
    String id,
    AbsenceStatus status, {
    String? decisionComment,
  }) {
    Absence mapOne(Absence a) {
      if (a.id != id) return a;
      return a.copyWith(
        status: status,
        decisionComment: decisionComment ?? a.decisionComment,
        approvedAt: status == AbsenceStatus.godkjent
            ? DateTime.now()
            : a.approvedAt,
        approvedBy: status == AbsenceStatus.godkjent
            ? (_profile?.id ?? a.approvedBy)
            : a.approvedBy,
      );
    }

    setState(() {
      _scopedAbsences = _scopedAbsences.map(mapOne).toList();
      _myAbsences = _myAbsences.map(mapOne).toList();
      if (status != AbsenceStatus.ventende) {
        _pendingApprovals.removeWhere((a) => a.id == id);
        _approvalOverlaps.remove(id);
      }
      _teamOverlaps = _computeTeamOverlaps(_scopedAbsences);
    });
  }

  void _removeLocalAbsence(String id) {
    setState(() {
      _scopedAbsences = _scopedAbsences.where((a) => a.id != id).toList();
      _myAbsences = _myAbsences.where((a) => a.id != id).toList();
      _pendingApprovals.removeWhere((a) => a.id == id);
      _approvalOverlaps.remove(id);
      _teamOverlaps = _computeTeamOverlaps(_scopedAbsences);
    });
  }

  int _indexForSlug(String? slug, int tabCount) {
    if (slug == null || slug.isEmpty) return 0;
    if (DriftProClient.isMobile) {
      switch (slug) {
        case 'godkjenn':
          return _godkjennTabIndex >= 0 ? _godkjennTabIndex : 0;
        case 'mine':
          return _godkjennTabIndex >= 0 ? 1 : 0;
        case 'team':
          return _teamCalendarTabIndex.clamp(0, tabCount - 1);
        default:
          return 0;
      }
    }
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
    if (DriftProClient.isMobile) {
      if (isManager) {
        if (index == _godkjennTabIndex) return 'godkjenn';
        if (index == _teamCalendarTabIndex) return 'team';
        return 'mine';
      }
      return 'mine';
    }
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
    final isManager = _canManageTeamLeave;
    _syncAbsenceUrl(isManager);
  }

  void _rebuildTabs(bool isDark, bool isManager, bool canAdmin) {
    final previousIndex = _tabController?.index ?? 0;
    final previousLength = _tabController?.length ?? 0;

    late List<Tab> tabs;
    late int godkjennIdx;
    late int teamCalIdx;

    if (DriftProClient.isMobile) {
      if (isManager) {
        godkjennIdx = 0;
        teamCalIdx = 2;
        tabs = [
          Tab(text: 'Inn (${_pendingApprovals.length})'),
          const Tab(text: 'Mine'),
          const Tab(text: 'Ansatte'),
        ];
      } else {
        godkjennIdx = -1;
        teamCalIdx = 0;
        tabs = const [
          Tab(icon: Icon(Icons.person_outline, size: 20), text: 'Mine søknader'),
        ];
      }
    } else {
      var idx = 0;
      tabs = <Tab>[
        const Tab(icon: Icon(Icons.dashboard_outlined, size: 20), text: 'Dashboard'),
        const Tab(icon: Icon(Icons.person_outline, size: 20), text: 'Mine'),
      ];
      idx = 2;
      godkjennIdx = -1;
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
      teamCalIdx = idx;
      tabs.add(
        const Tab(
          icon: Icon(Icons.calendar_month_outlined, size: 20),
          text: 'Team & kalender',
        ),
      );
      idx++;
      tabs.add(
        Tab(
          icon: const Icon(Icons.groups_outlined, size: 20),
          text: isManager ? (canAdmin ? 'Ansatte' : 'Mine ansatte') : 'Hjelp',
        ),
      );
    }

    if (_tabController == null || previousLength != tabs.length) {
      _tabController?.removeListener(_onAbsenceTabChanged);
      _tabController?.dispose();
      var initialIndex = previousIndex.clamp(0, tabs.length - 1);
      if (_pendingTabSlug != null) {
        initialIndex = _indexForSlug(_pendingTabSlug, tabs.length);
        _pendingTabSlug = null;
      } else if (DriftProClient.isMobile &&
          isManager &&
          _pendingApprovals.isNotEmpty) {
        initialIndex = 0;
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
    if (DriftProClient.isMobile) {
      if (isManager) {
        return [
          _pullRefreshTab(_buildHandlingTab(isDark)),
          _pullRefreshTab(_buildMineTab(isDark, isManager)),
          _pullRefreshTab(_buildTeamCalendarTab(isDark, isManager)),
        ];
      }
      return [_pullRefreshTab(_buildMineTab(isDark, isManager))];
    }
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

    final allAbsences = await SupabaseService.fetchAbsences(
      companyId: profile.companyId,
    );
    final mine = allAbsences.where((a) => a.userId == profile.id).toList();
    final scoped = _scopeAbsences(profile, allAbsences);
    final pending = _canManageTeamLeave
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
        _canManageTeamLeave,
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
      var profile = _profile ?? AccessSessionCache.profile;
      if (profile == null || (profile.companyId ?? '').isEmpty) {
        profile = await SupabaseService.fetchCurrentUserProfile();
      }
      if (profile == null || (profile.companyId ?? '').isEmpty) {
        profile = await SupabaseService.fetchEffectiveUserProfile();
      }
      if (profile == null || profile.companyId == null) {
        setState(() => _loadError =
            'Profilen er ikke koblet til et selskap — data fra Supabase vises ikke. '
            'Logg ut, logg inn på nytt, eller kjør ensure_internal_profile_missing.sql i Supabase.');
        return;
      }
      final loaded = profile;

      if (_tabController == null) {
        _seedFromProfile(loaded);
        if (mounted) setState(() {});
      }
      _profile = loaded;
      final companyId = loaded.companyId!;

      final results = await Future.wait([
        SupabaseService.fetchAbsences(companyId: companyId),
        SupabaseService.fetchCompanyLeaveSettings(companyId),
        SupabaseService.fetchDepartments(companyId: companyId),
        DepartmentLeaderScope.ledDepartmentIds(loaded.id),
      ]);

      final allAbsences = results[0] as List<Absence>;
      final mine =
          allAbsences.where((a) => a.userId == loaded.id).toList();
      final depts = results[2] as List<Department>;
      final led = results[3] as Set<String>;
      final managed = <String>{...led};
      for (final d in depts) {
        if (d.leaderId == loaded.id || d.leaderIds.contains(loaded.id)) {
          managed.add(d.id);
        }
      }
      if (loaded.role == UserRole.leder &&
          loaded.departmentId != null &&
          loaded.departmentId!.isNotEmpty) {
        managed.add(loaded.departmentId!);
      }
      _managedDepartmentIds = managed;
      _canManageTeamLeave = _manageTeamSync(loaded) || managed.isNotEmpty;
      final scoped = _scopeAbsences(loaded, allAbsences);
      final pending = _canManageTeamLeave
          ? scoped
              .where((a) =>
                  a.status == AbsenceStatus.ventende && a.userId != loaded.id)
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
        _companySettings = results[1] as CompanyLeaveSettings;
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
            _canManageTeamLeave,
            loaded.isAdmin && loaded.access.canVacationAdmin,
          );
          // Viktig: ikke la saldo/team blokkere hele siden (fanene viste bare spinner).
          _isLoading = false;
        });
      }

      await Future.wait([
        _loadSaldo(loaded),
        _loadTeamOverview(loaded),
      ]);
      _startAbsenceRealtime(companyId);
    } catch (e) {
      debugPrint('Error loading absence data: $e');
      setState(() => _loadError = 'Kunne ikke laste fravær: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Absence> _scopeAbsences(UserProfile profile, List<Absence> all) {
    if (profile.isAdmin || CompanyPrincipal.isPrincipal(profile)) return all;
    if (_canManageTeamLeave) {
      return all
          .where((a) => DepartmentLeaderScope.absenceInScope(
                a,
                profile,
                _managedDepartmentIds,
              ))
          .toList();
    }
    return all
        .where((a) =>
            a.userId == profile.id ||
            (profile.departmentId != null &&
                a.departmentId == profile.departmentId &&
                a.status != AbsenceStatus.avvist))
        .toList();
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
        includePending: true,
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
    if (!_canManageTeamLeave) {
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
    final allProfiles = await SupabaseService.fetchProfiles(
      companyId: profile.companyId,
    );
    final deptIds = _managedDepartmentIds.isNotEmpty
        ? _managedDepartmentIds
        : (profile.departmentId != null ? {profile.departmentId!} : <String>{});
    final scopedProfiles = profile.access.dataScopeCompany
        ? allProfiles.where((p) => !p.isPartnerPortalUser).toList()
        : allProfiles
            .where((p) =>
                p.departmentId != null &&
                deptIds.contains(p.departmentId) &&
                !p.isPartnerPortalUser)
            .toList();
    final quotas = await SupabaseService.fetchAbsenceQuotasForCompanyRange(
      companyId: profile.companyId!,
      fromYear: _selectedYear - 1,
      toYear: _selectedYear,
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

  Future<void> _showAbsenceTypeDetail(AbsenceType type, bool isDark) async {
    final items = _myAbsences
        .where((a) => a.type == type)
        .toList()
      ..sort((a, b) => b.startDate.compareTo(a.startDate));
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final df = DateFormat('dd.MM.yyyy');
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.35,
          maxChildSize: 0.9,
          builder: (_, scroll) {
            if (items.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Ingen registrerte ${type.label.toLowerCase()}-saker ennå.',
                  style: DriftProTheme.bodyMd,
                ),
              );
            }
            return ListView.builder(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: items.length + 1,
              itemBuilder: (_, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      type.label,
                      style: DriftProTheme.headingSm,
                    ),
                  );
                }
                final a = items[i - 1];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    onTap: () {
                      Navigator.pop(ctx);
                      _openAbsenceDetail(a, _days(a));
                    },
                    title: Text(
                      '${df.format(a.startDate)} – ${df.format(a.endDate)} · ${_days(a)} d',
                    ),
                    subtitle: Text(
                      [
                        a.status.label,
                        if ((a.comment ?? '').trim().isNotEmpty) a.comment!.trim(),
                      ].join(' · '),
                    ),
                    trailing: Icon(_iconForType(a.type), color: _colorForType(a.type)),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_profile == null || _tabController == null || _tabs.isEmpty) {
      if (_isLoading) {
        return MobileShellScaffold(
          title: 'Fravær & Ferie',
          hideMobileTitleBar: DriftProClient.isMobile,
          backgroundColor: DriftProTheme.surfaceLight,
          body: const DriftProLoadingCenter(),
        );
      }
    }

    if (_tabController == null || _tabs.isEmpty) {
      final msg = _loadError ??
          (_profile != null ? 'Kunne ikke laste innhold på fraværssiden.' : 'Fant ikke pålogget bruker eller bedrift.');
      return MobileShellScaffold(
        title: 'Fravær & Ferie',
        hideMobileTitleBar: DriftProClient.isMobile,
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
    final isManager = _canManageTeamLeave;
    final canAdmin = profile.isAdmin && profile.access.canVacationAdmin;

    return PermissionGuard(
      profile: _profile,
      accessKey: AccessKeys.fravaer,
      child: MobileShellScaffold(
      title: 'Fravær & Ferie',
      hideMobileTitleBar: DriftProClient.isMobile,
      actions: [
          if (isManager)
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
          if (!DriftProClient.isMobile)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadAllData,
              tooltip: 'Oppdater',
            ),
        ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(58),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A2420) : const Color(0xFFE2EDE6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? DriftProTheme.dividerDark
                    : DriftProTheme.primaryGreen.withValues(alpha: 0.18),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              padding: const EdgeInsets.all(5),
              indicatorPadding: const EdgeInsets.symmetric(vertical: 2),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              indicator: BoxDecoration(
                color: DriftProTheme.primaryGreen.withValues(
                  alpha: isDark ? 0.32 : 0.16,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: DriftProTheme.primaryGreen.withValues(alpha: 0.55),
                  width: 1.5,
                ),
              ),
              labelColor: DriftProTheme.primaryGreen,
              unselectedLabelColor:
                  isDark ? Colors.white70 : const Color(0xFF3D5248),
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              tabs: _tabs,
            ),
          ),
        ),
      ),
      backgroundColor:
          isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      floatingActionButton: access?.canFravaer != false
            ? FloatingActionButton.extended(
                onPressed: () => _showRegisterOptions(context),
                icon: const Icon(Icons.add_task),
                label: Text(
                  DriftProClient.isMobile ? 'Ny søknad' : 'Ny registrering',
                ),
              )
            : null,
      body: DriftProTabView(
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
    final canAdmin =
        _profile?.isAdmin == true && _profile?.access.canVacationAdmin == true;

    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Oversikt',
                  style: DriftProTheme.headingSm.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              DropdownButton<int>(
                value: _selectedYear,
                underline: const SizedBox.shrink(),
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
          const SizedBox(height: 4),
          Text(
            'Restferie, saldo og hva som skjer ved årsskifte — enkelt forklart.',
            style: DriftProTheme.caption,
          ),
          const SizedBox(height: 12),
          LeaveQuickActions(
            onTypeSelected: (t) => _openNewRequest(t),
            egenmeldingBlocked: _egenmeldingBlockedForSelf,
            ferieHint: _quota == null
                ? null
                : '${_quota!.vacationDaysRemaining} virkedager igjen',
            egenmeldingHint: _periodUsage == null
                ? null
                : '${(_companySettings.effectiveEgenmeldingDaysPerYear - _periodUsage!.egenmeldingDaysUsed).clamp(0, 99)} dager · '
                    '${(LeaveRules.egenmeldingMaxPeriodsPerYear - _periodUsage!.egenmeldingPeriodsUsed).clamp(0, 9)} tilfeller',
            syktBarnHint: () {
              final kids = _profile?.childrenUnder12Count ?? 0;
              final limit = _companySettings.syktBarnDaysLimit(
                childrenUnder12: kids,
              );
              final used = _periodUsage?.syktBarnDaysUsed ?? 0;
              final left = (limit - used).clamp(0, limit);
              return '$left/$limit dager · ${kids == 0 ? 'ingen barn under 12' : '$kids barn under 12'}';
            }(),
            onEgenmeldingBlocked: () {
              if (_periodUsage == null) return;
              showLeaveEgenmeldingBlockedSheet(
                context,
                periodUsage: _periodUsage!,
                maxDays: _companySettings.effectiveEgenmeldingDaysPerYear,
                onChooseAlternative: _openNewRequest,
              );
            },
          ),
          const SizedBox(height: 14),
          if (isManager && _pendingApprovals.isNotEmpty) ...[
            _actionBanner(
              isDark,
              icon: Icons.fact_check_outlined,
              color: DriftProTheme.warning,
              title: '${_pendingApprovals.length} søknader venter',
              subtitle: 'Godkjenn eller avvis under Godkjenn',
              onTap: () => _goToTab(_godkjennTabIndex),
            ),
            const SizedBox(height: 10),
          ],
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
            onOpenAdminCarryover: canAdmin ? _openVacationAdmin : null,
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
          if (todayOut.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              'Borte i dag (${todayOut.length})',
              style: DriftProTheme.labelLg.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            ...todayOut.take(6).map((a) => _absenceListTile(a, isDark)),
          ],
          if (isManager) ...[
            const SizedBox(height: 14),
            _actionBanner(
              isDark,
              icon: Icons.calendar_month_outlined,
              color: DriftProTheme.absenceVacation,
              title: 'Team & kalender',
              subtitle: 'Ansatte, restferie og ferie-/fraværskalender',
              onTap: () => _goToTab(_teamCalendarTabIndex),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openVacationAdmin() async {
    if (_profile?.companyId == null) return;
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

  Widget _pullRefreshTab(Widget child) {
    return MobilePullRefresh(onRefresh: _loadAllData, child: child);
  }

  DateTime _calDay(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _matchesMineFilter(Absence a) {
    switch (_mineTypeFilter) {
      case _MineTypeFilter.alle:
        return true;
      case _MineTypeFilter.ferie:
        return a.type == AbsenceType.ferie;
      case _MineTypeFilter.egenmelding:
        return a.type == AbsenceType.egenmelding;
      case _MineTypeFilter.syktBarn:
        return a.type == AbsenceType.syktBarn;
      case _MineTypeFilter.annet:
        return a.type != AbsenceType.ferie &&
            a.type != AbsenceType.egenmelding &&
            a.type != AbsenceType.syktBarn;
    }
  }

  Widget _buildMineTab(bool isDark, bool isManager) {
    if (_isLoading && _myAbsences.isEmpty) {
      return const DriftProLoadingCenter();
    }
    final today = _calDay(DateTime.now());
    final filtered = _myAbsences.where(_matchesMineFilter).toList();

    bool ongoing(Absence a) =>
        a.status == AbsenceStatus.godkjent &&
        !_calDay(a.startDate).isAfter(today) &&
        !_calDay(a.endDate).isBefore(today);
    bool upcoming(Absence a) =>
        a.status == AbsenceStatus.godkjent && _calDay(a.startDate).isAfter(today);
    bool pending(Absence a) => a.status == AbsenceStatus.ventende;
    bool past(Absence a) =>
        a.status == AbsenceStatus.avvist ||
        (a.status == AbsenceStatus.godkjent && _calDay(a.endDate).isBefore(today));

    final nowList = filtered.where(ongoing).toList()
      ..sort((a, b) => a.endDate.compareTo(b.endDate));
    final nextList = filtered.where(upcoming).toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    final waitList = filtered.where(pending).toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    final pastList = filtered.where(past).toList()
      ..sort((a, b) => b.startDate.compareTo(a.startDate));

    final childrenCount = _profile?.childrenUnder12Count ?? 0;
    final syktLimit = _companySettings.syktBarnDaysLimit(
      childrenUnder12: childrenCount,
    );
    final ferieLeft = _quota?.vacationDaysRemaining;
    final next = nextList.isEmpty ? null : nextList.first;
    final daysUntilNext = next == null
        ? null
        : _calDay(next.startDate).difference(today).inDays;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.all(16),
      children: [
        Text('Ferie og fravær', style: DriftProTheme.headingSm),
        const SizedBox(height: 4),
        Text(
          isManager
              ? 'Din egen tidslinje. Ansatte ligger under Mine ansatte / Inkommende.'
              : 'Kommende, pågående og tidligere — samlet på ett sted.',
          style: DriftProTheme.caption,
        ),
        const SizedBox(height: 12),
        _LeaveInsightBanner(
          nowCount: nowList.length,
          next: next,
          daysUntilNext: daysUntilNext,
          ferieLeft: ferieLeft,
          pendingCount: waitList.length,
        ),
        const SizedBox(height: 14),
        if (_periodUsage != null) ...[
          LeaveUsageMeter(
            title: 'Egenmelding',
            used: _periodUsage!.egenmeldingDaysUsed,
            max: _companySettings.effectiveEgenmeldingDaysPerYear,
            metricLabel: '${_periodUsage!.egenmeldingDaysUsed} dager',
            secondaryUsed: _periodUsage!.egenmeldingPeriodsUsed,
            secondaryMax: LeaveRules.egenmeldingMaxPeriodsPerYear,
            secondaryMetricLabel:
                '${_periodUsage!.egenmeldingPeriodsUsed}/${LeaveRules.egenmeldingMaxPeriodsPerYear}',
            secondaryRemainingLabel:
                '${(LeaveRules.egenmeldingMaxPeriodsPerYear - _periodUsage!.egenmeldingPeriodsUsed).clamp(0, LeaveRules.egenmeldingMaxPeriodsPerYear)} tilfeller igjen',
            subtitle:
                '${_periodUsage!.window.formatRange()} · '
                'Maks ${LeaveRules.egenmeldingMaxPeriodsPerYear} tilfeller × '
                '${_companySettings.effectiveEgenmeldingConsecutiveMax} dager',
            icon: Icons.sick_outlined,
            onTap: () => _showAbsenceTypeDetail(
              AbsenceType.egenmelding,
              isDark,
            ),
          ),
          const SizedBox(height: 10),
          LeaveUsageMeter(
            title: 'Sykt barn',
            used: _periodUsage!.syktBarnDaysUsed,
            max: syktLimit,
            metricLabel:
                '${_periodUsage!.syktBarnDaysUsed}/$syktLimit dager',
            subtitle: childrenCount >= 2
                ? '${_periodUsage!.window.formatRange()} · $childrenCount barn — 15 dager (2+ barn)'
                : childrenCount == 1
                    ? '${_periodUsage!.window.formatRange()} · 1 barn — 10 dager'
                    : '${_periodUsage!.window.formatRange()} · Registrer antall barn under Profil',
            icon: Icons.child_care_rounded,
            onTap: () => _showAbsenceTypeDetail(
              AbsenceType.syktBarn,
              isDark,
            ),
          ),
          if (_quota != null) ...[
            const SizedBox(height: 10),
            LeaveUsageMeter(
              title: 'Ferie ${_quota!.year}',
              used: _quota!.vacationDaysUsed,
              max: _quota!.totalVacationDays,
              metricLabel:
                  '${_quota!.vacationDaysUsed}/${_quota!.totalVacationDays} dager',
              subtitle: '${_quota!.vacationDaysRemaining} dager igjen',
              icon: Icons.beach_access_outlined,
              onTap: () => _showAbsenceTypeDetail(
                AbsenceType.ferie,
                isDark,
              ),
            ),
          ],
          const SizedBox(height: 16),
        ],
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _MineTypeFilter.values.map((f) {
              final selected = _mineTypeFilter == f;
              final label = switch (f) {
                _MineTypeFilter.alle => 'Alle',
                _MineTypeFilter.ferie => 'Ferie',
                _MineTypeFilter.egenmelding => 'Egenmelding',
                _MineTypeFilter.syktBarn => 'Sykt barn',
                _MineTypeFilter.annet => 'Annet',
              };
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text(label),
                  selected: selected,
                  onSelected: (_) => setState(() => _mineTypeFilter = f),
                  selectedColor:
                      DriftProTheme.primaryGreen.withValues(alpha: 0.15),
                  checkmarkColor: DriftProTheme.primaryGreen,
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Column(
              children: [
                Icon(Icons.event_available, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 10),
                Text(
                  _myAbsences.isEmpty
                      ? 'Ingen søknader ennå'
                      : 'Ingen treff med valgt filter',
                  style: DriftProTheme.headingSm,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  'Bruk «Ny søknad» for ferie eller fravær.',
                  style: DriftProTheme.bodySm,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else ...[
          if (nowList.isNotEmpty)
            _leaveSection('Nå', nowList, isDark),
          if (nextList.isNotEmpty)
            _leaveSection('Kommende', nextList, isDark),
          if (waitList.isNotEmpty)
            _leaveSection('Venter på svar', waitList, isDark),
          if (pastList.isNotEmpty)
            _leaveSection('Tidligere', pastList.take(12).toList(), isDark),
        ],
        SizedBox(height: DriftProClient.isMobile ? 88 : 24),
      ],
    );
  }

  Widget _leaveSection(
    String title,
    List<Absence> items,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: DriftProTheme.labelSm),
              const SizedBox(width: 8),
              if (items.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '${items.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: DriftProTheme.primaryGreen,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ...items.map((a) => _buildAbsenceCard(a, _days(a), isDark)),
        ],
      ),
    );
  }

  /// Superadmin/admin/ferie-admin, eller avd.leder for egne ansatte (ikke seg selv).
  bool _canEditLeaveFor(UserProfile target) {
    final me = _profile;
    if (me == null) return false;
    if (me.role == UserRole.leder && target.id == me.id) return false;
    if (me.role == UserRole.superadmin ||
        me.isAdmin ||
        me.access.canVacationAdmin ||
        me.access.canRegisterLeaveForOthers) {
      return true;
    }
    if (me.role == UserRole.leder) {
      if (target.id == me.id) return false;
      if (me.departmentId != null && target.departmentId == me.departmentId) {
        return true;
      }
      return _managedDepartmentIds.contains(target.departmentId);
    }
    return false;
  }

  bool _canRegisterLeaveFor(UserProfile target) {
    final me = _profile;
    if (me == null) return false;
    if (me.access.canFravaer == false) return false;
    if (target.id == me.id) {
      // Avd.leder skal ikke registrere egen ferie/fravær herfra.
      return me.role != UserRole.leder;
    }
    return _canEditLeaveFor(target);
  }

  AbsenceQuota? _quotaForUser(String userId, {int? year}) {
    final y = year ?? _selectedYear;
    for (final q in _teamQuotas) {
      if (q.userId == userId && q.year == y) return q;
    }
    return null;
  }

  Future<void> _openEmployeeLeavePage(UserProfile employee) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LeaveEmployeeDetailScreen(
          employee: employee,
          quotaOf: () => _quotaForUser(employee.id),
          company: _companySettings,
          selectedYear: _selectedYear,
          absencesOf: () =>
              _scopedAbsences.where((a) => a.userId == employee.id).toList(),
          departmentNames: _departmentNames,
          canRegister: _canRegisterLeaveFor(employee),
          canEditQuota: _canEditLeaveFor(employee),
          onEditQuota: _canEditLeaveFor(employee)
              ? () => _editTeamQuota(employee, _quotaForUser(employee.id))
              : null,
          onAbsenceTap: (a) =>
              _openAbsenceDetail(a, _days(a), managerView: true),
          onChanged: _loadAllData,
        ),
      ),
    );
    if (mounted) await _loadAllData();
  }

  Widget _buildTeamCalendarTab(bool isDark, bool isManager) {
    if (isManager) {
      return LeaveTeamEmployeesHub(
        teamProfiles: _teamProfiles,
        scopedAbsences: _scopedAbsences,
        teamQuotas: _teamQuotas,
        companySettings: _companySettings,
        selectedYear: _selectedYear,
        departmentNames: _departmentNames,
        leaderProfile: _profile,
        month: _calendarMonth,
        onMonthChanged: (m) {
          setState(() => _calendarMonth = m);
          if (m.year != _selectedYear && _profile != null) {
            _selectedYear = m.year;
            _loadTeamOverview(_profile!);
            _loadSaldo(_profile!);
          }
        },
        onRefresh: _loadAllData,
        colorForType: _colorForType,
        iconForType: _iconForType,
        daysFor: _days,
        onAbsenceTap: (a) => _openAbsenceDetail(a, _days(a), managerView: true),
        onApprove: (a) => _updateStatus(a.id, AbsenceStatus.godkjent),
        onReject: (a) => _updateStatus(a.id, AbsenceStatus.avvist),
        canEditQuota: true,
        canEditQuotaFor: _canEditLeaveFor,
        onEditQuota: _editTeamQuota,
        onOpenEmployee: _openEmployeeLeavePage,
        onDayTap: _onCalendarDayTap,
      );
    }
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
      maxDays: _companySettings.effectiveEgenmeldingDaysPerYear,
    );
  }

  void _openNewRequest(AbsenceType type, {UserProfile? lockedEmployee}) {
    final profile = _profile;
    if (lockedEmployee == null &&
        type == AbsenceType.egenmelding &&
        _egenmeldingBlockedForSelf) {
      showLeaveEgenmeldingBlockedSheet(
        context,
        periodUsage: _periodUsage!,
        maxDays: _companySettings.effectiveEgenmeldingDaysPerYear,
        onChooseAlternative: _openNewRequest,
      );
      return;
    }
    final allowPick = lockedEmployee == null &&
        profile != null &&
        (profile.access.canRegisterLeaveForOthers || profile.isAdmin);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NewAbsenceScreen(
          type: type,
          allowPickEmployee: allowPick,
          lockedEmployee: lockedEmployee,
        ),
      ),
    ).then((v) {
      if (v == true) _loadAllData();
    });
  }

  Widget _buildHandlingTab(bool isDark) {
    if (_isLoading && _pendingApprovals.isEmpty && _scopedAbsences.isEmpty) {
      return const DriftProLoadingCenter();
    }
    if (_pendingApprovals.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.25),
          Center(child: Text('Ingen ventende forespørsler.', style: DriftProTheme.bodyMd.copyWith(color: Colors.grey))),
        ],
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
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
          (a) => _buildAbsenceCard(a, _days(a), isDark, showActions: true, managerView: true),
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
                    (a) {
                      final pending = a.status == AbsenceStatus.ventende;
                      return ListTile(
                        leading: Icon(
                          _iconForType(a.type),
                          color: pending
                              ? Colors.orange.shade700
                              : _colorForType(a.type),
                        ),
                        title: Text(a.userName ?? 'Ansatt'),
                        subtitle: Text(
                          '${a.type.label} · ${_days(a)} dager · ${a.status.label}',
                        ),
                        trailing: pending
                            ? const Text(
                                'Behandle',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: DriftProTheme.primaryGreen,
                                ),
                              )
                            : const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.pop(ctx);
                          _openAbsenceDetail(
                            a,
                            _days(a),
                            managerView: true,
                          );
                        },
                      );
                    },
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

  Future<void> _openRegisterForDate(DateTime date) async {
    final type = await showLeaveTypePickerSheet(
      context,
      egenmeldingBlocked: _egenmeldingBlockedForSelf,
      onEgenmeldingBlocked: () {
        if (_periodUsage == null) return;
        showLeaveEgenmeldingBlockedSheet(
          context,
          periodUsage: _periodUsage!,
          maxDays: _companySettings.effectiveEgenmeldingDaysPerYear,
          onChooseAlternative: _openNewRequest,
        );
      },
    );
    if (type == null || !mounted) return;
    final allowPick = _profile != null &&
        (_profile!.access.canRegisterLeaveForOthers || _profile!.isAdmin);
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NewAbsenceScreen(
          type: type,
          initialStart: date,
          initialEnd: date,
          allowPickEmployee: allowPick,
        ),
      ),
    );
    if (saved == true) _loadAllData();
  }

  Widget _buildRulesTab(bool isDark) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _InfoBox(
          title: 'Slik fungerer søknader',
          body:
              'Når du søker ferie eller fravær, får leder beskjed. '
              'Du ser status under Mine søknader, og får varsel når saken er behandlet.',
        ),
        const SizedBox(height: 12),
        _InfoBox(
          title: 'Egenmelding',
          body:
              'Du kan søke egenmelding i inntil '
              '${LeaveRules.egenmeldingMaxConsecutiveDays} dager om gangen '
              '(maks ${LeaveRules.egenmeldingMaxPeriodsPerYear} tilfeller · '
              '${LeaveRules.egenmeldingMaxDaysPerYear} dager totalt). '
              'Bruken vises i oversikten med farge fra gull til rødt etter hvert som kvoten fylles.',
        ),
        const SizedBox(height: 12),
        const _InfoBox(
          title: 'Ferie',
          body:
              'Feriedager trekkes fra kvoten når søknaden godkjennes. '
              'Sjekk saldoen din i oversikten før du søker.',
        ),
      ],
    );
  }

  Widget _buildTeamTab(bool isDark, bool canAdmin) {
    final canDistribute = canAdmin ||
        _profile?.access.canVacationAdmin == true ||
        _profile?.role == UserRole.superadmin;
    return Column(
      children: [
        if (canDistribute)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () async {
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
                        icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                        label: const Text('Del ut ferie + restferie'),
                        style: FilledButton.styleFrom(
                          backgroundColor: DriftProTheme.primaryGreen,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
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
                        icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                        label: Text('Restferie ${_selectedYear - 1}'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: DriftProTheme.primaryGreen,
                          side: BorderSide(
                            color: DriftProTheme.primaryGreen.withValues(
                              alpha: 0.5,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Åpne ferieadministrasjon for å dele ut nytt år med restferie '
                  'fra året før — systemet husker ubrukte dager per ansatt.',
                  style: DriftProTheme.caption,
                ),
              ],
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
              onYearChanged: (y) {
                setState(() => _selectedYear = y);
                if (_profile != null) {
                  _loadTeamOverview(_profile!);
                  _loadSaldo(_profile!);
                }
              },
              canEdit: canAdmin ||
                  _profile?.role == UserRole.leder ||
                  _profile?.access.canRegisterLeaveForOthers == true,
              onEditQuota: (u, q) {
                if (!_canEditLeaveFor(u)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Du kan ikke endre kvote for denne ansatte.',
                      ),
                    ),
                  );
                  return;
                }
                _editTeamQuota(u, q);
              },
              onTapEmployee: _openEmployeeLeavePage,
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

  Future<void> _openAbsenceDetail(Absence a, int days, {bool managerView = false}) async {
    final profile = _profile;
    if (profile == null) return;
    final changed = await showAbsenceDetailSheet(
      context,
      absence: a,
      profile: profile,
      days: days,
      onChanged: _softRefreshAbsences,
      onDeleted: _removeLocalAbsence,
      onDecide: managerView
          ? (id, status, {decisionComment}) =>
              _updateStatus(id, status, decisionComment: decisionComment)
          : null,
    );
    if (changed == true) {
      await _softRefreshAbsences();
    }
  }

  Widget _buildAbsenceCard(
    Absence a,
    int days,
    bool isDark, {
    bool showActions = false,
    bool managerView = false,
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
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _openAbsenceDetail(a, days, managerView: managerView),
              child: _absenceListTile(a, isDark, days: days, color: color),
            ),
          ),
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
          if (a.decisionComment != null && a.decisionComment!.trim().isNotEmpty)
            Text(
              'Svar: ${a.decisionComment!.trim()}',
              style: DriftProTheme.bodySm.copyWith(fontStyle: FontStyle.italic),
            ),
          if (a.comment != null)
            Text('"${a.comment!}"', style: DriftProTheme.bodySm.copyWith(fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  Future<void> _updateStatus(
    String id,
    AbsenceStatus status, {
    String? decisionComment,
  }) async {
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

    // Oppdater kalender/lister med en gang — ikke vent på nettverk.
    _patchLocalAbsenceStatus(
      id,
      status,
      decisionComment: decisionComment,
    );

    try {
      await SupabaseService.updateAbsenceStatus(
        id,
        status,
        decisionComment: decisionComment,
      );
      await _softRefreshAbsences();
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
      // Rull tilbake ved feil.
      await _softRefreshAbsences();
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

  Future<void> _showRegisterOptions(BuildContext context) async {
    final type = await showLeaveTypePickerSheet(
      context,
      egenmeldingBlocked: _egenmeldingBlockedForSelf,
      onEgenmeldingBlocked: () {
        if (_periodUsage == null) return;
        showLeaveEgenmeldingBlockedSheet(
          context,
          periodUsage: _periodUsage!,
          maxDays: _companySettings.effectiveEgenmeldingDaysPerYear,
          onChooseAlternative: _openNewRequest,
        );
      },
    );
    if (type == null || !mounted) return;
    _openNewRequest(type);
  }

  Widget _empty(String msg) => Center(child: Text(msg, style: DriftProTheme.bodyMd.copyWith(color: Colors.grey)));
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

class _LeaveInsightBanner extends StatelessWidget {
  const _LeaveInsightBanner({
    required this.nowCount,
    required this.next,
    required this.daysUntilNext,
    required this.ferieLeft,
    required this.pendingCount,
  });

  final int nowCount;
  final Absence? next;
  final int? daysUntilNext;
  final int? ferieLeft;
  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd.MM');
    String headline;
    String detail;
    IconData icon;
    Color tint;
    if (nowCount > 0) {
      headline = 'Du er borte nå';
      detail = nowCount == 1
          ? 'Ett godkjent fravær pågår.'
          : '$nowCount godkjente fravær pågår.';
      icon = Icons.event_busy_outlined;
      tint = const Color(0xFFE65100);
    } else if (next != null && daysUntilNext != null) {
      headline = daysUntilNext == 0
          ? 'Starter i dag'
          : daysUntilNext == 1
              ? 'Neste fravær i morgen'
              : 'Neste om $daysUntilNext dager';
      detail =
          '${next!.type.label} · ${df.format(next!.startDate)}–${df.format(next!.endDate)}';
      icon = Icons.event_available_outlined;
      tint = DriftProTheme.primaryGreen;
    } else {
      headline = 'Ingen planlagt fravær';
      detail = ferieLeft == null
          ? 'Søk ferie når du vet datoene.'
          : '$ferieLeft feriedager igjen i år.';
      icon = Icons.beach_access_outlined;
      tint = DriftProTheme.primaryGreen;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tint.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: tint),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: tint,
                  ),
                ),
                const SizedBox(height: 2),
                Text(detail, style: DriftProTheme.bodySm),
                if (pendingCount > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    '$pendingCount søknad${pendingCount == 1 ? '' : 'er'} venter på svar',
                    style: DriftProTheme.caption,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
