import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'employee_notification_recipients_panel.dart';
import 'unified_notification_settings_panel.dart';

/// Innstillinger: MAVI-ansatte (per bruker) | Samarbeid (partnervarsler).
class NotificationSettingsSplitTab extends StatelessWidget {
  const NotificationSettingsSplitTab({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Material(
            color: Colors.grey.shade100,
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
                EmployeeNotificationRecipientsPanel(),
                UnifiedNotificationSettingsPanel(scope: NotificationSettingsScope.partner),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
