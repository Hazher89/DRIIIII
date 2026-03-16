import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/supabase_service.dart';
import '../../../models/user_profile.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  bool _isLoading = true;
  List<UserProfile> _users = [];

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
        setState(() {
          _users = users;
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
          ? const Center(child: CircularProgressIndicator())
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
        subtitle: Text(user.email),
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
          ],
        ),
      ),
    );
  }
}
