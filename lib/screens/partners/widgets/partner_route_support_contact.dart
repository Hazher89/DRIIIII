import 'package:flutter/material.dart';

import '../../../core/constants/partner_kjorekontor.dart';
import '../../../core/theme/app_theme.dart';

/// Partner/sjåfør: ingen avvisning — ring kjørekontor direkte fra nettleser/telefon.
class PartnerRouteSupportContactCard extends StatelessWidget {
  const PartnerRouteSupportContactCard({super.key});

  Future<void> _call(BuildContext context) async {
    final ok = await launchKjorekontorPhone();
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Kunne ikke starte anrop. Ring $kKjorekontorPhoneDisplay manuelt.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.blue.shade50,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.support_agent, color: Colors.blue.shade800),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Stemmer ikke ruten?',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Colors.blue.shade900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Avvisning gjøres ikke i portalen. Ring kjørekontoret — oppgi bilnummer og rutedato.',
              style: TextStyle(fontSize: 12, height: 1.35, color: Colors.blue.shade900),
            ),
            const SizedBox(height: 10),
            SelectableText(
              kKjorekontorPhoneDisplay,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
                color: Colors.blue.shade900,
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () => _call(context),
              icon: const Icon(Icons.phone_in_talk),
              label: const Text(
                'Ring kjørekontoret nå',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: DriftProTheme.primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
