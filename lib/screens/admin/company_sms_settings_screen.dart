import 'package:flutter/material.dart';

import '../partners/widgets/partner_notification_settings_panel.dart';
import '../profile/widgets/mavi_notification_settings_panel.dart';

/// Varselinnstillinger (full skjerm – MAVI + samarbeid).
class CompanySmsSettingsScreen extends StatelessWidget {
  const CompanySmsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Varselinnstillinger')),
      body: const DefaultTabController(
        length: 2,
        child: Column(
          children: [
            TabBar(
              tabs: [
                Tab(text: 'MAVI-ansatte'),
                Tab(text: 'Samarbeid'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  MaviNotificationSettingsPanel(),
                  PartnerNotificationSettingsPanel(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
