import 'package:flutter/material.dart';

import '../../core/routing/app_paths.dart';
import '../../core/routing/route_url_sync.dart';
import '../../core/services/partner/partner_service.dart';
import '../../core/services/supabase_service.dart';
import '../../models/partner/partner_links.dart';
import '../../models/user_profile.dart';
import 'partner_shell.dart';
import 'widgets/partner_portal_access_revoked.dart';
import '../../widgets/driftpro_loading_indicator.dart';

/// Top-level `/portal` — samarbeidspartner med egen URL per fane.
class PartnerPortalRoute extends StatefulWidget {
  const PartnerPortalRoute({super.key, this.initialTab});

  final String? initialTab;

  @override
  State<PartnerPortalRoute> createState() => _PartnerPortalRouteState();
}

class _PartnerPortalRouteState extends State<PartnerPortalRoute> {
  UserProfile? _profile;
  String? _portalAccountKind;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  UserProfile _profileForPortalSession(
    UserProfile? profile,
    PartnerPortalSession session,
  ) {
    final user = SupabaseService.currentUser;
    final base = profile ??
        UserProfile(
          id: user?.id ?? '',
          email: user?.email?.trim().toLowerCase() ?? '',
          fullName: 'Partner',
          role: UserRole.samarbeidspartner,
          companyId: session.companyId,
          isOnboarded: true,
          isApproved: true,
          isActive: true,
        );
    return base.copyWith(
      partnerId: session.partnerId,
      companyId: session.companyId,
      partnerVehicleId: session.isOwner ? null : session.partnerVehicleId,
      role: UserRole.samarbeidspartner,
      isOnboarded: true,
      isApproved: true,
      isActive: true,
    );
  }

  Future<void> _load() async {
    try {
      await SupabaseService.ensureSessionLinkedToCompany();
      var profile = await SupabaseService.fetchCurrentUserProfile();
      var portalKind = _portalAccountKind;

      final email =
          SupabaseService.currentUser?.email?.trim().toLowerCase() ?? '';

      // MAVI-ansatt / superadmin (f.eks. #25) skal aldri inn i partnerportal.
      if (SupabaseService.isInternalStaffSession(
        profile: profile,
        email: email,
      )) {
        if (!mounted) return;
        setState(() {
          _profile = profile;
          _portalAccountKind = null;
          _loading = false;
        });
        return;
      }

      final hasPortalAccount =
          await SupabaseService.currentSessionHasActivePortalAccount();
      final looksLikePortal = SupabaseService.emailLooksLikePortal(email);

      if (hasPortalAccount ||
          profile?.isPartnerPortalUser == true ||
          looksLikePortal) {
        var session = await PartnerService.resolvePortalSession();
        if (session == null) {
          await SupabaseService.applyPartnerBootstrap();
          profile = await SupabaseService.fetchCurrentUserProfile();
          session = await PartnerService.resolvePortalSession();
        }
        if (session == null) {
          if (!mounted) return;
          setState(() {
            _profile = profile;
            _portalAccountKind = null;
            _loading = false;
          });
          return;
        }
        portalKind = session.accountKind;
        profile = _profileForPortalSession(profile, session);
      }
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _portalAccountKind = portalKind;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _initialIndex(UserProfile profile) {
    final isOwner = _portalAccountKind == 'owner';
    final slugs = isOwner ? AppPaths.portalOwnerTabs : AppPaths.portalDriverTabs;
    return RouteUrlSync.indexForSlug(widget.initialTab, slugs);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const DriftProLoadingPage();
    }
    final profile = _profile;
    if (_portalAccountKind != null && profile != null) {
      return PartnerShell(
        profile: profile,
        portalAccountKind: _portalAccountKind,
        initialTabIndex: _initialIndex(profile),
      );
    }
    if (_portalAccountKind == null &&
        (profile == null || profile.isPartnerPortalUser)) {
      return const PartnerPortalAccessRevoked();
    }
    return const Scaffold(
      body: Center(child: Text('Ingen portal-tilgang for denne kontoen.')),
    );
  }
}
