import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import '../../core/services/supabase_service.dart';
import 'access_actions.dart';
import 'access_session_cache.dart';
import 'route_access_map.dart';
import 'user_access.dart';
import '../../widgets/driftpro_loading_indicator.dart';
import '../routing/app_paths.dart';
import 'package:go_router/go_router.dart';

/// Naviger til en hovedfane via tilgangsnøkkel (ikke hardkodet indeks).
typedef NavigateByAccess = void Function(String accessKey);

/// MaterialRoute som blokkerer innhold uten tilgang (direkte lenker / dyp navigasjon).
Route<T> guardedMaterialRoute<T>({
  required UserProfile? profile,
  required String accessKey,
  required Widget child,
  String deniedMessage = 'Du har ikke tilgang til denne siden.',
  String? areaId,
  AccessAction action = AccessAction.view,
}) {
  return MaterialPageRoute<T>(
    builder: (_) => PermissionGuard(
      profile: profile,
      accessKey: accessKey,
      areaId: areaId,
      action: action,
      deniedMessage: deniedMessage,
      child: child,
    ),
  );
}

/// Viser [child] bare når brukeren har tilgang.
class PermissionGate extends StatelessWidget {
  final UserProfile? profile;
  final String? accessKey;
  final String? areaId;
  final AccessAction action;
  final Widget child;
  final Widget? fallback;

  const PermissionGate({
    super.key,
    required this.profile,
    required this.child,
    this.accessKey,
    this.areaId,
    this.action = AccessAction.view,
    this.fallback,
  });

  bool _allowed() {
    if (profile == null) return false;
    final access = profile!.access;
    if (areaId != null) return access.canArea(areaId!, action);
    if (accessKey != null) return access.can(accessKey!);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (_allowed()) return child;
    return fallback ?? const SizedBox.shrink();
  }
}

/// Skjerm som blokkeres hvis tilgang mangler.
/// Laster profil ved behov (cold start på delt lenke).
class PermissionGuard extends StatefulWidget {
  final UserProfile? profile;
  final String? accessKey;
  final String? areaId;
  final AccessAction action;
  final RouteAccessRequirement? requirement;
  final Uri? guardUri;
  final Widget child;
  final String deniedMessage;
  final bool redirectOnDeny;

  const PermissionGuard({
    super.key,
    required this.child,
    this.profile,
    this.accessKey,
    this.areaId,
    this.action = AccessAction.view,
    this.requirement,
    this.guardUri,
    this.deniedMessage = 'Du har ikke tilgang til denne siden.',
    this.redirectOnDeny = true,
  });

  @override
  State<PermissionGuard> createState() => _PermissionGuardState();
}

class _PermissionGuardState extends State<PermissionGuard> {
  UserProfile? _profile;
  bool _loading = false;
  bool _loadAttempted = false;
  bool _denyRedirectScheduled = false;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile ?? AccessSessionCache.profile;
    if (_profile == null) {
      _loading = true;
      _loadProfile();
    }
  }

  @override
  void didUpdateWidget(covariant PermissionGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.profile != null && widget.profile != _profile) {
      _profile = widget.profile;
      AccessSessionCache.setProfile(widget.profile);
    }
  }

  Future<void> _loadProfile() async {
    if (_loadAttempted) return;
    _loadAttempted = true;
    try {
      final p = await SupabaseService.fetchCurrentUserProfile();
      if (!mounted) return;
      if (p != null) AccessSessionCache.setProfile(p);
      setState(() {
        _profile = p ?? AccessSessionCache.profile;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  bool _allowed(UserAccess access) {
    if (widget.guardUri != null) {
      return RouteAccessMap.allowsUri(access, widget.guardUri!);
    }
    if (widget.requirement != null) {
      return RouteAccessMap.isAllowed(access, widget.requirement!);
    }
    if (widget.areaId != null) {
      return access.canArea(widget.areaId!, widget.action);
    }
    if (widget.accessKey != null) return access.can(widget.accessKey!);
    return false;
  }

  void _scheduleDenyRedirect() {
    if (!widget.redirectOnDeny || _denyRedirectScheduled || !mounted) return;
    _denyRedirectScheduled = true;
    final from = widget.guardUri?.toString();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go(AppPaths.accessDeniedPath(from: from));
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || (_profile == null && !_loadAttempted)) {
      return const Scaffold(body: DriftProLoadingCenter());
    }

    final profile = _profile;
    if (profile == null) {
      return const Scaffold(body: DriftProLoadingCenter());
    }

    final access = UserAccess(profile);
    if (_allowed(access)) {
      return widget.child;
    }

    _scheduleDenyRedirect();
    return const Scaffold(body: DriftProLoadingCenter());
  }
}
