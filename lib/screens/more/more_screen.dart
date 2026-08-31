import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_icons.dart';
import '../../core/layout/mobile_shell_scaffold.dart';
import '../../core/constants/app_strings.dart';
import '../../core/config/driftpro_client.dart';
import '../../core/permissions/partner_access.dart';
import '../../core/routing/app_paths.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/driftpro_theme_context.dart';
import '../../core/auth/session_sign_out.dart';
import '../../core/services/supabase_service.dart';
import '../../models/user_profile.dart';
import '../../core/permissions/user_access.dart';
import 'driftpro_platform_catalog.dart';

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> with WidgetsBindingObserver {
  UserProfile? _profile;
  bool _isLoading = true;
  int _usersWaitingForApprovalCount = 0;
  bool _profileReloadInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadProfile();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_loadProfile(silent: true));
    }
  }

  Future<void> _loadProfile({bool silent = false}) async {
    if (_profileReloadInFlight) return;
    _profileReloadInFlight = true;
    if (!silent) {
      setState(() => _isLoading = true);
    }
    try {
      final profile = await SupabaseService.fetchEffectiveUserProfile();
      int count = 0;
      if (profile?.isSuperAdmin == true && profile?.companyId != null) {
        final users = await SupabaseService.fetchProfiles(companyId: profile!.companyId!);
        count = users
            .where((u) => u.isOnboarded && !u.isApproved && !u.isPartnerPortalUser)
            .length;
      }
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _usersWaitingForApprovalCount = count;
      });
    } finally {
      _profileReloadInFlight = false;
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return MobileShellScaffold(
      title: AppStrings.navMore,
      hideMobileTitleBar: DriftProClient.isMobile,
      backgroundColor: context.driftColors.scaffold,
      body: RefreshIndicator(
        onRefresh: () => _loadProfile(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          children: [
          // Profil-kort
          GestureDetector(
            onTap: () => context.push(AppPaths.moreProfil),
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

          if (DriftProClient.isMobile && _profile != null && _hasMobileModules) ...[
            _buildSectionLabel(context, 'Moduler'),
            if (PartnerAccess.canOpenPartnersModule(_profile!.access))
              _buildModuleItem(
                context,
                Icons.handshake_outlined,
                AppStrings.navPartners,
                AppPaths.partners,
                isDark,
              ),
            if (_profile!.access.canStempling)
              _buildModuleItem(
                context,
                AppIcons.clock,
                AppStrings.navStempling,
                AppPaths.stempling,
                isDark,
              ),
            if (_profile!.access.canUniformMonitor)
              _buildModuleItem(
                context,
                Icons.verified_user_outlined,
                AppStrings.navUniform,
                AppPaths.uniform,
                isDark,
              ),
            if (_profile!.access.canSurveys || _profile!.access.canSurveysMenu)
              _buildModuleItem(
                context,
                AppIcons.survey,
                AppStrings.navSurveys,
                AppPaths.surveys,
                isDark,
              ),
            const SizedBox(height: 20),
          ],

          if (_profile != null && _hasAnyAdminMenu) ...[
            _buildSectionLabel(context, 'Administrasjon'),
            if (_profile!.access.canDepartments)
              _buildMenuItem(context, AppIcons.department, 'Avdelinger', isDark),
            if (_profile!.isSuperAdmin || _profile!.access.canEmployeesList)
              _buildMenuItem(context, AppIcons.employees, 'Ansatte', isDark),
            if (_profile!.isSuperAdmin || _profile!.access.canEmployeesList)
              _buildMenuItem(context, Icons.account_tree_outlined, 'Organisasjonskart', isDark),
            if (_profile!.access.canPartnersMenu || _profile!.access.canPartnersTab)
              if (!DriftProClient.isMobile)
                _buildMenuItem(
                  context,
                  Icons.handshake_outlined,
                  'Samarbeidspartnere',
                  isDark,
                ),
            if (_profile!.access.canPersonalFolder)
              _buildMenuItem(context, AppIcons.folder, 'Personalmappe', isDark),
            if (_profile!.access.canNotifications)
              _buildMenuItem(
                context,
                AppIcons.notification,
                'Varsler',
                isDark,
              ),
            if (_profile!.access.canSurveysMenu || _profile!.access.canSurveys)
              if (!DriftProClient.isMobile)
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
            if (_profile!.access.canHomeFeedAdmin)
              _buildMenuItem(
                context,
                Icons.dashboard_customize_outlined,
                'Forside-innhold',
                isDark,
              ),
            if (_profile!.isSuperAdmin ||
                _profile!.role == UserRole.admin)
              _buildMenuItem(
                context,
                Icons.smart_toy_outlined,
                'DriftPro-assistent',
                isDark,
              ),
            if (_profile!.isSuperAdmin)
              _buildMenuItem(
                context,
                Icons.forum_outlined,
                'Partner-chat',
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

          if (_profile?.access.canUniformMonitorAdmin == true ||
              _profile?.access.canUniformMonitor == true) ...[
            const SizedBox(height: 20),
            _buildSectionLabel(context, 'Hub'),
            if (_profile?.access.canUniformMonitorAdmin == true) ...[
              _buildMenuItem(
                context,
                Icons.videocam_outlined,
                'Kameraer',
                isDark,
              ),
            ],
            if (_profile?.access.canUniformMonitor == true)
              _buildMenuItem(
                context,
                Icons.photo_camera_front_outlined,
                'Kamerahendelser',
                isDark,
              ),
          ],

          const SizedBox(height: 20),
          _buildSectionLabel(context, 'Innstillinger'),
          if (_profile?.access.canProfile ?? true)
            _buildMenuItem(
              context,
              AppIcons.profile,
              'Min profil',
              isDark,
            ),
          if (DriftProPlatformCatalog.canAccessDropboxSettings(
            email: _profile?.email,
            employeeNumber: _profile?.employeeNumber,
          ))
            _buildMenuItem(
              context,
              Icons.cloud_outlined,
              'Fillagring',
              isDark,
            ),

          const SizedBox(height: 20),
          _buildSectionLabel(context, 'Info'),
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
        a.canPartnersTab ||
        p.isSuperAdmin ||
        p.role == UserRole.admin ||
        a.canPersonalFolder ||
        p.isSuperAdmin ||
        a.canSurveysMenu ||
        a.canSurveys ||
        a.canAccessControl ||
        p.isSuperAdmin ||
        a.canKiosk ||
        a.canHomeFeedAdmin ||
        a.canWhistleblowing;
  }

  bool get _hasMobileModules {
    final p = _profile;
    if (p == null) return false;
    final a = p.access;
    return PartnerAccess.canOpenPartnersModule(a) ||
        a.canStempling ||
        a.canUniformMonitor ||
        a.canSurveys ||
        a.canSurveysMenu;
  }

  Widget _buildModuleItem(
    BuildContext context,
    IconData icon,
    String title,
    String path,
    bool isDark,
  ) {
    final drift = context.driftColors;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: drift.card,
        borderRadius: BorderRadius.circular(DriftProTheme.radiusMd),
        border: Border.all(color: drift.borderSubtle),
      ),
      child: ListTile(
        leading: Icon(icon, color: drift.iconMuted),
        title: Text(
          title,
          style: DriftProTheme.bodyMd.copyWith(color: drift.textPrimary),
        ),
        trailing: Icon(
          Icons.arrow_forward_ios_rounded,
          size: 14,
          color: drift.textMuted,
        ),
        onTap: () => context.go(path),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DriftProTheme.radiusMd),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: DriftProTheme.labelSm.copyWith(
          color: context.driftColors.textMuted,
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
    final drift = context.driftColors;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: drift.card,
        borderRadius: BorderRadius.circular(DriftProTheme.radiusMd),
        border: Border.all(color: drift.borderSubtle),
      ),
      child: ListTile(
        leading: Icon(icon, color: drift.iconMuted),
        title: Text(
          title,
          style: DriftProTheme.bodyMd.copyWith(color: drift.textPrimary),
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
              color: drift.textMuted,
            ),
          ],
        ),
        onTap: () {
          final path = switch (title) {
            'Samarbeidspartnere' => AppPaths.morePartnere,
            'Avdelinger' => AppPaths.moreAvdelinger,
            'Ansatte' => AppPaths.moreAnsatte,
            'Organisasjonskart' => AppPaths.moreOrganisasjonskart,
            'Tilgangskontroll' => AppPaths.moreTilgangskontroll,
            'Undersøkelser' => AppPaths.moreUndersokelser,
            'Anonym anmeldelse' => AppPaths.moreWhistleblowing,
            'Brukergodkjenning' => AppPaths.moreBrukergodkjenning,
            'Infoskjerm' => AppPaths.moreInfoskjerm,
            'Forside-innhold' => AppPaths.moreForside,
            'DriftPro-assistent' => AppPaths.moreAssistent,
            'Partner-chat' => AppPaths.morePartnerChat,
            'Fillagring' => AppPaths.moreDropbox,
            'Min profil' => AppPaths.moreProfil,
            'Personalmappe' => AppPaths.morePersonalmappe,
            'Varsler' => AppPaths.moreVarsler,
            'Hjelp & støtte' => AppPaths.moreHjelp,
            'Personvern' => AppPaths.morePersonvern,
            'Om DriftPro' => AppPaths.moreOm,
            'Kameraer' => AppPaths.moreVisionCameras,
            'Kamerahendelser' => AppPaths.moreVisionEvents,
            _ => null,
          };
          if (path != null) context.push(path);
        },
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
