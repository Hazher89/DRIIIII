import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Kort steg-for-steg for nye ruter (mobilvennlig).
class PartnerRouteHowToStrip extends StatelessWidget {
  const PartnerRouteHowToStrip({
    super.key,
    this.compact = false,
  });

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final steps = [
      _Step(1, 'Les ruten', 'Sjekk dato, starttid og bil.'),
      _Step(2, 'Åpne PDF', 'Trykk «Åpne rute-PDF» for kundeliste og detaljer.'),
      _Step(3, 'Aksepter', 'Trykk grønn knapp når alt stemmer.'),
    ];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        color: DriftProTheme.primaryGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DriftProTheme.primaryGreen.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, color: DriftProTheme.primaryGreenDark, size: compact ? 18 : 20),
              const SizedBox(width: 8),
              Text(
                'Slik håndterer du en ny rute',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: compact ? 13 : 14,
                  color: DriftProTheme.primaryGreenDark,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 8 : 12),
          ...steps.map((s) => Padding(
                padding: EdgeInsets.only(bottom: compact ? 6 : 8),
                child: _stepRow(s, compact),
              )),
        ],
      ),
    );
  }

  Widget _stepRow(_Step s, bool compact) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: compact ? 22 : 26,
          height: compact ? 22 : 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: DriftProTheme.primaryGreen,
            shape: BoxShape.circle,
          ),
          child: Text(
            '${s.n}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.title,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: compact ? 12 : 13,
                ),
              ),
              Text(
                s.subtitle,
                style: TextStyle(
                  fontSize: compact ? 11 : 12,
                  height: 1.3,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Step {
  const _Step(this.n, this.title, this.subtitle);
  final int n;
  final String title;
  final String subtitle;
}
