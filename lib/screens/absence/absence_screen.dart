import 'package:flutter/material.dart';
import '../../core/constants/app_icons.dart';
import '../../core/constants/app_strings.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/absence.dart';
import '../../models/user_profile.dart';
import 'new_absence_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class AbsenceScreen extends StatefulWidget {
  const AbsenceScreen({super.key});

  @override
  State<AbsenceScreen> createState() => _AbsenceScreenState();
}

class _AbsenceScreenState extends State<AbsenceScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  List<Absence> _myAbsences = [];
  List<Absence> _deptAbsences = [];
  List<Absence> _pendingApprovals = [];
  AbsenceQuota? _quota;
  UserProfile? _profile;
  bool _isLoading = true;
  DateTime _calendarMonth = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    try {
      final profile = await SupabaseService.fetchCurrentUserProfile();
      if (profile != null) {
        _profile = profile;
        final futures = await Future.wait([
          SupabaseService.fetchAbsences(userId: profile.id),
          SupabaseService.fetchAbsences(companyId: profile.companyId),
          SupabaseService.fetchAbsenceQuota(userId: profile.id),
        ]);

        final mine = futures[0] as List<Absence>;
        final allInCompany = futures[1] as List<Absence>;

        setState(() {
          _myAbsences = mine;
          _deptAbsences = allInCompany.where((a) => a.status == AbsenceStatus.godkjent).toList();
          
          if (profile.isLeader || profile.isAdmin) {
            _pendingApprovals = allInCompany.where((a) => 
               a.status == AbsenceStatus.ventende && a.userId != profile.id
            ).toList();
            
            if (_tabController.length == 3) {
              _tabController = TabController(length: 4, vsync: this);
            }
          }
          
          _quota = futures[2] as AbsenceQuota?;
        });
      }
    } catch (e) {
      debugPrint('Error loading absence data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color _getAbsenceColor(AbsenceType type) {
    switch (type) {
      case AbsenceType.ferie: return DriftProTheme.absenceVacation;
      case AbsenceType.egenmelding: return DriftProTheme.absenceSickSelf;
      case AbsenceType.syktBarn: return DriftProTheme.absenceSickChild;
      case AbsenceType.permisjon: return DriftProTheme.absenceLeave;
      case AbsenceType.sykmelding: return DriftProTheme.absenceSickNote;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_profile == null && _isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isManager = _profile?.isLeader == true || _profile?.isAdmin == true;

    return Scaffold(
      backgroundColor: isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(
        title: const Text('Fravær & Ferie'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: DriftProTheme.primaryGreen,
          isScrollable: isManager,
          tabs: [
            const Tab(text: 'Mine'),
            if (isManager) const Tab(text: 'Håndtering'),
            const Tab(text: 'Kalender'),
            const Tab(text: 'Kvote'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showRegisterOptions(context),
        label: const Text('Registrer fravær'),
        icon: const Icon(Icons.add),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildMyAbsences(isDark),
          if (isManager) _buildHandlingTab(isDark),
          _buildCalendarView(isDark),
          _buildQuotaView(isDark),
        ],
      ),
    );
  }

  Widget _buildMyAbsences(bool isDark) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_myAbsences.isEmpty) return _buildEmptyState('Ingen fravær registrert ennå.');

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _myAbsences.length,
      itemBuilder: (context, index) {
        final a = _myAbsences[index];
        final days = a.endDate.difference(a.startDate).inDays + 1;
        return _buildAbsenceCard(a, days, isDark, showActions: false);
      },
    );
  }

  Widget _buildHandlingTab(bool isDark) {
    if (_pendingApprovals.isEmpty) return _buildEmptyState('Ingen ventende forespørsler.');

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _pendingApprovals.length,
      itemBuilder: (context, index) {
        final a = _pendingApprovals[index];
        final days = a.endDate.difference(a.startDate).inDays + 1;
        return _buildAbsenceCard(a, days, isDark, showActions: true);
      },
    );
  }

  Widget _buildAbsenceCard(Absence a, int days, bool isDark, {required bool showActions}) {
    final color = _getAbsenceColor(a.type);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade100),
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: Container(
              width: 48, height: 48,
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
              child: Icon(_getIconForType(a.type), color: color),
            ),
            title: Row(
              children: [
                Expanded(child: Text(a.type.label, style: DriftProTheme.labelLg)),
                _buildStatusBadge(a.status),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (a.userName != null) Text('Fra: ${a.userName!}', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('${DateFormat('d. MMM').format(a.startDate)} - ${DateFormat('d. MMM').format(a.endDate)} ($days dager)', style: DriftProTheme.bodySm),
                if (a.comment != null) Text('"${a.comment!}"', style: DriftProTheme.bodySm.copyWith(fontStyle: FontStyle.italic)),
              ],
            ),
          ),
          if (showActions)
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
                      style: ElevatedButton.styleFrom(backgroundColor: DriftProTheme.success),
                      child: const Text('Godkjenn'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _updateStatus(String id, AbsenceStatus status) async {
    try {
      await SupabaseService.updateAbsenceStatus(id, status);
      _loadAllData();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Feil: $e')));
    }
  }

  Widget _buildStatusBadge(AbsenceStatus status) {
    Color color;
    switch (status) {
      case AbsenceStatus.godkjent: color = DriftProTheme.success; break;
      case AbsenceStatus.avvist: color = DriftProTheme.error; break;
      case AbsenceStatus.ventende: color = DriftProTheme.warning; break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
      child: Text(status.label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildCalendarView(bool isDark) {
    return Column(
      children: [
        _buildCalendarHeader(isDark),
        Expanded(child: _buildCalendarGrid(isDark)),
        _buildCalendarLegend(isDark),
      ],
    );
  }

  Widget _buildCalendarHeader(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month - 1))),
          Text(DateFormat('MMMM yyyy').format(_calendarMonth), style: DriftProTheme.headingSm),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => setState(() => _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month + 1))),
        ],
      ),
    );
  }

  Widget _buildCalendarGrid(bool isDark) {
    final daysInMonth = DateUtils.getDaysInMonth(_calendarMonth.year, _calendarMonth.month);
    final firstDay = DateTime(_calendarMonth.year, _calendarMonth.month, 1);
    final firstWeekday = firstDay.weekday - 1;

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, childAspectRatio: 1),
      itemCount: 42,
      itemBuilder: (context, index) {
        if (index < firstWeekday || index >= daysInMonth + firstWeekday) return const SizedBox();
        final day = index - firstWeekday + 1;
        final date = DateTime(_calendarMonth.year, _calendarMonth.month, day);
        
        final dayAbsences = _deptAbsences.where((a) =>
            !date.isBefore(DateTime(a.startDate.year, a.startDate.month, a.startDate.day)) &&
            !date.isAfter(DateTime(a.endDate.year, a.endDate.month, a.endDate.day))).toList();

        return Column(
          children: [
            Text('$day', style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87)),
            const SizedBox(height: 2),
            Wrap(
              spacing: 2, runSpacing: 2,
              children: dayAbsences.take(3).map((a) => Container(
                width: 6, height: 6,
                decoration: BoxDecoration(color: _getAbsenceColor(a.type), shape: BoxShape.circle),
              )).toList(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCalendarLegend(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: isDark ? DriftProTheme.cardDark : Colors.white, border: Border(top: BorderSide(color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade100))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: AbsenceType.values.take(3).map((t) => Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: _getAbsenceColor(t), shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(t.label, style: const TextStyle(fontSize: 10)),
        ])).toList(),
      ),
    );
  }

  Widget _buildQuotaView(bool isDark) {
    if (_quota == null) return const Center(child: Text('Laster kvote...'));
    final total = _quota!.totalVacationDays;
    final used = _quota!.vacationDaysUsed;
    final remaining = total - used;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _buildQuotaCircle(used, total, remaining, isDark),
          const SizedBox(height: 32),
          _buildQuotaDetailRow('Egenmelding', _quota!.egenmeldingDaysUsed, 24, DriftProTheme.absenceSickSelf, isDark),
          const SizedBox(height: 12),
          _buildQuotaDetailRow('Sykt barn', _quota!.syktBarnDaysUsed, 10, DriftProTheme.absenceSickChild, isDark),
        ],
      ),
    );
  }

  Widget _buildQuotaCircle(int used, int total, int remaining, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(color: DriftProTheme.primaryGreen.withOpacity(0.05), borderRadius: BorderRadius.circular(24)),
      child: Column(
        children: [
          Text('Gjenstående ferie', style: DriftProTheme.bodyMd),
          const SizedBox(height: 8),
          Text('$remaining', style: DriftProTheme.headingXl.copyWith(fontSize: 64, color: DriftProTheme.primaryGreen)),
          Text('av $total dager', style: DriftProTheme.caption),
        ],
      ),
    );
  }

  Widget _buildQuotaDetailRow(String label, int used, int total, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: isDark ? DriftProTheme.cardDark : Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade100)),
      child: Column(
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: DriftProTheme.labelLg), Text('$used/$total dager', style: DriftProTheme.bodySm)]),
          const SizedBox(height: 12),
          ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: used / total, backgroundColor: color.withOpacity(0.1), valueColor: AlwaysStoppedAnimation(color), minHeight: 8)),
        ],
      ),
    );
  }

  IconData _getIconForType(AbsenceType t) {
    switch (t) {
      case AbsenceType.ferie: return Icons.wb_sunny_rounded;
      case AbsenceType.egenmelding: return Icons.person_outline_rounded;
      case AbsenceType.syktBarn: return Icons.child_care_rounded;
      case AbsenceType.permisjon: return Icons.timer_outlined;
      case AbsenceType.sykmelding: return Icons.medical_services_outlined;
    }
  }

  void _showRegisterOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: AbsenceType.values.map((t) => ListTile(
            leading: Icon(_getIconForType(t), color: _getAbsenceColor(t)),
            title: Text(t.label),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => NewAbsenceScreen(type: t))).then((v) { if (v == true) _loadAllData(); });
            },
          )).toList(),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String msg) {
    return Center(child: Text(msg, style: DriftProTheme.bodyMd.copyWith(color: Colors.grey)));
  }
}
