import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/app_icons.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_notifier.dart';
import '../../core/services/supabase_service.dart';
import '../../models/user_profile.dart';
import '../common/placeholder_screen.dart';
import '../departments/departments_screen.dart';
import '../employees/employees_screen.dart';
import '../profile/profile_screen.dart';
import '../admin/access_control_screen.dart';
import '../surveys/survey_list_screen.dart';

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
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

          _buildSectionLabel('Administrasjon', isDark),
          _buildMenuItem(
            context,
            AppIcons.department,
            'Avdelinger',
            isDark,
          ),
          _buildMenuItem(
            context,
            AppIcons.employees,
            'Ansatte',
            isDark,
          ),
          _buildMenuItem(
            context,
            AppIcons.folder,
            'Personalmappe',
            isDark,
          ),
          _buildMenuItem(
            context,
            AppIcons.notification,
            'Varsler',
            isDark,
            badge: '3',
          ),
          _buildMenuItem(
            context,
            Icons.assignment_outlined,
            'Undersøkelser',
            isDark,
          ),
          if (_profile?.isAdmin == true)
            _buildMenuItem(
              context,
              Icons.lock_person_outlined,
              'Tilgangskontroll',
              isDark,
            ),

          const SizedBox(height: 20),
          _buildSectionLabel('Innstillinger', isDark),
          _buildMenuItem(
            context,
            AppIcons.profile,
            'Min profil',
            isDark,
          ),
          _buildThemeToggle(context, isDark),
          _buildMenuItem(
            context,
            AppIcons.settings,
            'Appinnstillinger',
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
          if (title == 'Avdelinger') {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DepartmentsScreen()));
            return;
          }
          if (title == 'Ansatte') {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EmployeesScreen()));
            return;
          }
          if (title == 'Tilgangskontroll') {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AccessControlScreen()));
            return;
          }
          if (title == 'Undersøkelser') {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SurveyListScreen()));
            return;
          }
          if (title == 'Min profil') {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
            return;
          }
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PlaceholderScreen(
                title: title,
                description: '$title-modulen kommer snart med Supabase-data.',
              ),
            ),
          );
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
            await Supabase.instance.client.auth.signOut();
          } catch (_) {}
        },
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DriftProTheme.radiusMd)),
      ),
    );
  }
}
