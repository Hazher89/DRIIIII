import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_icons.dart';
import '../../models/user_profile.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile? _profile;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    try {
      final profile = await SupabaseService.fetchCurrentUserProfile();
      setState(() => _profile = profile);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_profile == null) {
      return const Scaffold(body: Center(child: Text('Kunne ikke laste profil')));
    }

    return Scaffold(
      backgroundColor: isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(
        title: const Text('Min Profil'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Profile Header
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: DriftProTheme.primaryGreen.withOpacity(0.15),
                    backgroundImage: _profile!.avatarUrl != null ? NetworkImage(_profile!.avatarUrl!) : null,
                    child: _profile!.avatarUrl == null 
                      ? Text(_profile!.initials, style: DriftProTheme.headingXl.copyWith(color: DriftProTheme.primaryGreen, fontSize: 32))
                      : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _profile!.fullName,
                    style: DriftProTheme.headingLg,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _profile!.jobTitle ?? 'Ansatt',
                    style: DriftProTheme.bodyMd.copyWith(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Profile Details
            _buildInfoSection(isDark, [
              _buildInfoTile(AppIcons.profile, 'E-post', _profile!.email, isDark),
              _buildInfoTile(Icons.phone_rounded, 'Telefon', _profile!.phone ?? 'Ikke satt', isDark),
              _buildInfoTile(Icons.badge_rounded, 'Ansattnummer', _profile!.employeeNumber ?? 'Ikke satt', isDark),
              _buildInfoTile(AppIcons.department, 'Avdeling', _profile!.departmentId ?? 'Ingen avdeling', isDark),
            ]),
            
            const SizedBox(height: 24),

            // Settings Section
            _buildInfoSection(isDark, [
              _buildActionTile(Icons.lock_outline_rounded, 'Endre passord', () {}, isDark),
              _buildActionTile(Icons.notifications_none_rounded, 'Varslinginnstillinger', () {}, isDark),
              _buildActionTile(Icons.security_rounded, 'Personvern og sikkerhet', () {}, isDark),
            ]),

            const SizedBox(height: 32),
            
            // Logout Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await Supabase.instance.client.auth.signOut();
                },
                icon: const Icon(AppIcons.logout),
                label: const Text('Logg ut'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: DriftProTheme.error,
                  side: const BorderSide(color: DriftProTheme.error),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoSection(bool isDark, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(DriftProTheme.radiusLg),
        border: Border.all(color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade100),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildInfoTile(IconData icon, String label, String value, bool isDark) {
    return ListTile(
      leading: Icon(icon, color: DriftProTheme.primaryGreen, size: 22),
      title: Text(label, style: DriftProTheme.caption),
      subtitle: Text(value, style: DriftProTheme.bodyMd.copyWith(fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildActionTile(IconData icon, String label, VoidCallback onTap, bool isDark) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: isDark ? Colors.grey[400] : Colors.grey[600], size: 22),
      title: Text(label, style: DriftProTheme.bodyMd),
      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
    );
  }
}
