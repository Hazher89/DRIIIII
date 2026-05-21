import 'package:flutter/material.dart';
import '../../core/constants/app_icons.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/department.dart';
import '../../models/user_profile.dart';
import '../../models/ticket.dart';
import '../../models/absence.dart';
import '../employees/widgets/employee_display.dart';
import '../employees/widgets/employee_move_department_sheet.dart';

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
  final Set<String> _selectedLeaderIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _currentDept = widget.department;
    _nameController.text = _currentDept.name;
    _descController.text = _currentDept.description ?? '';
    _selectedLeaderIds
      ..clear()
      ..addAll(_currentDept.leaderIds);
    if (_selectedLeaderIds.isEmpty && _currentDept.leaderId != null) {
      _selectedLeaderIds.add(_currentDept.leaderId!);
    }
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final companyId = _currentDept.companyId;
      _allProfiles = await SupabaseService.fetchProfiles(companyId: companyId);

      final depts = await SupabaseService.fetchDepartments(companyId: companyId);
      final refreshed = depts.where((d) => d.id == _currentDept.id).firstOrNull;
      if (refreshed != null) {
        _currentDept = refreshed;
        _selectedLeaderIds
          ..clear()
          ..addAll(_currentDept.leaderIds);
        if (_selectedLeaderIds.isEmpty && _currentDept.leaderId != null) {
          _selectedLeaderIds.add(_currentDept.leaderId!);
        }
      }

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
            Tab(text: 'Ansatte'),
            Tab(text: 'Ledere'),
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
                _buildLeadersTab(isDark),
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
        Row(
          children: [
            Expanded(child: Text('Ansatte i avdelingen', style: DriftProTheme.headingMd)),
            TextButton(
              onPressed: () => _tabController.animateTo(1),
              child: const Text('Se alle'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_members.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? DriftProTheme.cardDark : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text('Ingen ansatte i denne avdelingen ennå. Legg til under fanen Ansatte.'),
          )
        else
          ..._members.take(8).map((m) => _memberCard(m, isDark, compact: true)),
        if (_members.length > 8)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('+ ${_members.length - 8} flere under Ansatte', style: DriftProTheme.caption),
          ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(child: Text('Avdelingsledere', style: DriftProTheme.headingMd)),
            TextButton(
              onPressed: () => _tabController.animateTo(2),
              child: const Text('Endre'),
            ),
          ],
        ),
        const SizedBox(height: 8),
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
    if (_selectedLeaderIds.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? DriftProTheme.cardDark : Colors.white,
          borderRadius: BorderRadius.circular(DriftProTheme.radiusLg),
        ),
        child: const Text('Ingen leder valgt — legg til under Innstillinger'),
      );
    }
    final leaders = _allProfiles.where((p) => _selectedLeaderIds.contains(p.id)).toList();
    return Column(
      children: leaders.map((leader) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? DriftProTheme.cardDark : Colors.white,
            borderRadius: BorderRadius.circular(DriftProTheme.radiusLg),
            border: Border.all(color: DriftProTheme.primaryGreen.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: DriftProTheme.primaryGreen.withValues(alpha: 0.1),
                child: Text(leader.initials, style: const TextStyle(color: DriftProTheme.primaryGreen)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(leader.fullName, style: DriftProTheme.labelLg),
                    Text(leader.email, style: DriftProTheme.bodySm),
                    if (leader.employeeNumber != null && leader.employeeNumber!.isNotEmpty)
                      Text('Ansattnr. ${leader.employeeNumber}', style: DriftProTheme.bodySm),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _memberCard(UserProfile m, bool isDark, {bool compact = false}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isDark ? DriftProTheme.cardDark : Colors.white,
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: compact ? 4 : 8,
        ),
        leading: CircleAvatar(
          backgroundColor: DriftProTheme.primaryGreen.withValues(alpha: 0.15),
          child: Text(m.initials, style: const TextStyle(color: DriftProTheme.primaryGreen)),
        ),
        title: EmployeeDisplay.nameWithNumber(m),
        subtitle: Text(
          [
            m.role.name,
            if (m.phone != null && m.phone!.isNotEmpty) m.phone!,
            if (!compact) m.email,
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: compact
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Flytt til annen avdeling',
                    icon: const Icon(Icons.swap_horiz, color: DriftProTheme.primaryGreen),
                    onPressed: () async {
                      final depts = await SupabaseService.fetchDepartments(
                        companyId: _currentDept.companyId,
                      );
                      if (!mounted) return;
                      final ok = await showEmployeeMoveDepartmentSheet(
                        context,
                        employee: m,
                        departments: depts,
                      );
                      if (ok == true) _loadData();
                    },
                  ),
                  IconButton(
                    tooltip: 'Fjern fra avdeling',
                    icon: const Icon(Icons.person_remove_outlined, color: Colors.red),
                    onPressed: () => _removeMember(m.id),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildMembersTab(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_members.length} ansatte',
                  style: DriftProTheme.headingSm,
                ),
              ),
              FilledButton.icon(
                onPressed: _showAddMemberPicker,
                icon: const Icon(Icons.person_add_alt_1, size: 18),
                label: const Text('Legg til ansatt'),
                style: FilledButton.styleFrom(
                  backgroundColor: DriftProTheme.primaryGreen,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Alle som tilhører ${_currentDept.name}. Ansattnummer brukes ved innlogging.',
            style: DriftProTheme.caption,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _members.isEmpty
              ? Center(
                  child: Text(
                    'Ingen ansatte her ennå.\nTrykk «Legg til ansatt».',
                    textAlign: TextAlign.center,
                    style: DriftProTheme.bodyMd.copyWith(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _members.length,
                  itemBuilder: (_, i) => _memberCard(_members[i], isDark),
                ),
        ),
      ],
    );
  }

  Widget _buildLeadersTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: DriftProTheme.primaryGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: DriftProTheme.primaryGreen.withValues(alpha: 0.35)),
            ),
            child: const Text(
              'Velg én eller flere ansatte som skal være leder for denne avdelingen. '
              'En leder kan også være leder for andre avdelinger (sett under Ansatte → trykk på personen → «Avdelingsleder for»).',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
          const SizedBox(height: 16),
          Text('Velg ledere', style: DriftProTheme.headingMd),
          const SizedBox(height: 12),
          _buildLeaderMultiSelect(isDark),
          const SizedBox(height: 20),
          if (_selectedLeaderIds.isNotEmpty) ...[
            Text('Valgte ledere', style: DriftProTheme.labelLg),
            const SizedBox(height: 8),
            _buildLeaderProfile(isDark),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saveLeadersOnly,
              style: FilledButton.styleFrom(
                backgroundColor: DriftProTheme.primaryGreen,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Lagre avdelingsledere', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveLeadersOnly() async {
    if (widget.isNew) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lagre avdelingen først (øverst til høyre)')),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      await SupabaseService.setDepartmentLeaders(
        _currentDept.id,
        _selectedLeaderIds.toList(),
      );
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Avdelingsledere lagret')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
           const SizedBox(height: 12),
           ListTile(
             contentPadding: EdgeInsets.zero,
             leading: const Icon(Icons.groups_2_outlined, color: DriftProTheme.primaryGreen),
             title: const Text('Avdelingsledere'),
             subtitle: const Text('Administreres under fanen «Ledere»'),
             trailing: const Icon(Icons.chevron_right),
             onTap: () => _tabController.animateTo(2),
           ),
           const SizedBox(height: 24),
           Center(child: TextButton(onPressed: _confirmDelete, child: const Text('Slett Avdeling', style: TextStyle(color: Colors.red)))),
        ],
      ),
    );
  }

  Widget _buildLeaderMultiSelect(bool isDark) {
    final candidates = _allProfiles
        .where((p) => p.role != UserRole.samarbeidspartner && p.isApproved)
        .toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: candidates.map((p) {
        final selected = _selectedLeaderIds.contains(p.id);
        final label = p.employeeNumber != null && p.employeeNumber!.isNotEmpty
            ? '${p.fullName} (${p.employeeNumber})'
            : p.fullName;
        return FilterChip(
          label: Text(label),
          selected: selected,
          onSelected: (v) {
            setState(() {
              if (v) {
                _selectedLeaderIds.add(p.id);
              } else {
                _selectedLeaderIds.remove(p.id);
              }
            });
          },
        );
      }).toList(),
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
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Navn må fylles ut')));
      return;
    }

    setState(() => _isLoading = true);
    try {
      final primaryLeader =
          _selectedLeaderIds.isEmpty ? null : _selectedLeaderIds.first;

      final updated = Department(
        id: _currentDept.id,
        companyId: _currentDept.companyId,
        name: _nameController.text,
        description: _descController.text,
        leaderId: primaryLeader,
        leaderIds: _selectedLeaderIds.toList(),
        colorCode: _currentDept.colorCode,
        iconName: _currentDept.iconName,
      );

      if (widget.isNew) {
        final created = await SupabaseService.createDepartment(updated);
        if (_selectedLeaderIds.isNotEmpty) {
          await SupabaseService.setDepartmentLeaders(
            created.id,
            _selectedLeaderIds.toList(),
          );
        }
      } else {
        await SupabaseService.updateDepartment(updated);
        await SupabaseService.setDepartmentLeaders(
          _currentDept.id,
          _selectedLeaderIds.toList(),
        );
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Avdeling lagret!'), backgroundColor: Colors.green));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Feil ved lagring: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _showAddMemberPicker() {
    showModalBottomSheet(context: context, builder: (_) => ListView(
      children: _allProfiles.where((p) => p.departmentId != _currentDept.id).map((p) => ListTile(
        title: Text(p.fullName),
        subtitle: p.employeeNumber != null && p.employeeNumber!.isNotEmpty
            ? Text('Ansattnr. ${p.employeeNumber}')
            : null,
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
