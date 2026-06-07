import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_icons.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_notifier.dart';
import '../../core/auth/session_sign_out.dart';
import '../../core/services/supabase_service.dart';
import '../../models/user_profile.dart';
import '../../core/permissions/access_keys.dart';
import '../../core/permissions/permission_gate.dart';
import '../../core/permissions/user_access.dart';
import '../employees/employee_hub_screen.dart';
import 'driftpro_platform_catalog.dart';
import 'help_support_screen.dart';
import 'privacy_screen.dart';
import 'about_driftpro_screen.dart';
import '../departments/departments_screen.dart';
import '../employees/employees_screen.dart';
import '../employees/employee_personal_folder_screen.dart';
import '../profile/profile_screen.dart';
import '../profile/notifications_hub_screen.dart';
import '../admin/access_control_screen.dart';
import '../admin/kiosk_settings_screen.dart';
import '../admin/dropbox_storage_settings_screen.dart';
import '../surveys/survey_list_screen.dart';
import '../partners/partners_dashboard_screen.dart';
import 'organization_chart_screen.dart';
import 'whistleblowing_screen.dart';

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  UserProfile? _profile;
  bool _isLoading = true;
  int _usersWaitingForApprovalCount = 0;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    try {
      final profile = await SupabaseService.fetchCurrentUserProfile();
      int count = 0;
      if (profile?.isSuperAdmin == true && profile?.companyId != null) {
        final users = await SupabaseService.fetchProfiles(companyId: profile!.companyId!);
        count = users
            .where((u) => u.isOnboarded && !u.isApproved && !u.isPartnerPortalUser)
            .length;
      }
      setState(() {
        _profile = profile;
        _usersWaitingForApprovalCount = count;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(title: const Text(AppStrings.navMore)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        physics: const BouncingScrollPhysics(),
        children: [
          // Profil-kort
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: DriftProTheme.primaryGradient,
                borderRadius: BorderRadius.circular(DriftProTheme.radiusXl),
                boxShadow: DriftProTheme.elevatedShadow,
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    backgroundImage: _profile?.avatarUrl != null ? NetworkImage(_profile!.avatarUrl!) : null,
                    child: _profile?.avatarUrl == null
                      ? Text(
                          _profile?.initials ?? '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        )
                      : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _profile?.fullName ?? 'Laster...',
                          style: DriftProTheme.headingSm.copyWith(
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _profile?.jobTitle ?? (_profile?.role.name.toUpperCase() ?? ''),
                          style: DriftProTheme.bodySm.copyWith(
                            color: Colors.white.withOpacity(0.75),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          if (_profile != null && _hasAnyAdminMenu) ...[
            _buildSectionLabel('Administrasjon', isDark),
            if (_profile!.access.canDepartments)
              _buildMenuItem(context, AppIcons.department, 'Avdelinger', isDark),
            if (_profile!.isSuperAdmin || _profile!.access.canEmployeesList)
              _buildMenuItem(context, AppIcons.employees, 'Ansatte', isDark),
            if (_profile!.isSuperAdmin || _profile!.access.canEmployeesList)
              _buildMenuItem(context, Icons.account_tree_outlined, 'Organisasjonskart', isDark),
            if (_profile!.access.canPartnersMenu)
              _buildMenuItem(
                context,
                Icons.handshake_outlined,
                'Samarbeidspartnere',
                isDark,
              ),
            if (_profile!.access.canPersonalFolder)
              _buildMenuItem(context, AppIcons.folder, 'Personalmappe', isDark),
            if (_profile!.isSuperAdmin)
              _buildMenuItem(
                context,
                AppIcons.notification,
                'Varsler',
                isDark,
              ),
            if (_profile!.access.canSurveysMenu)
              _buildMenuItem(
                context,
                Icons.assignment_outlined,
                'Undersøkelser',
                isDark,
              ),
            if (_profile!.access.canAccessControl)
              _buildMenuItem(
                context,
                Icons.lock_person_outlined,
                'Tilgangskontroll',
                isDark,
              ),
            if (_profile!.isSuperAdmin)
              _buildMenuItem(
                context,
                Icons.how_to_reg_outlined,
                'Brukergodkjenning',
                isDark,
                badge: _usersWaitingForApprovalCount > 0
                    ? _usersWaitingForApprovalCount.toString()
                    : null,
              ),
            if (_profile!.access.canKiosk)
              _buildMenuItem(
                context,
                Icons.display_settings_outlined,
                'Infoskjerm',
                isDark,
              ),
            if (_profile!.access.canWhistleblowing)
              _buildMenuItem(
                context,
                Icons.record_voice_over_outlined,
                'Anonym anmeldelse',
                isDark,
              ),
          ],

          const SizedBox(height: 20),
          _buildSectionLabel('Innstillinger', isDark),
          if (_profile?.access.canProfile ?? true)
            _buildMenuItem(
              context,
              AppIcons.profile,
              'Min profil',
              isDark,
            ),
          _buildThemeToggle(context, isDark),
          if (DriftProPlatformCatalog.canAccessDropboxSettings(
            email: _profile?.email,
            employeeNumber: _profile?.employeeNumber,
          ))
            _buildMenuItem(
              context,
              Icons.cloud_outlined,
              'Dropbox-lagring',
              isDark,
            ),

          const SizedBox(height: 20),
          _buildSectionLabel('Info', isDark),
          _buildMenuItem(
            context,
            Icons.help_outline_rounded,
            'Hjelp & støtte',
            isDark,
          ),
          _buildMenuItem(
            context,
            Icons.privacy_tip_outlined,
            'Personvern',
            isDark,
          ),
          _buildMenuItem(
            context,
            Icons.info_outline_rounded,
            'Om DriftPro',
            isDark,
          ),

          const SizedBox(height: 20),
          _buildLogoutButton(isDark, context),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  bool get _hasAnyAdminMenu {
    final p = _profile;
    if (p == null) return false;
    final a = p.access;
    return a.canDepartments ||
        a.canEmployeesList ||
        a.canEditEmployees ||
        a.canPartnersMenu ||
        a.canPersonalFolder ||
        p.isSuperAdmin ||
        a.canSurveysMenu ||
        a.canAccessControl ||
        p.isSuperAdmin ||
        a.canKiosk ||
        a.canWhistleblowing;
  }

  Widget _buildSectionLabel(String label, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: DriftProTheme.labelSm.copyWith(
          color: isDark ? Colors.grey[500] : Colors.grey[400],
          letterSpacing: 1,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context,
    IconData icon,
    String title,
    bool isDark, {
    String? badge,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(DriftProTheme.radiusMd),
        border: Border.all(
          color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade100,
        ),
      ),
      child: ListTile(
        leading: Icon(icon, color: isDark ? Colors.grey[400] : Colors.grey[600]),
        title: Text(
          title,
          style: DriftProTheme.bodyMd.copyWith(
            color: isDark ? Colors.white : Colors.grey[900],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: DriftProTheme.error,
                  borderRadius: BorderRadius.circular(DriftProTheme.radiusRound),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: isDark ? Colors.grey[600] : Colors.grey[400],
            ),
          ],
        ),
        onTap: () {
          if (title == 'Samarbeidspartnere') {
            Navigator.of(context).push(
              guardedMaterialRoute(
                profile: _profile,
                accessKey: AccessKeys.samarbeidspartnere,
                child: const PartnersDashboardScreen(),
              ),
            );
            return;
          }
          if (title == 'Avdelinger') {
            Navigator.of(context).push(
              guardedMaterialRoute(
                profile: _profile,
                accessKey: AccessKeys.avdelinger,
                child: const DepartmentsScreen(),
              ),
            );
            return;
          }
          if (title == 'Ansatte') {
            Navigator.of(context).push(
              guardedMaterialRoute(
                profile: _profile,
                accessKey: AccessKeys.ansatte,
                child: const EmployeesScreen(),
              ),
            );
            return;
          }
          if (title == 'Organisasjonskart') {
            Navigator.of(context).push(
              guardedMaterialRoute(
                profile: _profile,
                accessKey: AccessKeys.ansatte,
                child: const OrganizationChartScreen(),
              ),
            );
            return;
          }
          if (title == 'Tilgangskontroll') {
            Navigator.of(context).push(
              guardedMaterialRoute(
                profile: _profile,
                accessKey: AccessKeys.tilgangskontroll,
                child: const AccessControlScreen(),
              ),
            );
            return;
          }
          if (title == 'Undersøkelser') {
            Navigator.of(context).push(
              guardedMaterialRoute(
                profile: _profile,
                accessKey: AccessKeys.undersokelser,
                child: const SurveyListScreen(),
              ),
            );
            return;
          }
          if (title == 'Anonym anmeldelse') {
            Navigator.of(context).push(
              guardedMaterialRoute(
                profile: _profile,
                accessKey: AccessKeys.whistleblowing,
                child: const WhistleblowingScreen(),
              ),
            );
            return;
          }
          if (title == 'Brukergodkjenning') {
            Navigator.of(context).push(
              guardedMaterialRoute(
                profile: _profile,
                accessKey: AccessKeys.brukergodkjenning,
                child: const EmployeeHubScreen(),
              ),
            );
            return;
          }
          if (title == 'Infoskjerm') {
            Navigator.of(context).push(
              guardedMaterialRoute(
                profile: _profile,
                accessKey: AccessKeys.kiosk,
                child: const KioskSettingsScreen(),
              ),
            );
            return;
          }
          if (title == 'Dropbox-lagring') {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const DropboxStorageSettingsScreen(),
              ),
            );
            return;
          }
          if (title == 'Min profil') {
            Navigator.of(context).push(
              guardedMaterialRoute(
                profile: _profile,
                accessKey: AccessKeys.profil,
                child: const ProfileScreen(),
              ),
            );
            return;
          }
          if (title == 'Personalmappe') {
            Navigator.of(context).push(
              guardedMaterialRoute(
                profile: _profile,
                accessKey: AccessKeys.personalmappe,
                child: const EmployeePersonalFolderScreen(),
              ),
            );
            return;
          }
          if (title == 'Varsler') {
            Navigator.of(context).push(
              guardedMaterialRoute(
                profile: _profile,
                accessKey: AccessKeys.varsler,
                child: const NotificationsHubScreen(),
              ),
            );
            return;
          }
          if (title == 'Hjelp & støtte') {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HelpSupportScreen()),
            );
            return;
          }
          if (title == 'Personvern') {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PrivacyScreen()),
            );
            return;
          }
          if (title == 'Om DriftPro') {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AboutDriftProScreen()),
            );
            return;
          }
        },
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DriftProTheme.radiusMd)),
      ),
    );
  }

  Widget _buildThemeToggle(BuildContext context, bool isDark) {
    final themeNotifier = context.read<ThemeNotifier>();
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(DriftProTheme.radiusMd),
        border: Border.all(
          color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade100,
        ),
      ),
      child: ListTile(
        leading: Icon(
          isDark ? AppIcons.darkMode : AppIcons.lightMode,
          color: isDark ? Colors.grey[400] : Colors.grey[600],
        ),
        title: Text(
          'Mørk modus',
          style: DriftProTheme.bodyMd.copyWith(
            color: isDark ? Colors.white : Colors.grey[900],
          ),
        ),
        trailing: Switch.adaptive(
          value: isDark,
          activeColor: DriftProTheme.primaryGreen,
          onChanged: (_) => themeNotifier.toggleTheme(),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DriftProTheme.radiusMd)),
      ),
    );
  }

  Widget _buildLogoutButton(bool isDark, BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: DriftProTheme.error.withOpacity(0.08),
        borderRadius: BorderRadius.circular(DriftProTheme.radiusMd),
      ),
      child: ListTile(
        leading: const Icon(AppIcons.logout, color: DriftProTheme.error),
        title: Text(
          AppStrings.signOut,
          style: DriftProTheme.labelLg.copyWith(
            color: DriftProTheme.error,
          ),
        ),
        onTap: () async {
          try {
            await signOutFromPortal(context);
          } catch (_) {}
        },
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DriftProTheme.radiusMd)),
      ),
    );
  }
}
