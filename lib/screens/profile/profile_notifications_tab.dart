import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'widgets/email_outbox_log_panel.dart';
import 'widgets/notification_audit_panel.dart';
import 'widgets/notification_settings_split_tab.dart';
import 'widgets/sms_outbox_log_panel.dart';

/// Superadmin: logg + innstillinger (MAVI og samarbeid adskilt).
class ProfileNotificationsTab extends StatelessWidget {
  const ProfileNotificationsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          Material(
            color: DriftProTheme.primaryGreen.withValues(alpha: 0.08),
            child: const TabBar(
              labelColor: DriftProTheme.primaryGreen,
              unselectedLabelColor: Colors.grey,
              indicatorColor: DriftProTheme.primaryGreen,
              isScrollable: true,
              tabs: [
                Tab(icon: Icon(Icons.sms_outlined, size: 20), text: 'SMS-logg'),
                Tab(icon: Icon(Icons.email_outlined, size: 20), text: 'E-post-logg'),
                Tab(icon: Icon(Icons.block, size: 20), text: 'Ikke sendt'),
                Tab(icon: Icon(Icons.tune, size: 20), text: 'Innstillinger'),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [
                SmsOutboxLogPanel(),
                EmailOutboxLogPanel(),
                NotificationAuditPanel(),
                NotificationSettingsSplitTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
