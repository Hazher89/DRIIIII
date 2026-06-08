import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/supabase_service.dart';
import '../../../models/department.dart';
import '../../../models/user_profile.dart';
import '../../widgets/driftpro_loading_indicator.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  bool _isLoading = true;
  List<UserProfile> _users = [];
  List<Department> _departments = [];
  UserProfile? _me;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);
    try {
      final companyId = await SupabaseService.getCurrentCompanyId();
      if (companyId != null) {
        final users = await SupabaseService.fetchProfiles(companyId: companyId);
        final depts = await SupabaseService.fetchDepartments(companyId: companyId);
        final me = await SupabaseService.fetchCurrentUserProfile();
        setState(() {
          _users = users;
          _departments = depts;
          _me = me;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil ved henting av brukere: $e')),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleApproval(UserProfile user) async {
    try {
      await SupabaseService.client
          .from('profiles')
          .update({'is_approved': !user.isApproved})
          .eq('id', user.id);
      _loadUsers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke oppdatere bruker: $e')),
        );
      }
    }
  }

  Future<void> _editUser(UserProfile user) async {
    final nameCtrl = TextEditingController(text: user.fullName);
    final phoneCtrl = TextEditingController(text: user.phone ?? '');
    final emergencyNameCtrl = TextEditingController(text: user.emergencyContactName ?? '');
    final emergencyPhoneCtrl = TextEditingController(text: user.emergencyContactPhone ?? '');
    UserRole selectedRole = user.role;
    String? selectedDepartment = user.departmentId;
    DateTime? birthDate = user.birthDate;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Rediger bruker'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Navn')),
                  const SizedBox(height: 8),
                  TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Telefon')),
                  const SizedBox(height: 8),
                  TextField(controller: emergencyNameCtrl, decoration: const InputDecoration(labelText: 'Pårørende navn')),
                  const SizedBox(height: 8),
                  TextField(controller: emergencyPhoneCtrl, decoration: const InputDecoration(labelText: 'Pårørende telefon')),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      birthDate == null
                          ? 'Fødselsdato'
                          : 'Fødselsdato: ${birthDate!.day}.${birthDate!.month}.${birthDate!.year}',
                    ),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: birthDate ?? DateTime(DateTime.now().year - 30),
                        firstDate: DateTime(1900),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setSt(() => birthDate = picked);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: selectedDepartment,
                    hint: const Text('Velg avdeling'),
                    items: _departments
                        .map((d) => DropdownMenuItem<String>(value: d.id, child: Text(d.name)))
                        .toList(),
                    onChanged: (v) => setSt(() => selectedDepartment = v),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<UserRole>(
                    value: selectedRole,
                    items: UserRole.values
                        .map((r) => DropdownMenuItem(value: r, child: Text(r.name)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setSt(() => selectedRole = v);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lagre')),
          ],
        ),
      ),
    );

    if (ok == true) {
      await SupabaseService.updateProfileAdminFields(
        user.id,
        fullName: nameCtrl.text.trim(),
        phone: phoneCtrl.text.trim(),
        emergencyContactName: emergencyNameCtrl.text.trim(),
        emergencyContactPhone: emergencyPhoneCtrl.text.trim(),
        departmentId: selectedDepartment,
        role: selectedRole,
        birthDate: birthDate,
      );
      await _loadUsers();
    }
  }

  Future<void> _deleteUser(UserProfile user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slett bruker permanent?'),
        content: Text(
          'Dette sletter ${user.fullName} fra auth og hele systemet. Handlingen kan ikke angres.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Slett permanent', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await SupabaseService.deleteUserPermanently(user.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${user.fullName} ble slettet permanent')),
        );
      }
      await _loadUsers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sletting feilet: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? DriftProTheme.surfaceDark : DriftProTheme.bgLight,
      appBar: AppBar(
        title: const Text('Brukeradministrasjon'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadUsers),
        ],
      ),
      body: _isLoading
          ? const DriftProLoadingCenter()
          : _users.isEmpty
              ? const Center(child: Text('Ingen brukere funnet'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _users.length,
                  itemBuilder: (context, index) {
                    final user = _users[index];
                    return _buildUserCard(user, isDark);
                  },
                ),
    );
  }

  Widget _buildUserCard(UserProfile user, bool isDark) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isDark ? DriftProTheme.cardDark : Colors.white,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: DriftProTheme.primaryGreen.withOpacity(0.1),
          child: Text(user.initials, style: const TextStyle(color: DriftProTheme.primaryGreen)),
        ),
        title: Text(user.fullName, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          '${user.email}\nRolle: ${user.role.name}${user.departmentId != null ? ' · Avdeling satt' : ''}',
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!user.isApproved)
              ElevatedButton(
                onPressed: () => _toggleApproval(user),
                style: ElevatedButton.styleFrom(
                  backgroundColor: DriftProTheme.primaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: const Text('Godkjenn'),
              )
            else
              TextButton(
                onPressed: () => _toggleApproval(user),
                child: const Text('Fjern tilgang', style: TextStyle(color: Colors.red)),
              ),
            IconButton(
              tooltip: 'Rediger',
              onPressed: () => _editUser(user),
              icon: const Icon(Icons.edit_outlined),
            ),
            if ((_me?.isAdmin == true) && (_me?.id != user.id))
              IconButton(
                tooltip: 'Slett permanent',
                onPressed: () => _deleteUser(user),
                icon: const Icon(Icons.delete_forever_outlined, color: Colors.red),
              ),
          ],
        ),
      ),
    );
  }
}
