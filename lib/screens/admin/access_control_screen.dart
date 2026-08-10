import 'package:flutter/material.dart';

import '../../core/permissions/access_catalog.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user_profile.dart';
import '../employees/widgets/permission_matrix_editor.dart';
import '../../widgets/driftpro_loading_indicator.dart';

/// Tilgangskontroll — samme matrise som i Ansatt-hub.
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
        setState(() => _users = users.where((u) => !u.isPartnerPortalUser).toList());
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
      appBar: AppBar(
        title: const Text('Tilgangskontroll'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadUsers),
        ],
      ),
      body: _isLoading
          ? const DriftProLoadingCenter()
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
        subtitle: Text('${user.role.name} · ${user.isApproved ? 'Godkjent' : 'Venter'}'),
        trailing: const Icon(Icons.settings_outlined, color: DriftProTheme.primaryGreen),
        onTap: () => _showAccessSettings(user),
      ),
    );
  }

  void _showAccessSettings(UserProfile user) {
    Map<String, dynamic> settings = Map<String, dynamic>.from(
      AccessCatalog.normalizeV2(user.accessSettings, user.role),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (_, scroll) => Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Tilgang for ${user.fullName}', style: DriftProTheme.headingSm),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    controller: scroll,
                    children: [
                      PermissionMatrixEditor(
                        settings: settings,
                        roleForPresets: user.role,
                        onChanged: (s) => setModalState(() => settings = s),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () async {
                      await SupabaseService.updateProfileAccess(user.id, settings);
                      if (context.mounted) Navigator.pop(context);
                      _loadUsers();
                    },
                    child: const Text('LAGRE ENDRINGER'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
