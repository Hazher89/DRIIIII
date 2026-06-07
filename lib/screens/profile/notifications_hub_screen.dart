import 'package:flutter/material.dart';

import '../../core/permissions/user_access.dart';
import '../../core/services/supabase_service.dart';
import '../../models/user_profile.dart';
import 'profile_notifications_tab.dart';

/// Mer → Varsler: kun superadmin — logg, SMS-innstillinger og mottakere.
class NotificationsHubScreen extends StatefulWidget {
  const NotificationsHubScreen({
    super.key,
    this.initialTab,
    this.initialSettingsTab,
  });

  final String? initialTab;
  final String? initialSettingsTab;

  @override
  State<NotificationsHubScreen> createState() => _NotificationsHubScreenState();
}

class _NotificationsHubScreenState extends State<NotificationsHubScreen> {
  UserProfile? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await SupabaseService.fetchCurrentUserProfile();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_profile?.access.canNotifications != true) {
      return Scaffold(
        appBar: AppBar(title: const Text('Varsler'), centerTitle: true),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Du har ikke tilgang til varselsenteret.\n'
              'Be superadmin om «Varsler & varselinnstillinger» under Tilgang.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Varsler'),
        centerTitle: true,
      ),
      body: ProfileNotificationsTab(
        initialTab: widget.initialTab,
        initialSettingsTab: widget.initialSettingsTab,
      ),
    );
  }
}
