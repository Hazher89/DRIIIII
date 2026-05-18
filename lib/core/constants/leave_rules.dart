import '../../models/absence.dart';

/// Norske regler for fravær (referanse: Lovdata / folketrygd / ferieloven).
/// Bedriften kan ha tariffavtale som gir mer — sjekk alltid med HR.
class LeaveRules {
  LeaveRules._();

  // ── Egenmelding (aml. § 4-3, praksis + folketrygd) ─────────────────────
  static const int egenmeldingMaxConsecutiveDays = 3;
  static const int egenmeldingMaxPeriodsPerYear = 4;
  static const int egenmeldingMaxDaysPerYear = 24;

  // ── Sykt barn (folketrygdloven kap. 5) ─────────────────────────────────
  static const int syktBarnDaysPerChildUnder12 = 10;
  static const int syktBarnDaysTwoOrMoreChildren = 15;
  static const int syktBarnMaxAgeStandard = 12;

  // ── Ferie (ferieloven) ─────────────────────────────────────────────────
  static const int ferieLegalMinimumDays = 25;
  static const int ferieMainHolidayDays = 18;
  static const int defaultMaxCarryoverDays = 14;

  static const String lovdataEgenmeldingTitle = 'Egenmelding';
  static const String lovdataEgenmeldingBody =
      'Arbeidstaker kan melde egen sykdom uten sykmelding i inntil 3 kalenderdager '
      'om gangen (tariff/HR-avtale kan gi mer). Maks 4 egenmeldingsperioder per '
      'kalenderår. Ved lengre fravær kreves sykmelding fra lege. '
      'Kilde: arbeidsmiljøloven § 4-3, praksis under folketrygdloven.';

  static const String lovdataSyktBarnTitle = 'Omsorgspenger / sykt barn';
  static const String lovdataSyktBarnBody =
      'Foreldre har rett til inntil 10 dager omsorgspenger per kalenderår per barn '
      'under 12 år (15 dager ved 2+ barn). For barn 12–18 år gjelder 10 dager ved '
      'kronisk/langvarig sykdom eller funksjonshemning. '
      'Kilde: folketrygdloven kap. 5 (Lovdata).';

  static const String lovdataFerieTitle = 'Ferieloven';
  static const String lovdataFerieBody =
      'Minimum 25 virkedager ferie per år. Hovedferie (18 dager) skal som hovedregel '
      'gis i perioden 1. juni – 30. september. Ubrukte dager kan overføres til neste '
      'år etter avtale (ofte inntil 14 dager). '
      'Kilde: ferieloven (Lovdata).';

  static List<LeaveRuleCard> cardsForType(AbsenceType? type) {
    if (type == null) {
      return const [
        LeaveRuleCard(
          title: lovdataEgenmeldingTitle,
          body: lovdataEgenmeldingBody,
          iconName: 'person',
        ),
        LeaveRuleCard(
          title: lovdataSyktBarnTitle,
          body: lovdataSyktBarnBody,
          iconName: 'child',
        ),
        LeaveRuleCard(
          title: lovdataFerieTitle,
          body: lovdataFerieBody,
          iconName: 'sun',
        ),
      ];
    }
    switch (type) {
      case AbsenceType.egenmelding:
        return const [
          LeaveRuleCard(
            title: lovdataEgenmeldingTitle,
            body: lovdataEgenmeldingBody,
            iconName: 'person',
          ),
        ];
      case AbsenceType.syktBarn:
        return const [
          LeaveRuleCard(
            title: lovdataSyktBarnTitle,
            body: lovdataSyktBarnBody,
            iconName: 'child',
          ),
        ];
      case AbsenceType.ferie:
        return const [
          LeaveRuleCard(
            title: lovdataFerieTitle,
            body: lovdataFerieBody,
            iconName: 'sun',
          ),
        ];
      default:
        return const [];
    }
  }
}

class LeaveRuleCard {
  final String title;
  final String body;
  final String iconName;

  const LeaveRuleCard({
    required this.title,
    required this.body,
    required this.iconName,
  });
}

class CompanyLeaveSettings {
  final int egenmeldingDaysPerYear;
  final int egenmeldingConsecutiveMax;
  final int maxVacationCarryover;

  const CompanyLeaveSettings({
    this.egenmeldingDaysPerYear = LeaveRules.egenmeldingMaxDaysPerYear,
    this.egenmeldingConsecutiveMax = LeaveRules.egenmeldingMaxConsecutiveDays,
    this.maxVacationCarryover = LeaveRules.defaultMaxCarryoverDays,
  });

  factory CompanyLeaveSettings.fromJson(Map<String, dynamic> json) {
    return CompanyLeaveSettings(
      egenmeldingDaysPerYear:
          json['egenmelding_days_per_year'] as int? ?? LeaveRules.egenmeldingMaxDaysPerYear,
      egenmeldingConsecutiveMax:
          json['egenmelding_consecutive_max'] as int? ?? LeaveRules.egenmeldingMaxConsecutiveDays,
      maxVacationCarryover:
          json['max_vacation_carryover'] as int? ?? LeaveRules.defaultMaxCarryoverDays,
    );
  }

  /// Maks sykt-barn-dager per år (forenklet modell: 10, 15 ved flere barn i HR-notat).
  int syktBarnDaysLimit({int childrenCount = 1}) =>
      childrenCount >= 2
          ? LeaveRules.syktBarnDaysTwoOrMoreChildren
          : LeaveRules.syktBarnDaysPerChildUnder12;
}
