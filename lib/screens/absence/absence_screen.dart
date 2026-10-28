import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/routing/app_paths.dart';
import '../../core/layout/mobile_shell_scaffold.dart';
import '../../core/routing/route_url_sync.dart';

import '../../core/config/driftpro_client.dart';
import '../../core/constants/company_principals.dart';
import '../../core/constants/leave_rules.dart';
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
import 'widgets/manager_leave/manager_leave_overview.dart';
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
  _MineTypeFilter _mineTypeFilter = _MineTypeFilter.alle;

  List<Absence> _myAbsences = [];
  List<Absence> _scopedAbsences = [];
  List<Absence> _pendingApprovals = [];
  Map<String, List<DepartmentLeaveOverlap>> _approvalOverlaps = {};
  Map<String, String> _departmentNames = {};
  AbsenceQuota? _quota;
  LeavePeriodUsage? _periodUsage;
  CompanyLeaveSettings _companySettings = const CompanyLeaveSettings();
  UserProfile? _profile;
  bool _isLoading = true;
  String? _loadError;
  int _selectedYear = DateTime.now().year;
  List<UserProfile> _teamProfiles = [];
  List<AbsenceQuota> _teamQuotas = [];
  Set<String> _managedDepartmentIds = {};
  bool _canManageTeamLeave = false;
  String? _pendingTabSlug;
  /// Ledere: valgfri «Mine søknader»-visning utenfor hovedoversikten.
  bool _managerShowMine = false;

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
    });
  }

  void _removeLocalAbsence(String id) {
    setState(() {
      _scopedAbsences = _scopedAbsences.where((a) => a.id != id).toList();
      _myAbsences = _myAbsences.where((a) => a.id != id).toList();
      _pendingApprovals.removeWhere((a) => a.id == id);
      _approvalOverlaps.remove(id);
    });
  }

  void _syncAbsenceUrl(bool isManager) {
    if (!mounted) return;
    if (isManager) {
      RouteUrlSync.goIfChanged(
        context,
        AppPaths.absencePath(tab: _managerShowMine ? 'mine' : null),
      );
      return;
    }
    if (_tabController == null) return;
    RouteUrlSync.goIfChanged(
      context,
      AppPaths.absencePath(tab: 'mine'),
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
    // Ledere: én ren oversikt uten faner (kalender-rutenett fjernet).
    if (isManager) {
      _tabController?.removeListener(_onAbsenceTabChanged);
      _tabController?.dispose();
      _tabController = null;
      _tabs = [];
      if (_pendingTabSlug == 'mine') {
        _managerShowMine = true;
      }
      _pendingTabSlug = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncAbsenceUrl(true);
      });
      return;
    }

    final previousIndex = _tabController?.index ?? 0;
    final previousLength = _tabController?.length ?? 0;

    const tabs = <Tab>[
      Tab(icon: Icon(Icons.person_outline, size: 20), text: 'Mine søknader'),
    ];

    if (_tabController == null || previousLength != tabs.length) {
      _tabController?.removeListener(_onAbsenceTabChanged);
      _tabController?.dispose();
      var initialIndex = previousIndex.clamp(0, tabs.length - 1);
      if (_pendingTabSlug != null) {
        initialIndex = 0;
        _pendingTabSlug = null;
      }
      _tabController = TabController(
        length: tabs.length,
        vsync: this,
        initialIndex: initialIndex,
      )..addListener(_onAbsenceTabChanged);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _tabController == null) return;
        _syncAbsenceUrl(false);
      });
    }

    _tabs = tabs;
  }

  List<Widget> _buildTabBodies(bool isDark, bool isManager, bool canAdmin) {
    return [_pullRefreshTab(_buildMineTab(isDark, isManager))];
  }

  Widget _buildManagerOverview(bool isDark) {
    final canAdmin =
        _profile?.isAdmin == true && _profile?.access.canVacationAdmin == true;
    return ManagerLeaveOverview(
      teamProfiles: _teamProfiles,
      scopedAbsences: _scopedAbsences,
      pendingApprovals: _pendingApprovals,
      teamQuotas: _teamQuotas,
      departmentNames: _departmentNames,
      leaderProfile: _profile,
      selectedYear: _selectedYear,
      isLoading: _isLoading,
      companySettings: _companySettings,
      approverNames: _approverNamesById,
      onRefresh: _loadAllData,
      onRegister: () => _showRegisterOptions(context),
      onApprove: (a) => _updateStatus(a.id, AbsenceStatus.godkjent),
      onReject: (a, {decisionComment}) => _updateStatus(
        a.id,
        AbsenceStatus.avvist,
        decisionComment: decisionComment,
      ),
      onOpenAbsence: (a) =>
          _openAbsenceDetail(a, _days(a), managerView: true),
      onOpenEmployee: _openEmployeeLeavePage,
      onYearChanged: (y) {
        setState(() => _selectedYear = y);
        if (_profile != null) {
          _loadTeamOverview(_profile!);
          _loadSaldo(_profile!);
        }
      },
      onOpenMine: () {
        setState(() => _managerShowMine = true);
        _syncAbsenceUrl(true);
      },
      onOpenVacationAdmin: canAdmin ||
              _profile?.access.canVacationAdmin == true ||
              _profile?.role == UserRole.superadmin
          ? _openVacationAdmin
          : null,
    );
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
    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    setState(() {
      _myAbsences = mine;
      _scopedAbsences = scoped;
      _pendingApprovals = pending;
      _approvalOverlaps = overlaps;
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
      setState(() {
        _myAbsences = mine;
        _scopedAbsences = scoped;
        _companySettings = results[1] as CompanyLeaveSettings;
        _pendingApprovals = pending;
        _approvalOverlaps = overlaps;
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
    } catch (_) {
      if (mounted) {
        setState(() {
          _quota = null;
          _periodUsage = null;
        });
      }
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
    final isManager = _canManageTeamLeave && _profile != null;

    if (_profile == null) {
      if (_isLoading) {
        return MobileShellScaffold(
          title: 'Fravær & Ferie',
          hideMobileTitleBar: DriftProClient.isMobile,
          backgroundColor: DriftProTheme.surfaceLight,
          body: const DriftProLoadingCenter(),
        );
      }
      final msg = _loadError ?? 'Fant ikke pålogget bruker eller bedrift.';
      return MobileShellScaffold(
        title: 'Fravær & Ferie',
        hideMobileTitleBar: DriftProClient.isMobile,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 52, color: DriftProTheme.warning),
                const SizedBox(height: 16),
                Text(msg, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                    onPressed: _loadAllData, child: const Text('Prøv igjen')),
              ],
            ),
          ),
        ),
      );
    }

    if (!isManager && (_tabController == null || _tabs.isEmpty)) {
      if (_isLoading) {
        return MobileShellScaffold(
          title: 'Fravær & Ferie',
          hideMobileTitleBar: DriftProClient.isMobile,
          backgroundColor: DriftProTheme.surfaceLight,
          body: const DriftProLoadingCenter(),
        );
      }
      final msg = _loadError ?? 'Kunne ikke laste innhold på fraværssiden.';
      return MobileShellScaffold(
        title: 'Fravær & Ferie',
        hideMobileTitleBar: DriftProClient.isMobile,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 52, color: DriftProTheme.warning),
                const SizedBox(height: 16),
                Text(msg, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                    onPressed: _loadAllData, child: const Text('Prøv igjen')),
              ],
            ),
          ),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final access = _profile?.access;
    final profile = _profile!;
    final canAdmin = profile.isAdmin && profile.access.canVacationAdmin;

    if (isManager) {
      return PermissionGuard(
        profile: _profile,
        accessKey: AccessKeys.fravaer,
        child: MobileShellScaffold(
          title: 'Fravær & Ferie',
          hideMobileTitleBar: true,
          backgroundColor:
              isDark ? DriftProTheme.surfaceDark : const Color(0xFFF8FAFC),
          body: _managerShowMine
              ? Column(
                  children: [
                    Material(
                      color: isDark
                          ? DriftProTheme.cardDark
                          : Colors.white,
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back_rounded),
                                tooltip: 'Tilbake til oversikt',
                                onPressed: () {
                                  setState(() => _managerShowMine = false);
                                  _syncAbsenceUrl(true);
                                },
                              ),
                              Expanded(
                                child: Text(
                                  'Mine søknader',
                                  style: DriftProTheme.labelLg.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              FilledButton.icon(
                                onPressed: () =>
                                    _showRegisterOptions(context),
                                icon: const Icon(Icons.add_rounded, size: 18),
                                label: const Text('Ny søknad'),
                                style: FilledButton.styleFrom(
                                  backgroundColor:
                                      DriftProTheme.primaryGreen,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(child: _buildMineTab(isDark, true)),
                  ],
                )
              : _buildManagerOverview(isDark),
        ),
      );
    }

    return PermissionGuard(
      profile: _profile,
      accessKey: AccessKeys.fravaer,
      child: MobileShellScaffold(
        title: 'Fravær & Ferie',
        hideMobileTitleBar: DriftProClient.isMobile,
        actions: [
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
                color:
                    isDark ? const Color(0xFF1A2420) : const Color(0xFFE2EDE6),
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
                    color:
                        DriftProTheme.primaryGreen.withValues(alpha: 0.55),
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
          children: _buildTabBodies(isDark, false, canAdmin),
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
              ? 'Din egen tidslinje. Teamet ligger i hovedoversikten.'
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

  Map<String, String> get _approverNamesById => {
        for (final p in _teamProfiles) p.id: p.fullName,
        if (_profile != null) _profile!.id: _profile!.fullName,
      };

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
          onYearChanged: (y) async {
            setState(() => _selectedYear = y);
            if (_profile != null) {
              await _loadTeamOverview(_profile!);
              await _loadSaldo(_profile!);
            }
          },
          teamProfiles: _teamProfiles,
          teamQuotas: _teamQuotas,
          allAbsences: _scopedAbsences,
          approverNames: _approverNamesById,
        ),
      ),
    );
    if (mounted) await _loadAllData();
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
