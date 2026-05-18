import 'package:flutter/material.dart';

import 'widgets/sms_outbox_log_panel.dart';

/// Standalone SMS-logg (brukes fra andre steder om nødvendig).
class SmsLogScreen extends StatelessWidget {
  const SmsLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SMS-logg (Mavi)')),
      body: const SmsOutboxLogPanel(),
    );
  }
}
