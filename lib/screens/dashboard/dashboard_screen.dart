import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import '../../core/constants/app_icons.dart';
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
import '../admin/kiosk_settings_screen.dart';
import '../../widgets/cards/stat_card.dart';
import '../../widgets/cards/quick_action_button.dart';
import '../../widgets/cards/glass_card.dart';
import '../../widgets/common/section_header.dart';
import '../profile/profile_screen.dart';

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
  List<_DashboardNotice> _notices = const [];
  KioskSettings _kiosk = KioskSettings.defaults;
  String? _companyName;
  List<Absence> _scopedAbsences = const [];
  bool _nbDatesReady = false;
  Timer? _clockTimer;

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
    _loadAllData();
  }

  Future<void> _initNbLocale() async {
    await initializeDateFormatting('nb_NO');
    if (mounted) setState(() => _nbDatesReady = true);
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  bool get _anonymizeSharedScreen =>
      _kiosk.infoscreenLayoutEnabled && !_kiosk.revealNamesOnInfoscreen;

  double get _kioskFontFactor => _kiosk.infoscreenLayoutEnabled ? 1.14 : 1.0;

  UserAccess? get _access => _profile?.access;

  void _go(String accessKey) => widget.onNavigateByAccess?.call(accessKey);

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
      final tickets = canAvvik
          ? await SupabaseService.fetchTickets(companyId: companyId)
          : <Ticket>[];
      final absences = canFravaer
          ? await SupabaseService.fetchAbsences(companyId: companyId)
          : <Absence>[];
      final risks = (access?.canHmsRisk ?? false)
          ? await SupabaseService.fetchRiskAssessments(companyId: companyId)
          : <RiskAssessment>[];
      final profiles = await SupabaseService.fetchProfiles(companyId: companyId);
      final sjas = (access?.canHmsSja ?? false)
          ? await SupabaseService.fetchSjaForms(companyId: companyId)
          : <SjaForm>[];
      final rounds = (access?.canHmsSafetyRound ?? false)
          ? await SupabaseService.fetchSafetyRounds(companyId: companyId)
          : <SafetyRound>[];

      final isCoordinator = access?.canApproveLeave == true;
      final scopedTickets = _scopeTicketsByRole(tickets, profile);
      final scopedAbsences = _scopeAbsencesByRole(absences, profile);

      final onDuty = await AttendanceService.getOnDutyEmployees(companyId);
      final myAttendance = await AttendanceService.getMyAttendance();

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
      final pendingApprovals = isCoordinator
          ? scopedAbsences.where((a) => a.status == AbsenceStatus.ventende).length
          : 0;
      final pendingUsers = (profile?.isSuperAdmin == true)
          ? profiles.where((u) => !u.isApproved && !u.isPartnerPortalUser).length
          : 0;
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
      ];

      setState(() {
        _profile = profile;
        _kiosk = meta.kiosk;
        _companyName = meta.companyName;
        _scopedAbsences = scopedAbsences;
        _onDutyEmployees = onDuty;
        _myAttendance = myAttendance;
        _recentActivity = [
          if (canAvvik) ...scopedTickets,
          if (canFravaer) ...scopedAbsences,
          if (access?.canHmsSja == true) ...sjas,
        ].take(5).toList();
        _notices = notices;
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
          totalEmployees: profiles.length,
          absenceRate: profiles.isEmpty ? 0 : (todayAbsences / profiles.length * 100),
        );
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<Ticket> _scopeTicketsByRole(List<Ticket> tickets, UserProfile? profile) {
    if (profile == null) return const [];
    if (profile.isAdmin) return tickets;
    if (profile.isLeader) {
      return tickets
          .where((t) => t.departmentId == profile.departmentId || t.reportedBy == profile.id)
          .toList();
    }
    return tickets.where((t) => t.reportedBy == profile.id).toList();
  }

  List<Absence> _scopeAbsencesByRole(List<Absence> absences, UserProfile? profile) {
    if (profile == null) return const [];
    if (profile.isAdmin) return absences;
    if (profile.isLeader) {
      return absences
          .where((a) => a.departmentId == profile.departmentId || a.userId == profile.id)
          .toList();
    }
    return absences.where((a) => a.userId == profile.id).toList();
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
    if (_kiosk.showPersonalGreeting && first.isNotEmpty) {
      return '${_getGreeting()}, $first 👋';
    }
    final cn = _companyName?.trim();
    if (cn != null && cn.isNotEmpty) return cn;
    return 'DriftPro';
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
      '${_stats.todayAbsences}',
      'Fravær i dag',
      AppIcons.absence,
      _kiosk.showAbsenceAggregate && (_access?.canFravaer ?? false),
    );
    add(
      '${_stats.openTickets}',
      'Åpne avvik',
      AppIcons.ticket,
      _kiosk.showTicketStats && (_access?.canAvvik ?? false),
    );
    add(
      '${_onDutyEmployees.length}',
      'På jobb nå',
      Icons.work_outline,
      _kiosk.showAttendanceSummary && (_access?.canFravaer ?? false),
    );
    return parts;
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
    if (_kiosk.showTicketStats && _access?.canAvvik == true) {
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
    if (_kiosk.showTicketStats && _access?.canFravaer == true) {
      cards.add(StatCard(
        title: 'Fravær i dag',
        value: '${_stats.todayAbsences}',
        icon: AppIcons.absence,
        color: DriftProTheme.absenceVacation,
        onTap: () => _go(AccessKeys.fravaer),
      ));
    }
    if (_kiosk.showHmsHighlights && _access?.canHmsRisk == true) {
      cards.add(StatCard(
        title: 'Høy risiko',
        value: '${_stats.highRiskCount}',
        icon: AppIcons.riskAssessment,
        color: DriftProTheme.riskHigh,
        onTap: () => _go(AccessKeys.hms),
      ));
    }
    if (_kiosk.showHmsHighlights && _access?.canHmsSja == true) {
      cards.add(StatCard(
        title: 'SJA (åpne)',
        value: '${_stats.pendingSja}',
        icon: AppIcons.sja,
        color: DriftProTheme.accentBlue,
        onTap: () => _go(AccessKeys.hms),
      ));
    }
    if (_kiosk.showHmsHighlights && _access?.canHmsSafetyRound == true) {
      cards.add(StatCard(
        title: 'Vernerunder',
        value: '${_stats.upcomingSafetyRounds}',
        subtitle: 'planlagt',
        icon: Icons.health_and_safety_outlined,
        color: DriftProTheme.primaryGreen,
        onTap: () => _go(AccessKeys.hms),
      ));
    }
    if (_kiosk.showHmsHighlights && _access?.canFravaer == true) {
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
    final showActivity =
        _kiosk.showActivityFeed && _recentActivity.isNotEmpty;
    final showAttendanceList = _kiosk.showAttendanceSummary &&
        !_anonymizeSharedScreen &&
        (_access?.canFravaer == true || _access?.canEmployeesList == true);

    if (!showActivity && !showAttendanceList) {
      return const [];
    }

    if (showActivity && !showAttendanceList) {
      return [
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

    return Scaffold(
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
                          child: Text('D',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text('DriftPro'),
                    ],
                  ),
                  actions: [
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
                    if (_access?.canNotifications == true)
                      IconButton(
                        onPressed: _openNotificationsSheet,
                        icon: Badge(
                          isLabelVisible: _notices.isNotEmpty,
                          backgroundColor: DriftProTheme.error,
                          label: Text('${_notices.length}',
                              style: const TextStyle(fontSize: 9)),
                          child: Icon(AppIcons.notification,
                              color: isDark ? Colors.white : Colors.black87),
                        ),
                      ),
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
                          if (_kiosk.showMiniStatsRow && miniStats.isNotEmpty) ...[
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

                if (_kiosk.showAbsenceAggregate) ...[
                  SliverToBoxAdapter(child: _buildAbsenceAggregateSection(isDark)),
                ],

                if (_kiosk.showQuickActions && _buildQuickActionButtons().isNotEmpty) ...[
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

                if (_anonymizeSharedScreen && _kiosk.showAttendanceSummary) ...[
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
      title = item.type.label;
      subtitle = 'Fravær registrert';
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
        if (_access?.canAvvik == true) {
          _go(AccessKeys.avvik);
        }
        break;
      case _NoticeType.noCompany:
        break;
    }
  }
}

enum _NoticeType { pendingUsers, pendingAbsence, criticalTickets, noCompany }

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
