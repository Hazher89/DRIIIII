import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import '../../core/constants/app_icons.dart';
import '../../core/constants/company_display.dart';
import '../../core/constants/app_strings.dart';
import '../../core/permissions/access_keys.dart';
import '../../core/permissions/permission_gate.dart';
import '../../core/permissions/user_access.dart';
import '../../core/services/supabase_service.dart';
import '../employees/employee_hub_screen.dart';
import '../../core/theme/app_theme.dart';
import '../../models/dashboard_stats.dart';
import '../../models/absence.dart';
import '../../models/ticket.dart';
import '../../models/user_profile.dart';
import '../../models/sja_form.dart';
import '../../models/safety_round.dart';
import '../../models/risk_assessment.dart';
import '../../models/attendance/employee_attendance.dart';
import '../../models/kiosk_settings.dart';
import '../../core/services/attendance/attendance_service.dart';
import '../../core/services/tidsbanken/tidsbanken_presence_service.dart';
import '../../models/tidsbanken_presence.dart';
import '../online/online_presence_screen.dart';
import '../admin/kiosk_settings_screen.dart';
import '../../widgets/cards/stat_card.dart';
import '../../widgets/cards/quick_action_button.dart';
import '../../widgets/cards/glass_card.dart';
import '../../widgets/common/section_header.dart';
import '../profile/profile_screen.dart';
import '../../widgets/driftpro_notification_bell.dart';
import 'widgets/dashboard_command_palette.dart';
import 'widgets/dashboard_personal_panel.dart';
import 'widgets/dashboard_search_bar.dart';
import 'dashboard_search_catalog.dart';

class DashboardScreen extends StatefulWidget {
  final NavigateByAccess? onNavigateByAccess;

  const DashboardScreen({super.key, this.onNavigateByAccess});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  DashboardStats _stats = const DashboardStats();
  UserProfile? _profile;
  List<dynamic> _recentActivity = [];
  List<EmployeeAttendance> _onDutyEmployees = [];
  EmployeeAttendance? _myAttendance;
  bool _isLoading = false;
  int _activeTabIndex = 0;
  _OpsWindow _opsWindow = _OpsWindow.week;
  List<_DashboardNotice> _notices = const [];
  KioskSettings _kiosk = KioskSettings.defaults;
  String? _companyName;
  List<Absence> _scopedAbsences = const [];
  List<Ticket> _scopedTickets = const [];
  TidsbankenSyncState? _tidsbankenSync;
  bool _nbDatesReady = false;
  String? _departmentName;
  int? _vacationDaysLeft;
  int _myPendingAbsences = 0;
  int _myOpenTickets = 0;
  Timer? _clockTimer;
  Timer? _presenceTimer;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    );
    _fadeController.forward();
    _initNbLocale();
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    _presenceTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _refreshTidsbankenPresence();
    });
    _loadAllData();
  }

  Future<void> _initNbLocale() async {
    await initializeDateFormatting('nb_NO');
    if (mounted) setState(() => _nbDatesReady = true);
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _presenceTimer?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  bool get _anonymizeSharedScreen =>
      _kiosk.infoscreenLayoutEnabled && !_kiosk.revealNamesOnInfoscreen;

  double get _kioskFontFactor => _kiosk.infoscreenLayoutEnabled ? 1.14 : 1.0;

  /// Infoskjerm-toggles (skjul hurtigvalg osv.) gjelder kun TV-modus — ikke privat app.
  KioskSettings get _contentKiosk {
    if (_kiosk.infoscreenLayoutEnabled) return _kiosk;
    return KioskSettings.defaults.copyWith(
      showLiveTeamBoard: _kiosk.showLiveTeamBoard,
      showTidsbankenPresence: _kiosk.showTidsbankenPresence,
      showClock: _kiosk.showClock,
    );
  }

  bool get _usePersonalGreeting =>
      !_kiosk.infoscreenLayoutEnabled || _kiosk.showPersonalGreeting;

  UserAccess? get _access => _profile?.access;

  void _go(String accessKey) => widget.onNavigateByAccess?.call(accessKey);

  Future<void> _refreshTidsbankenPresence() async {
    if (!_kiosk.showLiveTeamBoard || !_kiosk.showTidsbankenPresence) return;
    try {
      final companyId = await SupabaseService.getCurrentCompanyId();
      if (companyId == null) return;
      if (!await TidsbankenPresenceService.isEnabledForCompany(companyId)) return;
      await TidsbankenPresenceService.syncNow();
      final sync = await TidsbankenPresenceService.fetchSyncState(companyId);
      if (mounted) setState(() => _tidsbankenSync = sync);
    } catch (_) {}
  }

  void _openOnlineBoard() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const OnlinePresenceScreen()),
    );
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    try {
      final companyId = await SupabaseService.getCurrentCompanyId();
      final profile = await SupabaseService.fetchCurrentUserProfile();
      final ({String? companyName, KioskSettings kiosk}) meta =
          companyId != null
              ? await SupabaseService.fetchCompanyDashboardMeta(companyId)
              : (companyName: null, kiosk: KioskSettings.defaults);

      if (companyId == null) {
        setState(() {
          _profile = profile;
          _isLoading = false;
          _stats = const DashboardStats();
          _kiosk = KioskSettings.defaults;
          _companyName = null;
          _scopedAbsences = const [];
          _notices = [
            _DashboardNotice(
              title: 'Ingen data fra Supabase',
              subtitle: profile?.isRecoverySession == true
                  ? 'Mangler profiles-rad — kjør ensure_internal_profile_missing.sql, logg ut og inn.'
                  : 'Profilen mangler company_id — logg ut og inn på nytt.',
              icon: Icons.cloud_off_outlined,
              color: DriftProTheme.warning,
              type: _NoticeType.noCompany,
            ),
          ];
        });
        return;
      }

      final access = profile?.access;
      final canAvvik = access?.canAvvik ?? false;
      final canFravaer = access?.canFravaer ?? false;

      final scopedTickets = (profile != null && canAvvik)
          ? await SupabaseService.fetchScopedTickets(profile: profile)
          : <Ticket>[];
      final scopedAbsences = (profile != null && canFravaer)
          ? await SupabaseService.fetchScopedAbsences(profile: profile)
          : <Absence>[];

      final risks = (access?.canHmsRisk ?? false)
          ? await SupabaseService.fetchRiskAssessments(companyId: companyId)
          : <RiskAssessment>[];
      final sjas = (access?.canHmsSja ?? false)
          ? await SupabaseService.fetchSjaForms(companyId: companyId)
          : <SjaForm>[];
      final rounds = (access?.canHmsSafetyRound ?? false)
          ? await SupabaseService.fetchSafetyRounds(companyId: companyId)
          : <SafetyRound>[];

      List<UserProfile> scopeProfiles = const [];
      if (profile != null) {
        if (profile.isAdmin) {
          scopeProfiles =
              await SupabaseService.fetchProfiles(companyId: companyId);
        } else if (profile.role == UserRole.leder &&
            profile.departmentId != null) {
          scopeProfiles = await SupabaseService.fetchProfiles(
            companyId: companyId,
            departmentId: profile.departmentId,
          );
        } else {
          scopeProfiles = [profile];
        }
      }

      final isCoordinator = access?.canApproveLeave == true;
      final scopeUserIds = scopeProfiles.map((p) => p.id).toSet();

      var onDuty = await AttendanceService.getOnDutyEmployees(companyId);
      if (profile != null && !profile.isAdmin) {
        if (profile.role == UserRole.leder) {
          onDuty = onDuty.where((e) => scopeUserIds.contains(e.userId)).toList();
        } else {
          onDuty = onDuty.where((e) => e.userId == profile.id).toList();
        }
      }
      final myAttendance = await AttendanceService.getMyAttendance();
      TidsbankenSyncState? tidsSync;
      if (meta.kiosk.showTidsbankenPresence) {
        tidsSync = await TidsbankenPresenceService.fetchSyncState(companyId);
        if (await TidsbankenPresenceService.isEnabledForCompany(companyId)) {
          await TidsbankenPresenceService.syncNow();
          tidsSync = await TidsbankenPresenceService.fetchSyncState(companyId);
        }
      }

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      int todayAbsences = scopedAbsences.where((a) {
        final start = DateTime(a.startDate.year, a.startDate.month, a.startDate.day);
        final end = DateTime(a.endDate.year, a.endDate.month, a.endDate.day);
        return a.status == AbsenceStatus.godkjent &&
            !today.isBefore(start) &&
            !today.isAfter(end);
      }).length;

      int openTickets = scopedTickets.where((t) => t.isOpen).length;
      int criticalTickets = scopedTickets.where((t) => t.severity == TicketSeverity.kritisk && t.isOpen).length;
      final pendingApprovals = isCoordinator && profile != null
          ? scopedAbsences
              .where((a) =>
                  a.status == AbsenceStatus.ventende && a.userId != profile.id)
              .length
          : 0;
      final newTicketsCount = scopedTickets.where((t) {
        final c = t.createdAt;
        if (c == null) return false;
        return DateTime.now().difference(c).inDays <= 7 && t.isOpen;
      }).length;
      final pendingUsers = (profile?.isSuperAdmin == true)
          ? (await SupabaseService.fetchProfiles(companyId: companyId))
              .where((u) => !u.isApproved && !u.isPartnerPortalUser)
              .length
          : 0;
      String? departmentName;
      int? vacationDaysLeft;
      if (profile != null) {
        if (profile.departmentId != null) {
          final depts = await SupabaseService.fetchDepartments(companyId: companyId);
          departmentName = depts
              .where((d) => d.id == profile.departmentId)
              .map((d) => d.name)
              .firstOrNull;
        }
        if (canFravaer) {
          final quota = await SupabaseService.fetchAbsenceQuota(userId: profile.id);
          vacationDaysLeft = quota?.vacationDaysRemaining;
        }
      }
      final myPendingAbsences = profile == null
          ? 0
          : scopedAbsences
              .where((a) =>
                  a.userId == profile.id && a.status == AbsenceStatus.ventende)
              .length;
      final myOpenTickets = profile == null
          ? 0
          : scopedTickets
              .where((t) => t.reportedBy == profile.id && t.isOpen)
              .length;

      final notices = <_DashboardNotice>[
        if (pendingUsers > 0 && profile?.isSuperAdmin == true)
          _DashboardNotice(
            title: '$pendingUsers nye brukere venter på godkjenning',
            subtitle: 'Trykk for å åpne godkjenning',
            icon: Icons.how_to_reg_outlined,
            color: DriftProTheme.primaryGreen,
            type: _NoticeType.pendingUsers,
          ),
        if (pendingApprovals > 0 && access?.canApproveLeave == true)
          _DashboardNotice(
            title: '$pendingApprovals fravær/ferie-forespørsler venter',
            subtitle: 'Trykk for å åpne håndtering',
            icon: AppIcons.absence,
            color: DriftProTheme.warning,
            type: _NoticeType.pendingAbsence,
          ),
        if (criticalTickets > 0 && canAvvik)
          _DashboardNotice(
            title: '$criticalTickets kritiske avvik åpne',
            subtitle: 'Trykk for å åpne avvik',
            icon: AppIcons.ticket,
            color: DriftProTheme.severityCritical,
            type: _NoticeType.criticalTickets,
          ),
        if (newTicketsCount > 0 && canAvvik)
          _DashboardNotice(
            title: '$newTicketsCount nye avvik siste 7 dager',
            subtitle: 'Trykk for å se avvik',
            icon: Icons.fiber_new_rounded,
            color: DriftProTheme.warning,
            type: _NoticeType.newTickets,
          ),
      ];

      setState(() {
        _profile = profile;
        _kiosk = meta.kiosk;
        _companyName = CompanyDisplay.resolve(meta.companyName);
        _scopedAbsences = scopedAbsences;
        _scopedTickets = scopedTickets;
        _onDutyEmployees = onDuty;
        _myAttendance = myAttendance;
        _tidsbankenSync = tidsSync;
        _recentActivity = _buildRecentActivity(
          tickets: scopedTickets,
          absences: scopedAbsences,
          sjas: sjas,
          canAvvik: canAvvik,
          canFravaer: canFravaer,
          canSja: access?.canHmsSja == true,
        );
        _notices = notices;
        _departmentName = departmentName;
        _vacationDaysLeft = vacationDaysLeft;
        _myPendingAbsences = myPendingAbsences;
        _myOpenTickets = myOpenTickets;
        _stats = DashboardStats(
          todayAbsences: todayAbsences,
          openTickets: openTickets,
          criticalTickets: criticalTickets,
          highRiskCount: (access?.canHmsRisk ?? false)
              ? risks.where((r) => r.isHighRisk).length
              : 0,
          pendingSja: (access?.canHmsSja ?? false)
              ? sjas
                  .where((s) =>
                      s.status == SjaStatus.utkast || s.status == SjaStatus.signert)
                  .length
              : 0,
          upcomingSafetyRounds: (access?.canHmsSafetyRound ?? false)
              ? rounds.where((r) => r.overallStatus == 'planlagt').length
              : 0,
          totalEmployees: scopeProfiles.length,
          absenceRate: scopeProfiles.isEmpty
              ? 0
              : (todayAbsences / scopeProfiles.length * 100),
        );
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<dynamic> _buildRecentActivity({
    required List<Ticket> tickets,
    required List<Absence> absences,
    required List<SjaForm> sjas,
    required bool canAvvik,
    required bool canFravaer,
    required bool canSja,
  }) {
    final items = <({DateTime? at, dynamic item})>[];
    if (canAvvik) {
      for (final t in tickets) {
        items.add((at: t.createdAt, item: t));
      }
    }
    if (canFravaer) {
      for (final a in absences) {
        items.add((at: a.createdAt ?? a.startDate, item: a));
      }
    }
    if (canSja) {
      for (final s in sjas) {
        items.add((at: s.createdAt, item: s));
      }
    }
    items.sort((a, b) {
      final ta = a.at ?? DateTime.fromMillisecondsSinceEpoch(0);
      final tb = b.at ?? DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
    return items.take(8).map((e) => e.item).toList();
  }

  bool _isAbsenceActiveToday(Absence a) {
    if (a.status != AbsenceStatus.godkjent) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start =
        DateTime(a.startDate.year, a.startDate.month, a.startDate.day);
    final end = DateTime(a.endDate.year, a.endDate.month, a.endDate.day);
    return !today.isBefore(start) && !today.isAfter(end);
  }

  List<Absence> get _vacationToday => _scopedAbsences
      .where((a) => a.type == AbsenceType.ferie && _isAbsenceActiveToday(a))
      .toList();

  List<Absence> get _otherAbsenceToday => _scopedAbsences
      .where((a) => a.type != AbsenceType.ferie && _isAbsenceActiveToday(a))
      .toList();

  List<Absence> get _pendingAbsenceRequests => _scopedAbsences
      .where((a) =>
          a.status == AbsenceStatus.ventende &&
          (_profile == null || a.userId != _profile!.id))
      .toList();

  List<Ticket> get _openTickets =>
      _scopedTickets.where((t) => t.isOpen).toList();

  DateTimeRange get _opsRange {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_opsWindow) {
      case _OpsWindow.today:
        return DateTimeRange(start: today, end: today);
      case _OpsWindow.week:
        return DateTimeRange(start: today, end: today.add(const Duration(days: 6)));
      case _OpsWindow.month:
        return DateTimeRange(start: today, end: today.add(const Duration(days: 29)));
    }
  }

  bool _absenceOverlapsRange(Absence a, DateTimeRange range) {
    if (a.status != AbsenceStatus.godkjent) return false;
    final start = DateTime(a.startDate.year, a.startDate.month, a.startDate.day);
    final end = DateTime(a.endDate.year, a.endDate.month, a.endDate.day);
    return !end.isBefore(range.start) && !start.isAfter(range.end);
  }

  List<Absence> _vacationInOpsRange() {
    final range = _opsRange;
    return _scopedAbsences
        .where((a) => a.type == AbsenceType.ferie && _absenceOverlapsRange(a, range))
        .toList();
  }

  List<Absence> _otherAbsenceInOpsRange() {
    final range = _opsRange;
    return _scopedAbsences
        .where((a) => a.type != AbsenceType.ferie && _absenceOverlapsRange(a, range))
        .toList();
  }

  List<Ticket> _openTicketsInOpsRange() {
    final range = _opsRange;
    return _openTickets.where((t) {
      final created = t.createdAt;
      if (created == null) return true;
      final d = DateTime(created.year, created.month, created.day);
      return !d.isBefore(range.start) && !d.isAfter(range.end);
    }).toList();
  }

  String get _opsWindowLabel => switch (_opsWindow) {
        _OpsWindow.today => 'I dag',
        _OpsWindow.week => 'Neste 7 dager',
        _OpsWindow.month => 'Neste 30 dager',
      };

  String get _dataScopeLabel {
    if (_profile?.isAdmin == true) return 'Hele bedriften';
    if (_profile?.role == UserRole.leder) return 'Din avdeling og deg';
    return 'Kun dine registreringer';
  }

  String get _roleLabel {
    final p = _profile;
    if (p == null) return '';
    if (p.jobTitle != null && p.jobTitle!.trim().isNotEmpty) return p.jobTitle!.trim();
    return switch (p.role) {
      UserRole.superadmin => 'Superadmin',
      UserRole.admin => 'Administrator',
      UserRole.leder => 'Avdelingsleder',
      UserRole.ansatt => 'Ansatt',
      UserRole.samarbeidspartner => 'Samarbeidspartner',
    };
  }

  DashboardPersonalSnapshot? get _personalSnapshot {
    final p = _profile;
    final access = _access;
    if (p == null || access == null) return null;
    return DashboardPersonalSnapshot(
      myPendingAbsences: _myPendingAbsences,
      myOpenTickets: _myOpenTickets,
      vacationDaysLeft: _vacationDaysLeft,
      departmentName: _departmentName,
      dataScopeLabel: _dataScopeLabel,
      roleLabel: _roleLabel,
    );
  }

  void _openCommandPalette() {
    final p = _profile;
    if (p == null) return;
    DashboardCommandPalette.show(
      context,
      profile: p,
      scopedTickets: _scopedTickets,
      scopedAbsences: _scopedAbsences,
      onNavigateByAccess: widget.onNavigateByAccess,
    );
  }

  List<Widget> _buildAccessibleModuleChips(bool isDark) {
    final p = _profile;
    final access = _access;
    if (p == null || access == null) return const [];

    final items = DashboardSearchCatalog.modulesAndActions(
      profile: p,
      access: access,
    ).where((i) => i.kind == DashboardSearchKind.module).take(8);

    return items
        .map(
          (item) => ActionChip(
            avatar: Icon(item.icon, size: 16, color: DriftProTheme.primaryGreen),
            label: Text(item.title),
            onPressed: () => item.navigate(context, widget.onNavigateByAccess),
            backgroundColor: isDark ? DriftProTheme.cardDark : Colors.white,
            side: BorderSide(
              color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200,
            ),
          ),
        )
        .toList();
  }

  bool get _canShowColleagueNames =>
      !_anonymizeSharedScreen &&
      (_profile?.isAdmin == true || _profile?.role == UserRole.leder);

  String _displayPersonName(String? name, {required bool isSelf}) {
    if (name == null || name.trim().isEmpty) return 'Ukjent';
    if (isSelf || _canShowColleagueNames) return name.trim();
    return 'Ansatt';
  }

  String _absencePeriodLabel(Absence a) {
    final fmt = DateFormat('d. MMM', 'nb_NO');
    if (_nbDatesReady) {
      try {
        return '${fmt.format(a.startDate)} – ${fmt.format(a.endDate)}';
      } catch (_) {}
    }
    return '${a.startDate.day}.${a.startDate.month} – ${a.endDate.day}.${a.endDate.month}';
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return AppStrings.greetingMorning;
    if (hour < 17) return AppStrings.greetingAfternoon;
    return AppStrings.greetingEvening;
  }

  String _getDateString() {
    final now = DateTime.now();
    if (_nbDatesReady) {
      try {
        final w = DateFormat.EEEE('nb_NO').format(now);
        final m = DateFormat.MMMM('nb_NO').format(now);
        return '$w ${now.day}. $m ${now.year}';
      } catch (_) {}
    }
    final weekdays = [
      'Mandag', 'Tirsdag', 'Onsdag', 'Torsdag', 'Fredag', 'Lørdag', 'Søndag'
    ];
    final months = [
      'januar', 'februar', 'mars', 'april', 'mai', 'juni',
      'juli', 'august', 'september', 'oktober', 'november', 'desember'
    ];
    return '${weekdays[now.weekday - 1]} ${now.day}. ${months[now.month - 1]} ${now.year}';
  }

  String? _getClockString() {
    if (!_kiosk.showClock) return null;
    final now = DateTime.now();
    if (_nbDatesReady) {
      try {
        return DateFormat.Hm('nb_NO').format(now);
      } catch (_) {}
    }
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  Map<AbsenceType, int> _absenceTypeCountsToday() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final map = <AbsenceType, int>{};
    for (final a in _scopedAbsences) {
      if (a.status != AbsenceStatus.godkjent) continue;
      final start = DateTime(a.startDate.year, a.startDate.month, a.startDate.day);
      final end = DateTime(a.endDate.year, a.endDate.month, a.endDate.day);
      if (today.isBefore(start) || today.isAfter(end)) continue;
      map[a.type] = (map[a.type] ?? 0) + 1;
    }
    return map;
  }

  String _heroTitleLine() {
    final nameParts = _profile?.fullName
            .split(' ')
            .where((s) => s.isNotEmpty)
            .toList() ??
        [];
    final first = nameParts.isNotEmpty ? nameParts.first : '';
    if (_usePersonalGreeting && first.isNotEmpty) {
      return '${_getGreeting()}, $first 👋';
    }
    return CompanyDisplay.resolve(_companyName);
  }

  List<Widget> _buildMiniStatChildren() {
    final parts = <Widget>[];
    void add(String value, String label, IconData icon, bool show) {
      if (!show) return;
      if (parts.isNotEmpty) {
        parts.add(const SizedBox(width: 12));
      }
      parts.add(_buildMiniStat(value, label, icon));
    }

    add(
      '${_vacationToday.length}',
      'På ferie',
      Icons.beach_access_outlined,
      _contentKiosk.showAbsenceAggregate && (_access?.canFravaer ?? false),
    );
    add(
      '${_otherAbsenceToday.length}',
      'Fravær i dag',
      AppIcons.absence,
      _contentKiosk.showAbsenceAggregate && (_access?.canFravaer ?? false),
    );
    add(
      '${_stats.openTickets}',
      'Åpne avvik',
      AppIcons.ticket,
      _contentKiosk.showTicketStats && (_access?.canAvvik ?? false),
    );
    add(
      '${_onDutyEmployees.length}',
      'På jobb nå',
      Icons.work_outline,
      _contentKiosk.showAttendanceSummary && (_access?.canFravaer ?? false),
    );
    return parts;
  }

  Widget _buildLiveTeamBoardCard(bool isDark) {
    final sync = _tidsbankenSync;
    final title = CompanyDisplay.resolve(_companyName);
    final onJob = sync != null && sync.totalCount > 0
        ? '${sync.clockedInCount} av ${sync.totalCount} innstemplt'
        : '${_onDutyEmployees.length} på jobb';
    final syncLabel = sync?.lastSyncAt != null
        ? 'Oppdatert ${DateFormat('HH:mm', 'nb').format(sync!.lastSyncAt!.toLocal())}'
        : 'Trykk for oversikt';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _openOnlineBoard,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.apartment_rounded, color: DriftProTheme.primaryGreen, size: 32),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: DriftProTheme.headingSm),
                      const SizedBox(height: 4),
                      Text(onJob, style: DriftProTheme.bodyMd),
                      Text(
                        syncLabel,
                        style: DriftProTheme.bodySm.copyWith(
                          color: isDark ? Colors.grey[500] : Colors.grey[600],
                        ),
                      ),
                      Text(
                        'Ferie · bursdag · hvem er inne · oppdateres hvert 5. min',
                        style: DriftProTheme.bodySm.copyWith(
                          color: DriftProTheme.primaryGreen,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAbsenceAggregateSection(bool isDark) {
    if (_access?.canFravaer != true) return const SizedBox.shrink();
    final counts = _absenceTypeCountsToday();
    if (counts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? DriftProTheme.cardDark : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade100,
            ),
          ),
          child: Text(
            'Ingen registrert fravær i dag (godkjente perioder).',
            style: DriftProTheme.bodyMd.copyWith(
              color: isDark ? Colors.white70 : Colors.grey[800],
            ),
          ),
        ),
      );
    }
    final lines = counts.entries
        .map((e) => '${e.key.label}: ${e.value}')
        .join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? DriftProTheme.cardDark : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade100,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Fravær i dag (samlet)',
              style: DriftProTheme.labelLg.copyWith(
                color: isDark ? Colors.white : Colors.grey[900],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              lines,
              style: DriftProTheme.bodyMd.copyWith(
                color: isDark ? Colors.white70 : Colors.grey[700],
              ),
            ),
            if (!_kiosk.revealNamesOnInfoscreen)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Viser ikke navn (personvern).',
                  style: DriftProTheme.bodySm.copyWith(
                    color: isDark ? Colors.grey[500] : Colors.grey[600],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOperationsHub(bool isDark) {
    final canFravaer = _access?.canFravaer == true;
    final canAvvik = _access?.canAvvik == true;
    if (!canFravaer && !canAvvik) return const SizedBox.shrink();

    final vacation = _vacationInOpsRange();
    final away = _otherAbsenceInOpsRange();
    final open = List<Ticket>.from(_openTicketsInOpsRange())
      ..sort((a, b) {
        final sev = b.severity.index.compareTo(a.severity.index);
        if (sev != 0) return sev;
        final ta = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final tb = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return tb.compareTo(ta);
      });
    final pending = _pendingAbsenceRequests;
    final showPending =
        pending.isNotEmpty && (_access?.canApproveLeave == true);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  DriftProTheme.primaryGreen.withValues(alpha: 0.92),
                  DriftProTheme.primaryGreen.withValues(alpha: 0.72),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.hub_outlined, color: Colors.white, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      'Operasjonssenter',
                      style: DriftProTheme.headingSm.copyWith(color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _dataScopeLabel,
                  style: DriftProTheme.bodySm.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 8),
                SegmentedButton<_OpsWindow>(
                  segments: const [
                    ButtonSegment(value: _OpsWindow.today, label: Text('I dag')),
                    ButtonSegment(value: _OpsWindow.week, label: Text('7 dager')),
                    ButtonSegment(value: _OpsWindow.month, label: Text('30 dager')),
                  ],
                  selected: {_opsWindow},
                  onSelectionChanged: (s) => setState(() => _opsWindow = s.first),
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: const WidgetStatePropertyAll(Colors.white),
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      return states.contains(WidgetState.selected)
                          ? Colors.white.withValues(alpha: 0.20)
                          : Colors.white.withValues(alpha: 0.08);
                    }),
                    side: WidgetStatePropertyAll(
                      BorderSide(color: Colors.white.withValues(alpha: 0.25)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (canFravaer)
                      _opsChip(
                        '${vacation.length}',
                        'På ferie',
                        Icons.beach_access_outlined,
                      ),
                    if (canFravaer)
                      _opsChip('${away.length}', 'Fravær', AppIcons.absence),
                    if (canAvvik)
                      _opsChip('${open.length}', 'Åpne avvik', AppIcons.ticket),
                    if (showPending)
                      _opsChip(
                        '${pending.length}',
                        'Venter',
                        Icons.pending_actions_outlined,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (canFravaer)
            _opsSection(
              isDark: isDark,
              title: 'På ferie nå',
              subtitle: vacation.isEmpty
                  ? _emptyOpsMessage('ferie')
                  : '${vacation.length} godkjent${vacation.length == 1 ? '' : 'e'} · $_opsWindowLabel',
              icon: Icons.beach_access_outlined,
              color: DriftProTheme.absenceVacation,
              onOpen: () => _go(AccessKeys.fravaer),
              child: vacation.isEmpty
                  ? null
                  : Column(
                      children: vacation
                          .take(6)
                          .map((a) => _absenceOpsRow(a, isDark))
                          .toList(),
                    ),
            ),
          if (canFravaer) ...[
            const SizedBox(height: 10),
            _opsSection(
              isDark: isDark,
              title: 'Fravær i dag',
              subtitle: away.isEmpty
                  ? _emptyOpsMessage('fravær')
                  : '${away.length} registrert · $_opsWindowLabel',
              icon: AppIcons.absence,
              color: DriftProTheme.warning,
              onOpen: () => _go(AccessKeys.fravaer),
              child: away.isEmpty
                  ? null
                  : Column(
                      children:
                          away.take(6).map((a) => _absenceOpsRow(a, isDark)).toList(),
                    ),
            ),
          ],
          if (showPending) ...[
            const SizedBox(height: 10),
            _opsSection(
              isDark: isDark,
              title: 'Venter på godkjenning',
              subtitle: '${pending.length} forespørsel${pending.length == 1 ? '' : 'er'}',
              icon: Icons.pending_actions_outlined,
              color: DriftProTheme.accentBlue,
              onOpen: () => _go(AccessKeys.fravaer),
              child: Column(
                children: pending
                    .take(5)
                    .map((a) => _absenceOpsRow(a, isDark, pending: true))
                    .toList(),
              ),
            ),
          ],
          if (canAvvik) ...[
            const SizedBox(height: 10),
            _opsSection(
              isDark: isDark,
              title: 'Åpne avvik',
              subtitle: open.isEmpty
                  ? _emptyOpsMessage('avvik')
                  : '${open.length} åpne · ${open.where((t) => t.severity == TicketSeverity.kritisk).length} kritiske · $_opsWindowLabel',
              icon: AppIcons.ticket,
              color: DriftProTheme.severityCritical,
              onOpen: () => _go(AccessKeys.avvik),
              child: open.isEmpty
                  ? null
                  : Column(
                      children:
                          open.take(5).map((t) => _ticketOpsRow(t, isDark)).toList(),
                    ),
            ),
          ],
          const SizedBox(height: 10),
          _buildUtilityStrip(isDark),
        ],
      ),
    );
  }

  Widget _opsChip(String value, String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildUtilityStrip(bool isDark) {
    final items = <Widget>[
      if (_access?.canFravaer == true)
        _utilityButton(
          icon: Icons.calendar_month_outlined,
          label: 'Se ferie/fravær',
          onTap: () => _go(AccessKeys.fravaer),
          isDark: isDark,
        ),
      if (_access?.canAvvik == true)
        _utilityButton(
          icon: Icons.report_problem_outlined,
          label: 'Se avvik',
          onTap: () => _go(AccessKeys.avvik),
          isDark: isDark,
        ),
      if (_access?.canFravaer == true)
        _utilityButton(
          icon: Icons.event_available_outlined,
          label: 'Ny registrering',
          onTap: () => _go(AccessKeys.fravaer),
          isDark: isDark,
        ),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 8, children: items);
  }

  Widget _utilityButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        foregroundColor: isDark ? Colors.white70 : Colors.grey.shade800,
        side: BorderSide(
          color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade300,
        ),
      ),
    );
  }

  Widget _opsSection({
    required bool isDark,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onOpen,
    required Widget? child,
  }) {
    return Material(
      color: isDark ? DriftProTheme.cardDark : Colors.white,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: DriftProTheme.labelLg),
                        Text(
                          subtitle,
                          style: DriftProTheme.bodySm.copyWith(
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: isDark ? Colors.grey[500] : Colors.grey[400],
                  ),
                ],
              ),
              if (child != null) ...[
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 8),
                child,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _absenceOpsRow(Absence a, bool isDark, {bool pending = false}) {
    final isSelf = a.userId == _profile?.id;
    final name = _displayPersonName(a.userName, isSelf: isSelf);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: DriftProTheme.primaryGreen.withValues(alpha: 0.1),
            backgroundImage:
                a.userAvatarUrl != null ? NetworkImage(a.userAvatarUrl!) : null,
            child: a.userAvatarUrl == null
                ? Text(
                    name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
                    style: const TextStyle(
                      fontSize: 12,
                      color: DriftProTheme.primaryGreen,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: DriftProTheme.labelMd),
                Text(
                  '${a.type.label} · ${_absencePeriodLabel(a)}',
                  style: DriftProTheme.bodySm.copyWith(
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          if (pending)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: DriftProTheme.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'VENTER',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: DriftProTheme.warning,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _ticketOpsRow(Ticket t, bool isDark) {
    final sevColor = switch (t.severity) {
      TicketSeverity.kritisk => DriftProTheme.severityCritical,
      TicketSeverity.hoy => DriftProTheme.riskHigh,
      TicketSeverity.middels => DriftProTheme.warning,
      TicketSeverity.lav => DriftProTheme.primaryGreen,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: sevColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _anonymizeSharedScreen ? 'Avvik #${t.ticketNumber ?? ''}' : t.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DriftProTheme.labelMd,
                ),
                Text(
                  '${t.severity.label} · ${t.status.label}',
                  style: DriftProTheme.bodySm.copyWith(
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _emptyOpsMessage(String kind) {
    if (_profile?.role == UserRole.ansatt) {
      return switch (kind) {
        'ferie' => 'Du har ingen godkjent ferie i dag.',
        'fravær' => 'Du har ikke registrert fravær i dag.',
        _ => 'Du har ingen åpne avvik.',
      };
    }
    return switch (kind) {
      'ferie' => 'Ingen på ferie i ditt dataområde i dag.',
      'fravær' => 'Ingen registrert fravær i dag.',
      _ => 'Ingen åpne avvik i ditt dataområde.',
    };
  }

  List<Widget> _buildQuickActionButtons() {
    final actions = <Widget>[];
    void add(Widget w) {
      if (actions.isNotEmpty) actions.add(const SizedBox(width: 12));
      actions.add(w);
    }

    if (_access?.canSurveys == true) {
      add(QuickActionButton(
        icon: AppIcons.survey,
        label: AppStrings.navSurveys,
        color: Colors.purple,
        onTap: () => _go(AccessKeys.surveys),
      ));
    }
    if (_access?.canFravaer == true) {
      add(QuickActionButton(
        icon: AppIcons.absence,
        label: 'Fravær',
        color: DriftProTheme.absenceVacation,
        onTap: () => _go(AccessKeys.fravaer),
      ));
    }
    if (_access?.canAvvik == true) {
      add(QuickActionButton(
        icon: AppIcons.newTicket,
        label: 'Nytt avvik',
        color: DriftProTheme.warning,
        onTap: () => _go(AccessKeys.avvik),
      ));
    }
    if (_access?.canHmsSja == true) {
      add(QuickActionButton(
        icon: AppIcons.sja,
        label: 'Ny SJA',
        color: DriftProTheme.accentBlue,
        onTap: () => _go(AccessKeys.hms),
      ));
    }
    if (_access?.canHmsRisk == true) {
      add(QuickActionButton(
        icon: AppIcons.riskAssessment,
        label: 'Risiko',
        color: DriftProTheme.riskHigh,
        onTap: () => _go(AccessKeys.hms),
      ));
    }
    return actions;
  }

  List<Widget> _buildOverviewStatCards() {
    final cards = <Widget>[];
    if (_contentKiosk.showTicketStats && _access?.canAvvik == true) {
      cards.add(StatCard(
        title: 'Åpne avvik',
        value: '${_stats.openTickets}',
        icon: AppIcons.ticket,
        color: DriftProTheme.warning,
        subtitle: '${_stats.criticalTickets} kritiske',
        isAlert: _stats.criticalTickets > 0,
        onTap: () => _go(AccessKeys.avvik),
      ));
    }
    if (_contentKiosk.showTicketStats && _access?.canFravaer == true) {
      cards.add(StatCard(
        title: 'Fravær i dag',
        value: '${_stats.todayAbsences}',
        icon: AppIcons.absence,
        color: DriftProTheme.absenceVacation,
        onTap: () => _go(AccessKeys.fravaer),
      ));
    }
    if (_contentKiosk.showHmsHighlights && _access?.canHmsRisk == true) {
      cards.add(StatCard(
        title: 'Høy risiko',
        value: '${_stats.highRiskCount}',
        icon: AppIcons.riskAssessment,
        color: DriftProTheme.riskHigh,
        onTap: () => _go(AccessKeys.hms),
      ));
    }
    if (_contentKiosk.showHmsHighlights && _access?.canHmsSja == true) {
      cards.add(StatCard(
        title: 'SJA (åpne)',
        value: '${_stats.pendingSja}',
        icon: AppIcons.sja,
        color: DriftProTheme.accentBlue,
        onTap: () => _go(AccessKeys.hms),
      ));
    }
    if (_contentKiosk.showHmsHighlights && _access?.canHmsSafetyRound == true) {
      cards.add(StatCard(
        title: 'Vernerunder',
        value: '${_stats.upcomingSafetyRounds}',
        subtitle: 'planlagt',
        icon: Icons.health_and_safety_outlined,
        color: DriftProTheme.primaryGreen,
        onTap: () => _go(AccessKeys.hms),
      ));
    }
    if (_contentKiosk.showHmsHighlights &&
        _access?.canFravaer == true &&
        (_profile?.isAdmin == true || _profile?.role == UserRole.leder)) {
      cards.add(StatCard(
        title: 'Bemanningsdekning',
        value:
            '${_stats.totalEmployees > 0 ? (100 - _stats.absenceRate).clamp(0, 100).toStringAsFixed(0) : '—'}%',
        subtitle: 'anslått tilstedeværelse',
        icon: Icons.groups_outlined,
        color: DriftProTheme.primaryGreen,
        onTap: () => _go(AccessKeys.fravaer),
      ));
    }
    return cards;
  }

  List<Widget> _buildActivityAttendanceSlivers(bool isDark) {
    final showActivity = _contentKiosk.showActivityFeed;
    // Full oversikt ligger på infoskjerm-kortet — unngå lang «På jobb»-liste her.
    final showAttendanceList = !_contentKiosk.showLiveTeamBoard &&
        _contentKiosk.showAttendanceSummary &&
        !_anonymizeSharedScreen &&
        (_access?.canFravaer == true || _access?.canEmployeesList == true);

    if (!showActivity && !showAttendanceList) {
      return const [];
    }

    if (showActivity && !showAttendanceList) {
      return [
        const SliverToBoxAdapter(
          child: SectionHeader(title: 'Siste aktivitet'),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              if (_recentActivity.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: Text('Ingen nylig aktivitet'),
                  ),
                );
              }
              final item = _recentActivity[index];
              return _buildActivityTile(item, isDark);
            },
            childCount: _recentActivity.isEmpty ? 1 : _recentActivity.length,
          ),
        ),
      ];
    }

    if (!showActivity && showAttendanceList) {
      return [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: SectionHeader(title: 'På jobb nå'),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              if (_onDutyEmployees.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: Text('Ingen ansatte er på jobb akkurat nå.'),
                  ),
                );
              }
              final emp = _onDutyEmployees[index];
              return _buildAttendanceTile(emp, isDark);
            },
            childCount: _onDutyEmployees.isEmpty ? 1 : _onDutyEmployees.length,
          ),
        ),
      ];
    }

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              _buildTabButton(0, 'Aktivitet', isDark),
              const SizedBox(width: 12),
              _buildTabButton(1, 'På jobb (${_onDutyEmployees.length})', isDark),
            ],
          ),
        ),
      ),
      if (_activeTabIndex == 0)
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              if (_recentActivity.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: Text('Ingen nylig aktivitet'),
                  ),
                );
              }
              final item = _recentActivity[index];
              return _buildActivityTile(item, isDark);
            },
            childCount: _recentActivity.isEmpty ? 1 : _recentActivity.length,
          ),
        )
      else
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              if (_onDutyEmployees.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: Text('Ingen ansatte er på jobb akkurat nå.'),
                  ),
                );
              }
              final emp = _onDutyEmployees[index];
              return _buildAttendanceTile(emp, isDark);
            },
            childCount: _onDutyEmployees.isEmpty ? 1 : _onDutyEmployees.length,
          ),
        ),
    ];
  }

  Future<void> _refreshDashboard() async {
    HapticFeedback.mediumImpact();
    await _loadAllData();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final miniStats = _buildMiniStatChildren();

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): _openCommandPalette,
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): _openCommandPalette,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
      backgroundColor: isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: RefreshIndicator(
          onRefresh: _refreshDashboard,
          color: DriftProTheme.primaryGreen,
          child: Theme(
            data: Theme.of(context).copyWith(
              textTheme: Theme.of(context).textTheme.apply(
                    fontSizeFactor: _kioskFontFactor,
                  ),
            ),
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics()),
              slivers: [
                SliverAppBar(
                  floating: true,
                  snap: true,
                  elevation: 0,
                  backgroundColor:
                      isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
                  title: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          gradient: DriftProTheme.primaryGradient,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Center(
                          child: Text('M',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(CompanyDisplay.defaultName),
                    ],
                  ),
                  actions: [
                    IconButton(
                      tooltip: 'Søk (⌘K)',
                      onPressed: _openCommandPalette,
                      icon: Icon(Icons.search_rounded,
                          color: isDark ? Colors.white : Colors.black87),
                    ),
                    if (_access?.canKiosk == true)
                      IconButton(
                        tooltip: 'Infoskjerm',
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const KioskSettingsScreen(),
                            ),
                          );
                          _loadAllData();
                        },
                        icon: Icon(Icons.display_settings_outlined,
                            color: isDark ? Colors.white : Colors.black87),
                      ),
                    if (_access?.canNotifications == true) ...[
                      const DriftproNotificationBell(),
                      IconButton(
                        onPressed: _openNotificationsSheet,
                        icon: Badge(
                          isLabelVisible: _notices.isNotEmpty,
                          backgroundColor: DriftProTheme.error,
                          label: Text('${_notices.length}',
                              style: const TextStyle(fontSize: 9)),
                          child: Icon(Icons.dashboard_customize_outlined,
                              color: isDark ? Colors.white : Colors.black87),
                        ),
                        tooltip: 'Oppgaver på dashboard',
                      ),
                    ],
                    if (_access?.canProfile != false)
                      GestureDetector(
                      onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const ProfileScreen())),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 16, left: 8),
                        child: CircleAvatar(
                          radius: 16,
                          backgroundColor:
                              DriftProTheme.primaryGreen.withOpacity(0.1),
                          backgroundImage: _profile?.avatarUrl != null
                              ? NetworkImage(_profile!.avatarUrl!)
                              : null,
                          child: _profile?.avatarUrl == null
                              ? Text(_profile?.initials ?? '?',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: DriftProTheme.primaryGreen))
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),

                SliverToBoxAdapter(
                  child: DashboardSearchBar(
                    profile: _profile,
                    scopedTickets: _scopedTickets,
                    scopedAbsences: _scopedAbsences,
                    onNavigateByAccess: widget.onNavigateByAccess,
                  ),
                ),

                if (_personalSnapshot != null && _access != null)
                  SliverToBoxAdapter(
                    child: DashboardPersonalPanel(
                      profile: _profile!,
                      access: _access!,
                      snapshot: _personalSnapshot!,
                      onOpenFravaer: _access!.canFravaer
                          ? () => _go(AccessKeys.fravaer)
                          : null,
                      onOpenAvvik:
                          _access!.canAvvik ? () => _go(AccessKeys.avvik) : null,
                      onOpenProfile: _access!.canProfile
                          ? () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const ProfileScreen(),
                                ),
                              )
                          : null,
                    ),
                  ),

                if (_buildAccessibleModuleChips(isDark).isNotEmpty) ...[
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: SectionHeader(title: 'Dine moduler'),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _buildAccessibleModuleChips(isDark),
                      ),
                    ),
                  ),
                ],

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _heroTitleLine(),
                                      style: DriftProTheme.headingLg
                                          .copyWith(color: Colors.white),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _getDateString(),
                                      style: DriftProTheme.bodyMd
                                          .copyWith(color: Colors.white70),
                                    ),
                                    if (_getClockString() != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        _getClockString()!,
                                        style: DriftProTheme.headingSm.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              _buildAttendanceToggle(isDark),
                            ],
                          ),
                          if (_kiosk.showCustomMessage &&
                              (_kiosk.customMessageTitle.isNotEmpty ||
                                  _kiosk.customMessageBody.isNotEmpty)) ...[
                            const SizedBox(height: 16),
                            Divider(color: Colors.white.withValues(alpha: 0.2)),
                            const SizedBox(height: 8),
                            if (_kiosk.customMessageTitle.isNotEmpty)
                              Text(
                                _kiosk.customMessageTitle,
                                style: DriftProTheme.labelLg
                                    .copyWith(color: Colors.white),
                              ),
                            if (_kiosk.customMessageBody.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                _kiosk.customMessageBody,
                                style: DriftProTheme.bodyMd
                                    .copyWith(color: Colors.white70),
                              ),
                            ],
                          ],
                          if (_contentKiosk.showMiniStatsRow && miniStats.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            Row(children: miniStats),
                          ],
                          if (_anonymizeSharedScreen) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Personvern: felles skjerm viser ikke navn. Admin kan endre dette under Infoskjerm.',
                              style: DriftProTheme.bodySm
                                  .copyWith(color: Colors.white54),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),

                if (_access?.canFravaer == true || _access?.canAvvik == true) ...[
                  SliverToBoxAdapter(child: _buildOperationsHub(isDark)),
                ],

                if (_contentKiosk.showLiveTeamBoard) ...[
                  SliverToBoxAdapter(child: _buildLiveTeamBoardCard(isDark)),
                ],

                if (_contentKiosk.showAbsenceAggregate) ...[
                  SliverToBoxAdapter(child: _buildAbsenceAggregateSection(isDark)),
                ],

                if (_contentKiosk.showQuickActions && _buildQuickActionButtons().isNotEmpty) ...[
                  const SliverToBoxAdapter(child: SectionHeader(title: 'Hurtigvalg')),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 100,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: _buildQuickActionButtons(),
                      ),
                    ),
                  ),
                ],

                if (_buildOverviewStatCards().isNotEmpty) ...[
                  const SliverToBoxAdapter(child: SectionHeader(title: 'Oversikt')),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1.35,
                      ),
                      delegate: SliverChildListDelegate(_buildOverviewStatCards()),
                    ),
                  ),
                ],

                if (_anonymizeSharedScreen && _contentKiosk.showAttendanceSummary) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: GlassCard(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(Icons.work_outline,
                                  color: Colors.white.withValues(alpha: 0.9)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  '${_onDutyEmployees.length} personer er innstemplt nå (navn skjult på felles skjerm).',
                                  style: DriftProTheme.bodyMd
                                      .copyWith(color: Colors.white70),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],

                ..._buildActivityAttendanceSlivers(isDark),

                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          ),
        ),
      ),
        ),
      ),
    );
  }

  Widget _buildMiniStat(String value, String label, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityTile(dynamic item, bool isDark) {
    String title;
    String subtitle;
    IconData icon;
    Color color;

    if (item is Ticket) {
      title = _anonymizeSharedScreen ? 'Avvik' : item.title;
      subtitle = 'Avvik meldt';
      icon = AppIcons.ticket;
      color = DriftProTheme.warning;
    } else if (item is Absence) {
      final isSelf = item.userId == _profile?.id;
      final who = _displayPersonName(item.userName, isSelf: isSelf);
      title = '${item.type.label}${who.isNotEmpty && who != 'Ansatt' ? ' · $who' : ''}';
      subtitle = item.status.label;
      icon = AppIcons.absence;
      color = DriftProTheme.absenceVacation;
    } else if (item is SjaForm) {
      title = _anonymizeSharedScreen ? 'SJA' : item.title;
      subtitle = 'Ny SJA opprettet';
      icon = AppIcons.sja;
      color = DriftProTheme.accentBlue;
    } else {
      title = 'Aktivitet';
      subtitle = 'Systemoppdatering';
      icon = Icons.notifications_none;
      color = Colors.grey;
    }
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? DriftProTheme.cardDark : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade100),
        ),
        child: Row(
          children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: color, size: 20)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: DriftProTheme.labelLg), Text(subtitle, style: DriftProTheme.bodySm.copyWith(color: Colors.grey))])),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton(int index, String label, bool isDark) {
    final isActive = _activeTabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _activeTabIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? DriftProTheme.primaryGreen : (isDark ? Colors.white10 : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildAttendanceToggle(bool isDark) {
    final isOnDuty = _myAttendance?.isOnDuty ?? false;
    return GestureDetector(
      onTap: () async {
        final newStatus = isOnDuty ? AttendanceStatus.off_duty : AttendanceStatus.on_duty;
        HapticFeedback.lightImpact();
        await AttendanceService.toggleStatus(newStatus);
        _loadAllData();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isOnDuty ? Colors.green.withOpacity(0.2) : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isOnDuty ? Colors.green : Colors.white30, width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isOnDuty ? Icons.logout : Icons.login, color: Colors.white, size: 20),
            const SizedBox(height: 4),
            Text(isOnDuty ? 'Gå av' : 'På jobb', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceTile(EmployeeAttendance emp, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? DriftProTheme.cardDark : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade100),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: DriftProTheme.primaryGreen.withOpacity(0.1),
              backgroundImage: emp.avatarUrl != null ? NetworkImage(emp.avatarUrl!) : null,
              child: emp.avatarUrl == null ? Text(emp.fullName?.characters.first.toUpperCase() ?? '?', style: const TextStyle(fontSize: 14, color: DriftProTheme.primaryGreen)) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(emp.fullName ?? 'Ukjent ansatt', style: DriftProTheme.labelLg),
                  Text('Sjekket inn: ${emp.checkInAt?.hour.toString().padLeft(2, '0')}:${emp.checkInAt?.minute.toString().padLeft(2, '0')}', style: DriftProTheme.bodySm.copyWith(color: Colors.grey)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
              child: const Text('PÅ JOBB', style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _openNotificationsSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: _notices.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Ingen nye varsler akkurat nå.'),
              )
            : ListView.separated(
                shrinkWrap: true,
                itemCount: _notices.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final n = _notices[i];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: n.color.withValues(alpha: 0.15),
                      child: Icon(n.icon, color: n.color),
                    ),
                    title: Text(n.title),
                    subtitle: Text(n.subtitle),
                    onTap: () {
                      Navigator.pop(context);
                      _handleNoticeTap(n.type);
                    },
                  );
                },
              ),
      ),
    );
  }

  void _handleNoticeTap(_NoticeType type) {
    switch (type) {
      case _NoticeType.pendingUsers:
        if (_profile?.isSuperAdmin == true) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const EmployeeHubScreen()),
          );
        }
        break;
      case _NoticeType.pendingAbsence:
        if (_access?.canApproveLeave == true) {
          _go(AccessKeys.fravaer);
        }
        break;
      case _NoticeType.criticalTickets:
      case _NoticeType.newTickets:
        if (_access?.canAvvik == true) {
          _go(AccessKeys.avvik);
        }
        break;
      case _NoticeType.noCompany:
        break;
    }
  }
}

enum _OpsWindow { today, week, month }

enum _NoticeType {
  pendingUsers,
  pendingAbsence,
  criticalTickets,
  newTickets,
  noCompany,
}

class _DashboardNotice {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final _NoticeType type;

  const _DashboardNotice({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.type,
  });
}
