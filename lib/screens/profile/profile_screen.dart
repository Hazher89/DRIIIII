import 'package:flutter/material.dart';
import '../../core/auth/session_sign_out.dart';
import '../../core/permissions/user_access.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_icons.dart';
import '../../models/user_profile.dart';
import 'employee_change_password_sheet.dart';
import 'widgets/profile_children_under_12_card.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile? _profile;
  String? _departmentName;
  bool _isLoading = true;

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    try {
      final profile = await SupabaseService.fetchCurrentUserProfile();
      String? departmentName;
      if (profile?.departmentId != null) {
        final companyId =
            profile!.companyId ?? await SupabaseService.discoverBootstrapCompanyId();
        if (companyId != null) {
          final depts = await SupabaseService.fetchDepartments(companyId: companyId);
          for (final d in depts) {
            if (d.id == profile.departmentId) {
              departmentName = d.name;
              break;
            }
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _departmentName = departmentName;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
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
      backgroundColor:
          isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(
        title: const Text('Min Profil'),
        centerTitle: true,
      ),
      body: _buildProfileBody(isDark),
    );
  }

  Widget _buildProfileBody(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor:
                      DriftProTheme.primaryGreen.withValues(alpha: 0.15),
                  backgroundImage: _profile!.avatarUrl != null
                      ? NetworkImage(_profile!.avatarUrl!)
                      : null,
                  child: _profile!.avatarUrl == null
                      ? Text(
                          _profile!.initials,
                          style: DriftProTheme.headingXl.copyWith(
                            color: DriftProTheme.primaryGreen,
                            fontSize: 32,
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 16),
                Text(_profile!.fullName, style: DriftProTheme.headingLg),
                const SizedBox(height: 4),
                Text(
                  _profile!.jobTitle ?? 'Ansatt',
                  style: DriftProTheme.bodyMd.copyWith(color: Colors.grey[600]),
                ),
                if (_profile!.isSuperAdmin) ...[
                  const SizedBox(height: 8),
                  Chip(
                    avatar: const Icon(Icons.admin_panel_settings, size: 18),
                    label: const Text('Superadmin'),
                    backgroundColor:
                        DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (_profile!.partnerId == null)
            ProfileChildrenUnder12Card(
              profile: _profile!,
              onSaved: _loadProfile,
            ),
          const SizedBox(height: 32),
          _buildInfoSection(isDark, [
            _buildInfoTile(
              AppIcons.profile,
              'E-post',
              _profile!.email,
              isDark,
            ),
            _buildInfoTile(
              Icons.phone_rounded,
              'Telefon',
              _profile!.phone ?? 'Ikke satt',
              isDark,
            ),
            _buildInfoTile(
              Icons.badge_rounded,
              'Ansattnummer',
              _profile!.employeeNumber ?? 'Ikke satt',
              isDark,
            ),
            _buildInfoTile(
              AppIcons.department,
              'Avdeling',
              _departmentName ?? (_profile!.departmentId != null ? 'Ukjent avdeling' : 'Ingen avdeling'),
              isDark,
            ),
          ]),
          const SizedBox(height: 24),
          _buildInfoSection(isDark, [
            if (_profile!.partnerId == null)
              _buildActionTile(
                Icons.lock_outline_rounded,
                'Bytt passord (SMS bekreftelse)',
                () => showEmployeeChangePasswordSheet(context),
                isDark,
              ),
            _buildActionTile(
              Icons.security_rounded,
              'Personvern og sikkerhet',
              () {},
              isDark,
            ),
          ]),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                await signOutFromPortal(context);
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
    );
  }

  Widget _buildInfoSection(bool isDark, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(DriftProTheme.radiusLg),
        border: Border.all(
          color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade100,
        ),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildInfoTile(
    IconData icon,
    String label,
    String value,
    bool isDark,
  ) {
    return ListTile(
      leading: Icon(icon, color: DriftProTheme.primaryGreen, size: 22),
      title: Text(label, style: DriftProTheme.caption),
      subtitle: Text(
        value,
        style: DriftProTheme.bodyMd.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildActionTile(
    IconData icon,
    String label,
    VoidCallback onTap,
    bool isDark, {
    String? subtitle,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Icon(
        icon,
        color: isDark ? Colors.grey[400] : Colors.grey[600],
        size: 22,
      ),
      title: Text(label, style: DriftProTheme.bodyMd),
      subtitle: subtitle != null ? Text(subtitle, style: DriftProTheme.caption) : null,
      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
    );
  }
}
