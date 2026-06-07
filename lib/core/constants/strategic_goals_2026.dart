import 'package:flutter/material.dart';

enum StrategicGoalCategory { kvalitet, hms, miljo }

enum StrategicGoalCompare { min, max, exact, zeroBest }

class StrategicGoal {
  final String id;
  final StrategicGoalCategory category;
  final String title;
  final String targetDisplay;
  final String description;
  final IconData icon;
  final StrategicGoalCompare compare;
  final double? targetValue;
  final String? metricKey;

  const StrategicGoal({
    required this.id,
    required this.category,
    required this.title,
    required this.targetDisplay,
    required this.description,
    required this.icon,
    required this.compare,
    this.targetValue,
    this.metricKey,
  });
}

/// Strategiske målsetninger 2026 — MAVI (fra styringsdokument).
abstract final class StrategicGoals2026 {
  static const title = 'Strategiske mål 2026';
  static const subtitle = 'MAVI · Overordnede målsetninger';

  static const goals = <StrategicGoal>[
    StrategicGoal(
      id: 'nps',
      category: StrategicGoalCategory.kvalitet,
      title: 'Kundetilfredshet',
      targetDisplay: '≥ 54 NPS',
      description: 'Aktiv overvåking av kunderespons og kontinuerlig forbedring.',
      icon: Icons.sentiment_satisfied_alt_outlined,
      compare: StrategicGoalCompare.min,
      targetValue: 54,
    ),
    StrategicGoal(
      id: 'levering',
      category: StrategicGoalCategory.kvalitet,
      title: 'Leveringspresisjon',
      targetDisplay: '≥ 92 %',
      description: 'Pålitelighet og nøyaktighet i alle ledd av transporten.',
      icon: Icons.local_shipping_outlined,
      compare: StrategicGoalCompare.min,
      targetValue: 92,
    ),
    StrategicGoal(
      id: 'behandlingstid',
      category: StrategicGoalCategory.kvalitet,
      title: 'Behandlingstid kundesaker',
      targetDisplay: '≤ 1 time',
      description: 'MAVI Logistikk. Hurtig respons er kritisk for servicegraden.',
      icon: Icons.timer_outlined,
      compare: StrategicGoalCompare.max,
      targetValue: 1,
    ),
    StrategicGoal(
      id: 'hub_skade',
      category: StrategicGoalCategory.kvalitet,
      title: 'Skade / tap på hub',
      targetDisplay: '≤ 100 000 kr',
      description: 'Inkl. «Lost at HUB». Sikker og nøyaktig håndtering.',
      icon: Icons.inventory_2_outlined,
      compare: StrategicGoalCompare.max,
      targetValue: 100000,
    ),
    StrategicGoal(
      id: 'vernerunde',
      category: StrategicGoalCategory.hms,
      title: 'Vernerunder',
      targetDisplay: '1 per år',
      description: 'Systematisk gjennomføring og dokumentasjon i egne bygg.',
      icon: Icons.health_and_safety_outlined,
      compare: StrategicGoalCompare.min,
      targetValue: 1,
      metricKey: 'safety_rounds_planned',
    ),
    StrategicGoal(
      id: 'brann',
      category: StrategicGoalCategory.hms,
      title: 'Brannvernrunde',
      targetDisplay: 'Årlig iht. lov',
      description: 'I egne bygg. Strategisk samarbeid med Elkjøp.',
      icon: Icons.local_fire_department_outlined,
      compare: StrategicGoalCompare.exact,
    ),
    StrategicGoal(
      id: 'fravaer',
      category: StrategicGoalCategory.hms,
      title: 'Fravær',
      targetDisplay: '≤ 9,9 %',
      description: 'Gjennomsnitt pr. år. Fokus på trivsel og arbeidsmiljø.',
      icon: Icons.event_busy_outlined,
      compare: StrategicGoalCompare.max,
      targetValue: 9.9,
      metricKey: 'absence_rate',
    ),
    StrategicGoal(
      id: 'sikkerhet',
      category: StrategicGoalCategory.hms,
      title: 'Sikkerhet',
      targetDisplay: '0 alvorlige',
      description: 'Iht. internkontroll og gjennomførte risikoanalyser.',
      icon: Icons.shield_outlined,
      compare: StrategicGoalCompare.zeroBest,
      metricKey: 'critical_tickets',
    ),
    StrategicGoal(
      id: 'bomtur',
      category: StrategicGoalCategory.miljo,
      title: 'Bomtur',
      targetDisplay: '≤ 6 %',
      description: 'SMS + telefonisk daglig kontroll for å fjerne bomkjøring.',
      icon: Icons.route_outlined,
      compare: StrategicGoalCompare.max,
      targetValue: 6,
    ),
    StrategicGoal(
      id: 'utslipp',
      category: StrategicGoalCategory.miljo,
      title: 'Utslippsreduksjon',
      targetDisplay: '−30 %',
      description: 'ECO-Driving kurs for alle selskapets sjåfører.',
      icon: Icons.eco_outlined,
      compare: StrategicGoalCompare.min,
      targetValue: 30,
    ),
    StrategicGoal(
      id: 'bilpark',
      category: StrategicGoalCategory.miljo,
      title: 'Bilpark-strategi',
      targetDisplay: 'Nullutslipp',
      description: 'Nye innkjøp i egen regi skal være elektriske eller utslippsfrie.',
      icon: Icons.electric_car_outlined,
      compare: StrategicGoalCompare.exact,
    ),
    StrategicGoal(
      id: 'retur',
      category: StrategicGoalCategory.miljo,
      title: 'Returhåndtering',
      targetDisplay: '100 % korrekt',
      description: 'Korrekt produkttype og mengde ved retur av miljøavfall.',
      icon: Icons.recycling_outlined,
      compare: StrategicGoalCompare.exact,
    ),
  ];

  static String categoryLabel(StrategicGoalCategory c) => switch (c) {
        StrategicGoalCategory.kvalitet => 'Kvalitet',
        StrategicGoalCategory.hms => 'HMS',
        StrategicGoalCategory.miljo => 'Ytre miljø',
      };

  static Color categoryColor(StrategicGoalCategory c) => switch (c) {
        StrategicGoalCategory.kvalitet => const Color(0xFF1565C0),
        StrategicGoalCategory.hms => const Color(0xFF0D9488),
        StrategicGoalCategory.miljo => const Color(0xFF059669),
      };
}
