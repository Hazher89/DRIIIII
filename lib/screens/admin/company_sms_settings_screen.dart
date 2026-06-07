import 'package:flutter/material.dart';

import '../profile/widgets/notification_settings_split_tab.dart';

/// Varselinnstillinger (MAVI-ansatte + samarbeid).
class CompanySmsSettingsScreen extends StatelessWidget {
  const CompanySmsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Varselinnstillinger')),
      body: const NotificationSettingsSplitTab(),
    );
  }
}
