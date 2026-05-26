import 'package:flutter/material.dart';

import '../core/services/supabase_service.dart';
import '../core/theme/app_theme.dart';
import '../models/user_profile.dart';
import 'driver_shell.dart';

class DriverAccessGate extends StatefulWidget {
  const DriverAccessGate({super.key});

  @override
  State<DriverAccessGate> createState() => _DriverAccessGateState();
}

class _DriverAccessGateState extends State<DriverAccessGate> {
  bool _loading = true;
  UserProfile? _profile;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var profile = await SupabaseService.fetchOrCreateCurrentUserProfile();
    profile = await SupabaseService.ensureSessionLinkedToCompany() ?? profile;
    if (mounted) {
      setState(() {
        _profile = profile;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_profile == null) {
      return Scaffold(
        body: Center(
          child: Text('Ingen sjåførprofil', style: DriftProTheme.bodyMd),
        ),
      );
    }
    return DriverShell(profile: _profile!);
  }
}
