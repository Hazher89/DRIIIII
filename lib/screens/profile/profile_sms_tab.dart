import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'widgets/company_sms_settings_panel.dart';
import 'widgets/sms_outbox_log_panel.dart';

/// Superadmin: SMS-logg + innstillinger i profil.
class ProfileSmsTab extends StatelessWidget {
  const ProfileSmsTab({super.key});

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
                Tab(
                  icon: Icon(Icons.outbox_outlined, size: 20),
                  text: 'Sendte SMS',
                ),
                Tab(
                  icon: Icon(Icons.settings_outlined, size: 20),
                  text: 'SMS-innstillinger',
                ),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [
                SmsOutboxLogPanel(),
                CompanySmsSettingsPanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
