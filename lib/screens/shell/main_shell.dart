import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth/session_sign_out.dart';
import '../../core/routing/app_paths.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/app_icons.dart';
import '../auth/onboarding_screen.dart';
import '../auth/pending_approval_screen.dart';
import '../partners/partner_shell.dart';
import '../../models/user_profile.dart';
import '../../core/services/partner/partner_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/permissions/access_keys.dart';
import '../../core/permissions/user_access.dart';

class MainShell extends StatefulWidget {
  final StatefulNavigationShell navigationShell;

  const MainShell({super.key, required this.navigationShell});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  UserProfile? _profile;
  String? _portalAccountKind;
  bool _isLoadingAccess = true;

  @override
  void initState() {
    super.initState();
    _loadAccess();
  }

  /// true = vi forlater MainShell (onboarding / ventende godkjenning).
  bool _scheduleProfileGate(UserProfile profile) {
    if (!profile.isOnboarded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => OnboardingScreen(profile: profile)),
          (_) => false,
        );
      });
      return true;
    }

    if (!profile.isApproved && profile.role != UserRole.superadmin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const PendingApprovalScreen()),
          (_) => false,
        );
      });
      return true;
    }

    return false;
  }

  /// Når appen startet med nød-superadmin (DB tom): prøv igjen etter at du har kjørt SQL.
  Future<void> _syncDbProfileAfterRecovery() async {
    for (var i = 0; i < 12; i++) {
      if (!mounted) return;
      await Future<void>.delayed(Duration(milliseconds: i == 0 ? 400 : 850));
      if (!mounted) return;

      await SupabaseService.rpcEnsureInternalProfileMissing();
      if (!mounted) return;

      final real = await SupabaseService.fetchCurrentUserProfile();
      if (!mounted) return;
      if (real == null) continue;

      if (_scheduleProfileGate(real)) return;

      setState(() => _profile = real);

      if (mounted && i >= 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profilen er hentet fra databasen.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }
  }

  Future<void> _loadAccess() async {
    try {
      var profile = await SupabaseService.fetchOrCreateCurrentUserProfile();
      final portalEmail = Supabase.instance.client.auth.currentUser?.email?.trim().toLowerCase() ?? '';
      final looksLikePortal = portalEmail.endsWith('.portal') ||
          portalEmail.endsWith('@portal.driftpro.no');
      if (profile != null &&
          profile.partnerId == null &&
          (looksLikePortal || profile.role == UserRole.samarbeidspartner)) {
        profile = await SupabaseService.ensureSessionLinkedToCompany() ?? profile;
      } else if (profile != null && profile.companyId == null && !profile.isPartnerPortalUser) {
        profile = await SupabaseService.ensureSessionLinkedToCompany() ?? profile;
      }
      if (!mounted) return;

      if (profile == null) {
        setState(() {
          _profile = null;
          _isLoadingAccess = false;
        });
        return;
      }

      if (_scheduleProfileGate(profile)) {
        setState(() => _isLoadingAccess = false);
        return;
      }

      var portalKind = _portalAccountKind;
      if (profile.isPartnerPortalUser) {
        await SupabaseService.ensureSessionLinkedToCompany();
        profile = await SupabaseService.fetchCurrentUserProfile() ?? profile;
        final session = await PartnerService.resolvePortalSession();
        portalKind = session?.accountKind;
        if (session != null) {
          profile = profile.copyWith(
            partnerId: session.partnerId,
            partnerVehicleId: session.isOwner ? null : session.partnerVehicleId,
          );
        }
      }

      setState(() {
        _profile = profile;
        _portalAccountKind = portalKind;
        _isLoadingAccess = false;
      });

      if (profile.isRecoverySession) {
        unawaited(_syncDbProfileAfterRecovery());
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingAccess = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kunne ikke laste profil etter innlogging: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    }
  }

  void _onNavigate(int visibleIndex, List<Map<String, dynamic>> visibleScreens) {
    HapticFeedback.selectionClick();
    final access = visibleScreens[visibleIndex]['access'] as String;
    final path = AppPaths.pathForAccess(access) ?? AppPaths.dashboard;
    final branch = AppPaths.branchIndexForPath(path);
    if (branch != null) {
      widget.navigationShell.goBranch(branch);
    }
  }

  int _visibleIndexForCurrentBranch(List<Map<String, dynamic>> visibleScreens) {
    final branch = widget.navigationShell.currentIndex;
    if (branch < 0 || branch >= AppPaths.shellTabs.length) return 0;
    final access = AppPaths.shellTabs[branch].access;
    final idx = visibleScreens.indexWhere((s) => s['access'] == access);
    return idx >= 0 ? idx : 0;
  }

  void _ensureAllowedRoute(List<Map<String, dynamic>> visibleScreens) {
    if (visibleScreens.isEmpty || !mounted) return;
    final branch = widget.navigationShell.currentIndex;
    if (branch < 0 || branch >= AppPaths.shellTabs.length) return;
    final currentAccess = AppPaths.shellTabs[branch].access;
    final allowed = visibleScreens.any((s) => s['access'] == currentAccess);
    if (!allowed) {
      final first = visibleScreens.first['access'] as String;
      final path = AppPaths.pathForAccess(first) ?? AppPaths.dashboard;
      context.go(path);
    }
  }

  bool _hasAccess(String key) {
    if (_profile == null) return false;
    return _profile!.access.can(key);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingAccess) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    if (_profile != null && _profile!.isPartnerPortalUser) {
      return PartnerShell(
        profile: _profile!,
        portalAccountKind: _portalAccountKind,
      );
    }

    // Safety check fallback (Active enforcement)
    if (_profile == null ||
        !_profile!.isOnboarded ||
        (!_profile!.isApproved && _profile!.role != UserRole.superadmin)) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.security, size: 64, color: Colors.orange),
              const SizedBox(height: 24),
              const Text('Tilgang nektet', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text('Du har ikke tilgang til denne delen av systemet.', textAlign: TextAlign.center),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => signOutFromPortal(context),
                child: const Text('Logg ut'),
              ),
            ],
          ),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final allScreens = [
      {
        'icon': AppIcons.dashboard,
        'label': AppStrings.navDashboard,
        'access': AccessKeys.dashboard,
      },
      {'icon': AppIcons.survey, 'label': AppStrings.navSurveys, 'access': AccessKeys.surveys},
      {'icon': AppIcons.absence, 'label': AppStrings.navAbsence, 'access': AccessKeys.fravaer},
      {'icon': AppIcons.ticket, 'label': AppStrings.navTickets, 'access': AccessKeys.avvik},
      {'icon': AppIcons.hms, 'label': AppStrings.navHMS, 'access': AccessKeys.hms},
      {'icon': Icons.handshake_outlined, 'label': AppStrings.navPartners, 'access': AccessKeys.partners},
      {'icon': AppIcons.more, 'label': AppStrings.navMore, 'access': AccessKeys.more},
    ];

    final visibleScreens = allScreens.where((s) => _hasAccess(s['access'] as String)).toList();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureAllowedRoute(visibleScreens));
    final navIndex = _visibleIndexForCurrentBranch(visibleScreens);

    return Scaffold(
      body: widget.navigationShell,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark ? DriftProTheme.cardDark : Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: visibleScreens.asMap().entries.map((entry) {
                final i = entry.key;
                final s = entry.value;
                return _buildNavItem(
                  i,
                  s['icon'] as IconData,
                  s['label'] as String,
                  isDark,
                  navIndex: navIndex,
                  visibleScreens: visibleScreens,
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
    int index,
    IconData icon,
    String label,
    bool isDark, {
    required int navIndex,
    required List<Map<String, dynamic>> visibleScreens,
    int? badge,
  }) {
    final isSelected = navIndex == index;
    return GestureDetector(
      onTap: () => _onNavigate(index, visibleScreens),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? DriftProTheme.primaryGreen.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(DriftProTheme.radiusMd),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Badge(
              isLabelVisible: badge != null && badge > 0,
              label: badge != null ? Text('$badge', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700)) : null,
              backgroundColor: DriftProTheme.error,
              child: Icon(
                icon,
                size: 24,
                color: isSelected ? DriftProTheme.primaryGreen : (isDark ? Colors.grey[600] : Colors.grey[450]),
              ),
            ),
            const SizedBox(height: 3),
            SizedBox(
              width: 64,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? DriftProTheme.primaryGreen : (isDark ? Colors.grey[600] : Colors.grey[450]),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
