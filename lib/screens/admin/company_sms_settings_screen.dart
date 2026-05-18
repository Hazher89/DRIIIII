import 'package:flutter/material.dart';

import '../profile/widgets/company_sms_settings_panel.dart';

/// SMS-innstillinger (full skjerm – f.eks. fra ansatt-hub).
class CompanySmsSettingsScreen extends StatelessWidget {
  const CompanySmsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SMS-varsler (Mavi)')),
      body: const CompanySmsSettingsPanel(),
    );
  }
}
