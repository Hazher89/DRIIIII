import 'package:flutter/material.dart';

import '../../core/routing/app_paths.dart';
import '../../core/routing/route_url_sync.dart';
import '../../core/services/partner/partner_service.dart';
import '../../core/services/supabase_service.dart';
import '../../models/user_profile.dart';
import 'partner_shell.dart';
import 'widgets/partner_portal_access_revoked.dart';

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

  Future<void> _load() async {
    try {
      await SupabaseService.ensureSessionLinkedToCompany();
      var profile = await SupabaseService.fetchCurrentUserProfile();
      var portalKind = _portalAccountKind;

      final email =
          SupabaseService.currentUser?.email?.trim().toLowerCase() ?? '';
      final looksLikePortal = email.endsWith('.portal') ||
          email.endsWith('@portal.driftpro.no');

      if (profile?.isPartnerPortalUser == true || looksLikePortal) {
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
        if (profile != null) {
          profile = profile.copyWith(
            partnerId: session.partnerId,
            partnerVehicleId: session.isOwner ? null : session.partnerVehicleId,
          );
        }
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final profile = _profile;
    if (_portalAccountKind == null &&
        (profile == null || profile.isPartnerPortalUser)) {
      return const PartnerPortalAccessRevoked();
    }
    if (profile == null || !profile.isPartnerPortalUser) {
      return const Scaffold(
        body: Center(child: Text('Ingen portal-tilgang for denne kontoen.')),
      );
    }
    return PartnerShell(
      profile: profile,
      portalAccountKind: _portalAccountKind,
      initialTabIndex: _initialIndex(profile),
    );
  }
}
