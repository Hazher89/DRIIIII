import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth/session_sign_out.dart';
import '../../core/layout/mobile_shell_nav.dart';
import '../../core/layout/web_layout.dart';
import '../../core/routing/app_paths.dart';
import '../../core/theme/driftpro_theme_context.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/app_icons.dart';
import '../auth/onboarding_screen.dart';
import '../auth/pending_approval_screen.dart';
import '../../models/user_profile.dart';
import '../../core/services/native_permissions_service.dart';
import '../../core/services/partner/partner_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/permissions/access_keys.dart';
import '../../core/permissions/access_session_cache.dart';
import '../../core/permissions/partner_access.dart';
import '../../core/permissions/user_access.dart';
import '../../widgets/driftpro_brand_bar.dart';
import '../../widgets/driftpro_loading_indicator.dart';

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
  StreamSubscription<AuthState>? _authSub;
  String? _sessionUserId;

  @override
  void initState() {
    super.initState();
    _sessionUserId = Supabase.instance.client.auth.currentUser?.id;
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      final nextId = event.session?.user.id;
      if (nextId == _sessionUserId) return;
      _sessionUserId = nextId;
      if (!mounted) return;
      setState(() {
        _profile = null;
        _portalAccountKind = null;
        _isLoadingAccess = true;
      });
      if (nextId != null) {
        unawaited(_loadAccess());
      }
    });
    _loadAccess();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
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
      AccessSessionCache.setProfile(real);

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
      final looksLikePortal = SupabaseService.emailLooksLikePortal(portalEmail);
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

      final hasPortalAccount =
          await SupabaseService.currentSessionHasActivePortalAccount();
      if (hasPortalAccount &&
          !SupabaseService.isInternalStaffSession(
            profile: profile,
            email: portalEmail,
          )) {
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          context.go(AppPaths.portal);
        });
        return;
      }

      var portalKind = _portalAccountKind;
      if (profile.isPartnerPortalUser &&
          !SupabaseService.isInternalStaffSession(
            profile: profile,
            email: portalEmail,
          )) {
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
      AccessSessionCache.setProfile(profile);

      unawaited(NativePermissionsService.bootstrapAfterLogin(
        mounted ? context : null,
      ));

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
    final branchIndex =
        AppPaths.shellTabs.indexWhere((t) => t.access == access);
    if (branchIndex >= 0) {
      widget.navigationShell.goBranch(
        branchIndex,
        initialLocation: branchIndex == widget.navigationShell.currentIndex,
      );
      return;
    }
    final path = AppPaths.pathForAccess(access) ?? AppPaths.dashboard;
    context.go(path);
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
    if (key == AccessKeys.partners) {
      return PartnerAccess.canOpenPartnersModule(_profile!.access);
    }
    return _profile!.access.can(key);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingAccess) return const DriftProLoadingPage();

    if (_profile != null && _profile!.isPartnerPortalUser) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final path = GoRouterState.of(context).uri.path;
        if (path != AppPaths.portal && !path.startsWith('${AppPaths.portal}/')) {
          context.go(AppPaths.portal);
        }
      });
      return const DriftProLoadingPage();
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

    final drift = context.driftColors;

    final allScreens = [
      {
        'icon': AppIcons.dashboard,
        'label': AppStrings.navDashboard,
        'access': AccessKeys.dashboard,
      },
      {
        'icon': AppIcons.survey,
        'label': AppStrings.navSurveys,
        'access': AccessKeys.surveys,
      },
      {
        'icon': AppIcons.absence,
        'label': AppStrings.navAbsence,
        'access': AccessKeys.fravaer,
      },
      {
        'icon': AppIcons.ticket,
        'label': AppStrings.navTickets,
        'access': AccessKeys.avvik,
      },
      {
        'icon': AppIcons.hms,
        'label': AppStrings.navHMS,
        'access': AccessKeys.hms,
      },
      {
        'icon': Icons.verified_user_outlined,
        'label': AppStrings.navUniform,
        'access': AccessKeys.uniformMonitor,
      },
      {
        'icon': Icons.handshake_outlined,
        'label': AppStrings.navPartners,
        'access': AccessKeys.partners,
      },
      {
        'icon': AppIcons.clock,
        'label': AppStrings.navStempling,
        'access': AccessKeys.stempling,
      },
      {
        'icon': AppIcons.more,
        'label': AppStrings.navMore,
        'access': AccessKeys.more,
      },
    ];

    final visibleScreens = allScreens.where((s) => _hasAccess(s['access'] as String)).toList();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureAllowedRoute(visibleScreens));
    final navIndex = _visibleIndexForCurrentBranch(visibleScreens);
    final useSideNav = WebLayout.prefersPointerNav &&
        MediaQuery.sizeOf(context).width >= 900;

    if (useSideNav) {
      return DriftProBrandedScaffold(
        backgroundColor: WebLayout.canvasColor(context),
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _WebShellSideNav(
              screens: visibleScreens,
              selectedIndex: navIndex,
              onSelect: (i) => _onNavigate(i, visibleScreens),
            ),
            Expanded(child: widget.navigationShell),
          ],
        ),
      );
    }

    return DriftProBrandedScaffold(
      backgroundColor: WebLayout.prefersPointerNav
          ? WebLayout.canvasColor(context)
          : null,
      body: widget.navigationShell,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: drift.navBar,
          border: Border(top: BorderSide(color: drift.borderSubtle)),
          boxShadow: drift.cardShadow,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: MobileShellNavBar(
              itemCount: visibleScreens.length,
              builder: (context, i, {required compact}) {
                final s = visibleScreens[i];
                return _buildNavItem(
                  context,
                  i,
                  s['icon'] as IconData,
                  s['label'] as String,
                  navIndex: navIndex,
                  visibleScreens: visibleScreens,
                  compact: compact,
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context,
    int index,
    IconData icon,
    String label, {
    required int navIndex,
    required List<Map<String, dynamic>> visibleScreens,
    int? badge,
    bool compact = false,
  }) {
    final drift = context.driftColors;
    final scheme = Theme.of(context).colorScheme;
    final isSelected = navIndex == index;
    final metrics = ShellNavItemMetrics.of(context, compact: compact);
    return GestureDetector(
      onTap: () => _onNavigate(index, visibleScreens),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: metrics.horizontalPadding,
          vertical: 6,
        ),
        constraints: BoxConstraints(minWidth: metrics.minWidth),
        decoration: BoxDecoration(
          color: isSelected ? scheme.primary.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Badge(
              isLabelVisible: badge != null && badge > 0,
              label: badge != null
                  ? Text(
                      '$badge',
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : null,
              child: Icon(
                icon,
                size: metrics.iconSize,
                color: isSelected ? drift.navSelected : drift.navUnselected,
              ),
            ),
            const SizedBox(height: 3),
            SizedBox(
              width: compact ? 56 : 64,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: metrics.labelSize,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? drift.navSelected : drift.navUnselected,
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

/// Venstremeny for web/desktop — klikk, ikke swipe/bunn-tabs.
class _WebShellSideNav extends StatelessWidget {
  const _WebShellSideNav({
    required this.screens,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<Map<String, dynamic>> screens;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final drift = context.driftColors;
    final wide = MediaQuery.sizeOf(context).width >= 1180;
    final railWidth = wide ? 220.0 : 72.0;

    return Container(
      width: railWidth,
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF151820)
            : Colors.white,
        border: Border(right: BorderSide(color: drift.borderSubtle)),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 24),
        itemCount: screens.length,
        itemBuilder: (context, i) {
          final s = screens[i];
          final selected = i == selectedIndex;
          final icon = s['icon'] as IconData;
          final label = s['label'] as String;
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Material(
              color: selected
                  ? drift.navSelected.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onSelect(i),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: wide ? 12 : 0,
                    vertical: 11,
                  ),
                  child: wide
                      ? Row(
                          children: [
                            Icon(
                              icon,
                              size: 20,
                              color: selected
                                  ? drift.navSelected
                                  : drift.navUnselected,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight:
                                      selected ? FontWeight.w800 : FontWeight.w600,
                                  color: selected
                                      ? drift.navSelected
                                      : drift.navUnselected,
                                ),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            Icon(
                              icon,
                              size: 22,
                              color: selected
                                  ? drift.navSelected
                                  : drift.navUnselected,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight:
                                    selected ? FontWeight.w800 : FontWeight.w600,
                                color: selected
                                    ? drift.navSelected
                                    : drift.navUnselected,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
