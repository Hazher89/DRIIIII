import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Partner/sjåfør: ingen avvisning — kontakt kjørekontor.
class PartnerRouteSupportContactCard extends StatelessWidget {
  const PartnerRouteSupportContactCard({super.key});

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
              'Avvisning gjøres ikke i portalen. Ring kjørekontoret dersom noe ikke stemmer — '
              'MAVI hjelper deg videre.',
              style: TextStyle(fontSize: 12, height: 1.35, color: Colors.blue.shade900),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Kontakt kjørekontoret'),
                    content: const Text(
                      'Bruk telefonnummeret dere har fått fra MAVI / DriftPro. '
                      'Oppgi bilnummer og rutedato når du ringer.',
                    ),
                    actions: [
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.phone_in_talk_outlined),
              label: const Text(
                'Ring kjørekontoret',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: DriftProTheme.primaryGreen,
                side: BorderSide(color: DriftProTheme.primaryGreen.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
