import 'package:flutter/material.dart';

import '../../core/permissions/user_access.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user_profile.dart';
import '../partners/widgets/partner_notification_settings_panel.dart';
import 'profile_notifications_tab.dart';
import 'widgets/mavi_notification_settings_panel.dart';

/// Mer → Varsler: logg + innstillinger (superadmin) eller kun innstillinger.
class NotificationsHubScreen extends StatefulWidget {
  const NotificationsHubScreen({super.key});

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

    final isSuperAdmin = _profile?.isSuperAdmin == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Varsler'),
        centerTitle: true,
      ),
      body: isSuperAdmin
          ? const ProfileNotificationsTab()
          : const _NotificationSettingsOnlyBody(),
    );
  }
}

class _NotificationSettingsOnlyBody extends StatelessWidget {
  const _NotificationSettingsOnlyBody();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Material(
            color: DriftProTheme.primaryGreen.withValues(alpha: 0.08),
            child: const TabBar(
              labelColor: DriftProTheme.primaryGreen,
              unselectedLabelColor: Colors.grey,
              indicatorColor: DriftProTheme.primaryGreen,
              tabs: [
                Tab(text: 'MAVI-ansatte'),
                Tab(text: 'Samarbeid'),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [
                MaviNotificationSettingsPanel(),
                PartnerNotificationSettingsPanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
