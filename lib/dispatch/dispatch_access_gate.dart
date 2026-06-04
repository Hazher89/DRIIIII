import 'package:flutter/material.dart';

import '../core/permissions/user_access.dart';
import '../core/services/supabase_service.dart';
import '../core/theme/app_theme.dart';
import '../models/user_profile.dart';
import 'dispatch_shell.dart';

/// Etter innlogging: sjekk DriftPro-profil og rute-tilgang før planlegger åpnes.
class DispatchAccessGate extends StatefulWidget {
  const DispatchAccessGate({super.key});

  @override
  State<DispatchAccessGate> createState() => _DispatchAccessGateState();
}

class _DispatchAccessGateState extends State<DispatchAccessGate> {
  bool _loading = true;
  UserProfile? _profile;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var profile = await SupabaseService.fetchOrCreateCurrentUserProfile();
      if (profile != null && profile.companyId == null && !profile.isPartnerPortalUser) {
        profile = await SupabaseService.ensureSessionLinkedToCompany() ?? profile;
      }
      if (!mounted) return;

      if (profile == null) {
        setState(() {
          _profile = null;
          _error = 'Fant ikke brukerprofil i DriftPro.';
          _loading = false;
        });
        return;
      }

      if (!profile.isApproved && profile.role != UserRole.superadmin) {
        setState(() {
          _profile = profile;
          _error = 'Kontoen venter på godkjenning i DriftPro.';
          _loading = false;
        });
        return;
      }

      final canPlan = profile.isSuperAdmin ||
          profile.access.canPartnerRoutePlanning;

      if (!canPlan) {
        setState(() {
          _profile = profile;
          _error = 'Denne kontoen har ikke tilgang til ruteplanlegging i DriftPro.';
          _loading = false;
        });
        return;
      }

      setState(() {
        _profile = profile;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _signOut() async {
    await SupabaseService.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline, size: 48, color: Colors.orange.shade800),
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: DriftProTheme.bodyMd,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _signOut,
                    icon: const Icon(Icons.logout),
                    label: const Text('Logg ut'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return DispatchShell(profile: _profile!);
  }
}
