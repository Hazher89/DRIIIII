import 'package:flutter/material.dart';
import '../../core/constants/app_icons.dart';
import '../../core/constants/app_strings.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user_profile.dart';
import '../profile/profile_screen.dart';

class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  List<UserProfile> _employees = [];
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final companyId = await SupabaseService.getCurrentCompanyId();
      if (companyId == null) {
        setState(() {
          _error = 'Ingen selskap tilknyttet din profil. Kontakt administrator.';
          _isLoading = false;
        });
        return;
      }

      final employees = await SupabaseService.fetchProfiles(companyId: companyId);
      setState(() {
        _employees = employees;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Feil ved henting av ansatte: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filteredEmployees = _employees.where((e) => 
      e.fullName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
      (e.jobTitle ?? '').toLowerCase().contains(_searchQuery.toLowerCase())
    ).toList();

    return Scaffold(
      backgroundColor: isDark ? DriftProTheme.bgDark : DriftProTheme.bgLight,
      appBar: AppBar(
        title: const Text('Ansatte'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'Søk etter ansatt eller tittel...',
                prefixIcon: const Icon(Icons.search),
                fillColor: isDark ? DriftProTheme.cardDark : Colors.white,
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : RefreshIndicator(
                        onRefresh: _loadEmployees,
                        child: filteredEmployees.isEmpty
                            ? _buildEmptyState(isDark)
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                itemCount: filteredEmployees.length,
                                itemBuilder: (context, index) {
                                  final employee = filteredEmployees[index];
                                  return _buildEmployeeCard(employee, isDark);
                                },
                              ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(AppIcons.employees, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isEmpty ? 'Ingen ansatte registrert' : 'Ingen treff på søket',
            style: DriftProTheme.headingMd.copyWith(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeCard(UserProfile employee, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: DriftProTheme.cardShadow,
        border: Border.all(
          color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade100,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: Hero(
          tag: 'avatar-${employee.id}',
          child: CircleAvatar(
            radius: 24,
            backgroundImage: employee.avatarUrl != null ? NetworkImage(employee.avatarUrl!) : null,
            child: employee.avatarUrl == null ? Text(employee.initials) : null,
          ),
        ),
        title: Text(employee.fullName, style: DriftProTheme.labelLg),
        subtitle: Text(employee.jobTitle ?? 'Ansatt', style: DriftProTheme.bodySm),
        trailing: _buildRoleBadge(employee.role),
        onTap: () {
          // In a real app, we might go to a detailed employee view
          // For now, let's show a summary or allow admin to edit role
          _showEmployeeActions(employee);
        },
      ),
    );
  }

  Widget _buildRoleBadge(UserRole role) {
    Color color;
    switch (role) {
      case UserRole.superadmin: color = Colors.purple; break;
      case UserRole.admin: color = DriftProTheme.error; break;
      case UserRole.leder: color = DriftProTheme.primaryGreen; break;
      case UserRole.ansatt: color = Colors.blue; break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        role.name.toUpperCase(),
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  void _showEmployeeActions(UserProfile employee) {
    final curUser = SupabaseService.client.auth.currentUser;
    // Only allow editing if current user is admin/superadmin and not the same user
    final canEdit = (SupabaseService.client.auth.currentUser?.email == 'baxightsi@gmail.com') && (curUser?.id != employee.id);

    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(radius: 32, child: Text(employee.initials)),
            const SizedBox(height: 16),
            Text(employee.fullName, style: DriftProTheme.headingMd),
            Text(employee.email, style: DriftProTheme.bodySm),
            const SizedBox(height: 24),
            if (canEdit) ...[
              const Text('Endre rolle', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: UserRole.values.map((role) => ChoiceChip(
                  label: Text(role.name),
                  selected: employee.role == role,
                  onSelected: (selected) async {
                    if (selected) {
                      await SupabaseService.updateProfileRole(employee.id, role);
                      Navigator.pop(context);
                      _loadEmployees();
                    }
                  },
                )).toList(),
              ),
              const SizedBox(height: 24),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('LUKK'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
