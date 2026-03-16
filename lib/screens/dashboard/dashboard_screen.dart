import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_icons.dart';
import '../../core/constants/app_strings.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/dashboard_stats.dart';
import '../../models/absence.dart';
import '../../models/ticket.dart';
import '../../models/user_profile.dart';
import '../../models/sja_form.dart';
import '../../models/safety_round.dart';
import '../../models/risk_assessment.dart';
import '../../widgets/cards/stat_card.dart';
import '../../widgets/cards/quick_action_button.dart';
import '../../widgets/cards/glass_card.dart';
import '../../widgets/common/section_header.dart';
import '../profile/profile_screen.dart';

class DashboardScreen extends StatefulWidget {
  final Function(int)? onNavigate;

  const DashboardScreen({super.key, this.onNavigate});

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
  bool _isLoading = false;

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
    _loadAllData();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    try {
      final companyId = await SupabaseService.getCurrentCompanyId();
      final profile = await SupabaseService.fetchCurrentUserProfile();
      
      if (companyId == null) {
        setState(() {
          _profile = profile;
          _isLoading = false;
          _stats = const DashboardStats();
        });
        return;
      }

      final futures = await Future.wait([
        SupabaseService.fetchTickets(companyId: companyId),
        SupabaseService.fetchAbsences(companyId: companyId),
        SupabaseService.fetchRiskAssessments(companyId: companyId),
        SupabaseService.fetchProfiles(companyId: companyId),
        SupabaseService.fetchSjaForms(companyId: companyId),
        SupabaseService.fetchSafetyRounds(companyId: companyId),
      ]);

      final tickets = futures[0] as List<Ticket>;
      final absences = futures[1] as List<Absence>;
      final risks = futures[2] as List<RiskAssessment>;
      final profiles = futures[3] as List<UserProfile>;
      final sjas = futures[4] as List<SjaForm>;
      final rounds = futures[5] as List<SafetyRound>;

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      int todayAbsences = absences.where((a) {
        final start = DateTime(a.startDate.year, a.startDate.month, a.startDate.day);
        final end = DateTime(a.endDate.year, a.endDate.month, a.endDate.day);
        return a.status == AbsenceStatus.godkjent &&
            !today.isBefore(start) &&
            !today.isAfter(end);
      }).length;

      int openTickets = tickets.where((t) => t.isOpen).length;
      int criticalTickets = tickets.where((t) => t.severity == TicketSeverity.kritisk && t.isOpen).length;

      setState(() {
        _profile = profile;
        _recentActivity = [...tickets, ...absences, ...sjas].take(5).toList();
        _stats = DashboardStats(
          todayAbsences: todayAbsences,
          openTickets: openTickets,
          criticalTickets: criticalTickets,
          highRiskCount: risks.where((r) => r.isHighRisk).length,
          pendingSja: sjas.where((s) => s.status == SjaStatus.utkast || s.status == SjaStatus.signert).length,
          upcomingSafetyRounds: rounds.where((r) => r.overallStatus == 'planlagt').length,
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

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return AppStrings.greetingMorning;
    if (hour < 17) return AppStrings.greetingAfternoon;
    return AppStrings.greetingEvening;
  }

  String _getDateString() {
    final now = DateTime.now();
    final weekdays = [
      'Mandag', 'Tirsdag', 'Onsdag', 'Torsdag', 'Fredag', 'Lørdag', 'Søndag'
    ];
    final months = [
      'januar', 'februar', 'mars', 'april', 'mai', 'juni',
      'juli', 'august', 'september', 'oktober', 'november', 'desember'
    ];
    return '${weekdays[now.weekday - 1]} ${now.day}. ${months[now.month - 1]}';
  }

  Future<void> _refreshDashboard() async {
    HapticFeedback.mediumImpact();
    await _loadAllData();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: RefreshIndicator(
          onRefresh: _refreshDashboard,
          color: DriftProTheme.primaryGreen,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              // AppBar
              SliverAppBar(
                floating: true, snap: true, elevation: 0,
                backgroundColor: isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
                title: Row(
                  children: [
                    Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        gradient: DriftProTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(child: Text('D', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                    ),
                    const SizedBox(width: 8),
                    const Text('DriftPro'),
                  ],
                ),
                actions: [
                  IconButton(
                    onPressed: () {},
                    icon: Icon(AppIcons.notification, color: isDark ? Colors.white : Colors.black87),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 16, left: 8),
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: DriftProTheme.primaryGreen.withOpacity(0.1),
                        backgroundImage: _profile?.avatarUrl != null ? NetworkImage(_profile!.avatarUrl!) : null,
                        child: _profile?.avatarUrl == null ? Text(_profile?.initials ?? '?', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: DriftProTheme.primaryGreen)) : null,
                      ),
                    ),
                  ),
                ],
              ),

              // Hero Card
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${_getGreeting()}, ${_profile?.fullName.split(' ').first ?? ''} 👋', style: DriftProTheme.headingLg.copyWith(color: Colors.white)),
                        Text(_getDateString(), style: DriftProTheme.bodyMd.copyWith(color: Colors.white70)),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            _buildMiniStat('${_stats.todayAbsences}', 'Fravær i dag', AppIcons.absence),
                            const SizedBox(width: 12),
                            _buildMiniStat('${_stats.openTickets}', 'Åpne avvik', AppIcons.ticket),
                            const SizedBox(width: 12),
                            _buildMiniStat('${_stats.absenceRate}%', 'Snitt fravær', AppIcons.chart),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Quick Actions
              SliverToBoxAdapter(
                child: SectionHeader(title: 'Hurtigvalg'),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 100,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      QuickActionButton(icon: AppIcons.survey, label: AppStrings.navSurveys, color: Colors.purple, onTap: () => widget.onNavigate?.call(1)),
                      const SizedBox(width: 12),
                      QuickActionButton(icon: AppIcons.absence, label: 'Fravær', color: DriftProTheme.absenceVacation, onTap: () => widget.onNavigate?.call(2)),
                      const SizedBox(width: 12),
                      QuickActionButton(icon: AppIcons.newTicket, label: 'Nytt avvik', color: DriftProTheme.warning, onTap: () => widget.onNavigate?.call(3)),
                      const SizedBox(width: 12),
                      QuickActionButton(icon: AppIcons.sja, label: 'Ny SJA', color: DriftProTheme.accentBlue, onTap: () => widget.onNavigate?.call(4)),
                      const SizedBox(width: 12),
                      QuickActionButton(icon: AppIcons.riskAssessment, label: 'Risiko', color: DriftProTheme.riskHigh, onTap: () => widget.onNavigate?.call(4)),
                    ],
                  ),
                ),
              ),

              // Stats Grid
              SliverToBoxAdapter(child: SectionHeader(title: 'Oversikt')),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.4),
                  delegate: SliverChildListDelegate([
                    StatCard(title: 'Fravær i dag', value: '${_stats.todayAbsences}', icon: AppIcons.absence, color: DriftProTheme.absenceVacation, onTap: () => widget.onNavigate?.call(2)),
                    StatCard(title: 'Åpne avvik', value: '${_stats.openTickets}', icon: AppIcons.ticket, color: DriftProTheme.warning, subtitle: '${_stats.criticalTickets} kritiske', isAlert: _stats.criticalTickets > 0, onTap: () => widget.onNavigate?.call(3)),
                  ]),
                ),
              ),

              // Recent Activity
              SliverToBoxAdapter(child: SectionHeader(title: 'Siste aktivitet')),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (_recentActivity.isEmpty) {
                      return const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('Ingen nylig aktivitet')));
                    }
                    final item = _recentActivity[index];
                    return _buildActivityTile(item, isDark);
                  },
                  childCount: _recentActivity.isEmpty ? 1 : _recentActivity.length,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
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
      title = item.title;
      subtitle = 'Avvik meldt';
      icon = AppIcons.ticket;
      color = DriftProTheme.warning;
    } else if (item is Absence) {
      title = item.type.label;
      subtitle = 'Fravær registrert';
      icon = AppIcons.absence;
      color = DriftProTheme.absenceVacation;
    } else if (item is SjaForm) {
      title = item.title;
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
}
