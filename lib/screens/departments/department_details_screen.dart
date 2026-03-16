import 'package:flutter/material.dart';
import '../../core/constants/app_icons.dart';
import '../../core/constants/app_strings.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/department.dart';
import '../../models/user_profile.dart';
import '../../models/ticket.dart';
import '../../models/absence.dart';

class DepartmentDetailsScreen extends StatefulWidget {
  final Department department;
  final bool isNew;

  const DepartmentDetailsScreen({
    super.key,
    required this.department,
    this.isNew = false,
  });

  @override
  State<DepartmentDetailsScreen> createState() => _DepartmentDetailsScreenState();
}

class _DepartmentDetailsScreenState extends State<DepartmentDetailsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Department _currentDept;
  List<UserProfile> _allProfiles = [];
  List<UserProfile> _members = [];
  List<Ticket> _tickets = [];
  List<Absence> _absences = [];
  Map<String, AbsenceQuota> _memberQuotas = {};
  bool _isLoading = true;
  
  // Controllers for editing
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  String? _selectedLeaderId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _currentDept = widget.department;
    _nameController.text = _currentDept.name;
    _descController.text = _currentDept.description ?? '';
    _selectedLeaderId = _currentDept.leaderId;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final companyId = _currentDept.companyId;
      _allProfiles = await SupabaseService.fetchProfiles(companyId: companyId);
      
      if (!widget.isNew) {
        _members = await SupabaseService.fetchProfiles(
          companyId: companyId,
          departmentId: _currentDept.id,
        );
        
        final tickets = await SupabaseService.fetchTickets(companyId: companyId);
        _tickets = tickets.where((t) => t.departmentId == _currentDept.id).toList();
        
        final absences = await SupabaseService.fetchAbsences(companyId: companyId);
        _absences = absences.where((a) => _members.any((m) => m.id == a.userId)).toList();

        // Fetch quotas for members
        for (var member in _members) {
          final q = await SupabaseService.fetchAbsenceQuota(userId: member.id);
          if (q != null) _memberQuotas[member.id] = q;
        }
      }

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Error: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? DriftProTheme.bgDark : DriftProTheme.bgLight,
      appBar: AppBar(
        title: Text(widget.isNew ? 'Ny Avdeling' : _currentDept.name),
        actions: [
          TextButton(
            onPressed: _saveDepartment,
            child: const Text('Lagre', style: TextStyle(color: DriftProTheme.primaryGreen)),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Oversikt'),
            Tab(text: 'Medlemmer'),
            Tab(text: 'Kvoter'),
            Tab(text: 'Aktivitet'),
            Tab(text: 'Innstillinger'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(isDark),
                _buildMembersTab(isDark),
                _buildQuotasTab(isDark),
                _buildActivityTab(isDark),
                _buildSettingsTab(isDark),
              ],
            ),
    );
  }

  Widget _buildOverviewTab(bool isDark) {
    if (widget.isNew) return const Center(child: Text('Lagre avdelingen først'));
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(child: _buildStatCard('Medlemmer', _members.length.toString(), Icons.people_outline, Colors.blue, isDark)),
            const SizedBox(width: 12),
            Expanded(child: _buildStatCard('Åpne Avvik', _tickets.where((t) => t.status != TicketStatus.lukket).length.toString(), AppIcons.error, Colors.orange, isDark)),
          ],
        ),
        const SizedBox(height: 12),
        _buildStatCard('Fravær i dag', _absences.where((a) => a.isActive).length.toString(), AppIcons.absence, Colors.teal, isDark),
        const SizedBox(height: 24),
        Text('Avdelingsleder', style: DriftProTheme.headingMd),
        const SizedBox(height: 12),
        _buildLeaderProfile(isDark),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: isDark ? DriftProTheme.cardDark : Colors.white, borderRadius: BorderRadius.circular(DriftProTheme.radiusLg), boxShadow: DriftProTheme.cardShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 12),
          Text(value, style: DriftProTheme.headingLg),
          Text(label, style: DriftProTheme.bodySm.copyWith(color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _buildLeaderProfile(bool isDark) {
    final leader = _allProfiles.firstWhere((p) => p.id == _selectedLeaderId, orElse: () => _allProfiles.first);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: isDark ? DriftProTheme.cardDark : Colors.white, borderRadius: BorderRadius.circular(DriftProTheme.radiusLg), border: Border.all(color: DriftProTheme.primaryGreen.withOpacity(0.3))),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: DriftProTheme.primaryGreen.withOpacity(0.1), child: Text(leader.initials, style: const TextStyle(color: DriftProTheme.primaryGreen))),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(leader.fullName, style: DriftProTheme.labelLg), Text(leader.email, style: DriftProTheme.bodySm)])),
        ],
      ),
    );
  }

  Widget _buildMembersTab(bool isDark) {
    return Column(
      children: [
        Padding(padding: const EdgeInsets.all(16), child: Row(children: [Text('${_members.length} Medlemmer', style: DriftProTheme.labelLg), const Spacer(), ElevatedButton(onPressed: _showAddMemberPicker, child: const Text('Legg til'))])),
        Expanded(
          child: ListView.builder(
            itemCount: _members.length,
            itemBuilder: (context, index) {
              final m = _members[index];
              return ListTile(
                leading: CircleAvatar(child: Text(m.initials)),
                title: Text(m.fullName),
                subtitle: Text(m.role.name),
                trailing: IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.red), onPressed: () => _removeMember(m.id)),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildQuotasTab(bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _members.length,
      itemBuilder: (context, index) {
        final m = _members[index];
        final q = _memberQuotas[m.id];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: isDark ? DriftProTheme.cardDark : Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade100)),
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(radius: 16, child: Text(m.initials, style: const TextStyle(fontSize: 10))),
                  const SizedBox(width: 12),
                  Expanded(child: Text(m.fullName, style: DriftProTheme.labelLg)),
                  IconButton(icon: const Icon(Icons.edit_note_rounded), onPressed: () => _editQuota(m)),
                ],
              ),
              const Divider(),
              if (q != null) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _miniQuota('Ferie', '${q.vacationDaysUsed}/${q.totalVacationDays}'),
                    _miniQuota('Egenm.', '${q.egenmeldingDaysUsed}/24'),
                    _miniQuota('Sykt barn', '${q.syktBarnDaysUsed}/10'),
                  ],
                ),
              ] else 
                const Text('Ingen kvote satt opp', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        );
      },
    );
  }

  Widget _miniQuota(String label, String value) {
    return Column(children: [Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)), Text(value, style: const TextStyle(fontWeight: FontWeight.bold))]);
  }

  Widget _buildActivityTab(bool isDark) {
    final items = [..._tickets, ..._absences];
    if (items.isEmpty) return const Center(child: Text('Ingen aktivitet ennå'));
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final isTicket = item is Ticket;
        return ListTile(
          leading: Icon(isTicket ? AppIcons.error : AppIcons.absence, color: isTicket ? Colors.orange : Colors.teal),
          title: Text(isTicket ? 'Avvik: ${item.title}' : 'Fravær: ${(item as Absence).type.label}'),
          subtitle: Text(isTicket ? 'Av ${item.reporterName}' : 'Av ${(item as Absence).userName}'),
          trailing: Text(isTicket ? item.status.name : (item as Absence).status.label),
        );
      },
    );
  }

  Widget _buildSettingsTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
           const Text('Navn'),
           TextField(controller: _nameController),
           const SizedBox(height: 20),
           const Text('Beskrivelse'),
           TextField(controller: _descController, maxLines: 2),
           const SizedBox(height: 20),
           const Text('Leder'),
           _buildLeaderDropdown(isDark),
           const SizedBox(height: 40),
           Center(child: TextButton(onPressed: _confirmDelete, child: const Text('Slett Avdeling', style: TextStyle(color: Colors.red)))),
        ],
      ),
    );
  }

  Widget _buildLeaderDropdown(bool isDark) {
    return DropdownButtonFormField<String>(
      value: _selectedLeaderId,
      items: _allProfiles.map((p) => DropdownMenuItem(value: p.id, child: Text(p.fullName))).toList(),
      onChanged: (val) => setState(() => _selectedLeaderId = val),
    );
  }

  void _editQuota(UserProfile user) {
    final q = _memberQuotas[user.id] ?? AbsenceQuota(id: '', userId: user.id, year: DateTime.now().year);
    final controller = TextEditingController(text: q.vacationDaysTotal.toString());
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Endre ferie: ${user.fullName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Totalt antall feriedager per år:'),
            TextField(controller: controller, keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Avbryt')),
          TextButton(
            onPressed: () async {
              final newTotal = int.tryParse(controller.text) ?? 25;
              if (q.id.isEmpty) {
                await SupabaseService.createAbsenceQuota(AbsenceQuota(id: '', userId: user.id, year: q.year, vacationDaysTotal: newTotal));
              } else {
                await SupabaseService.updateAbsenceQuota(user.id, q.year, {'vacation_days_total': newTotal});
              }
              Navigator.pop(context);
              _loadData();
            },
            child: const Text('Lagre'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveDepartment() async {
    final updated = Department(
      id: _currentDept.id,
      companyId: _currentDept.companyId,
      name: _nameController.text,
      description: _descController.text,
      leaderId: _selectedLeaderId,
      colorCode: _currentDept.colorCode,
      iconName: _currentDept.iconName,
    );
    if (widget.isNew) await SupabaseService.createDepartment(updated);
    else await SupabaseService.updateDepartment(updated);
    if (mounted) Navigator.pop(context);
  }

  void _showAddMemberPicker() {
    showModalBottomSheet(context: context, builder: (_) => ListView(
      children: _allProfiles.where((p) => p.departmentId != _currentDept.id).map((p) => ListTile(
        title: Text(p.fullName),
        onTap: () async {
           await SupabaseService.updateProfileDepartment(p.id, _currentDept.id);
           Navigator.pop(context);
           _loadData();
        },
      )).toList(),
    ));
  }

  Future<void> _removeMember(String id) async {
    await SupabaseService.updateProfileDepartment(id, null);
    _loadData();
  }

  void _confirmDelete() {
    showDialog(context: context, builder: (_) => AlertDialog(title: const Text('Slett?'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Nei')), TextButton(onPressed: () async { await SupabaseService.deleteDepartment(_currentDept.id); Navigator.pop(context); Navigator.pop(context); }, child: const Text('Ja'))]));
  }
}
