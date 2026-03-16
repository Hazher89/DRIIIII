import 'package:flutter/material.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user_profile.dart';

class AccessControlScreen extends StatefulWidget {
  const AccessControlScreen({super.key});

  @override
  State<AccessControlScreen> createState() => _AccessControlScreenState();
}

class _AccessControlScreenState extends State<AccessControlScreen> {
  List<UserProfile> _users = [];
  bool _isLoading = true;

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
        setState(() => _users = users);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? DriftProTheme.bgDark : DriftProTheme.bgLight,
      appBar: AppBar(title: const Text('Tilgangskontroll')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _users.length,
              itemBuilder: (context, index) {
                final user = _users[index];
                return _buildUserTile(user, isDark);
              },
            ),
    );
  }

  Widget _buildUserTile(UserProfile user, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade100),
      ),
      child: ListTile(
        leading: CircleAvatar(child: Text(user.initials)),
        title: Text(user.fullName),
        subtitle: Text('Rolle: ${user.role.name}'),
        trailing: const Icon(Icons.settings_outlined, color: DriftProTheme.primaryGreen),
        onTap: () => _showAccessSettings(user),
      ),
    );
  }

  void _showAccessSettings(UserProfile user) {
    // Default settings
    Map<String, dynamic> settings = Map<String, dynamic>.from(user.accessSettings ?? {
      'hms': true,
      'fravaer': true,
      'avvik': true,
      'avdelinger': user.isAdmin,
      'ansatte': user.isAdmin,
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 24),
              Text('Tilgang for ${user.fullName}', style: DriftProTheme.headingSm),
              const Divider(height: 32),
              
              _buildToggle('HMS Modul', 'hms', settings, setModalState),
              _buildToggle('Fravær & Ferie', 'fravaer', settings, setModalState),
              _buildToggle('Avvikshåndtering', 'avvik', settings, setModalState),
              _buildToggle('Avdelingsstyring', 'avdelinger', settings, setModalState),
              _buildToggle('Ansattliste', 'ansatte', settings, setModalState),
              
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () async {
                    await SupabaseService.updateProfileAccess(user.id, settings);
                    Navigator.pop(context);
                    _loadUsers();
                  },
                  child: const Text('LAGRE ENDRINGER'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToggle(String title, String key, Map<String, dynamic> settings, StateSetter setState) {
    return SwitchListTile.adaptive(
      title: Text(title, style: DriftProTheme.labelLg),
      value: settings[key] ?? false,
      activeColor: DriftProTheme.primaryGreen,
      onChanged: (val) => setState(() => settings[key] = val),
    );
  }
}
