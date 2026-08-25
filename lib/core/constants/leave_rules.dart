import '../../models/absence.dart';

/// Norske regler for fravær (referanse: Lovdata / folketrygd / ferieloven).
/// Bedriften kan ha tariffavtale som gir mer — sjekk alltid med HR.
class LeaveRules {
  LeaveRules._();

  // ── Egenmelding (aml. § 4-3, praksis + folketrygd) ─────────────────────
  /// Maks kalenderdager per egenmeldingsperiode (hard tak i appen).
  static const int egenmeldingMaxConsecutiveDays = 5;
  static const int egenmeldingMaxPeriodsPerYear = 4;
  static const int egenmeldingMaxDaysPerYear = 24;

  // ── Sykt barn (folketrygdloven kap. 5) ─────────────────────────────────
  static const int syktBarnDaysPerChildUnder12 = 10;
  static const int syktBarnDaysTwoOrMoreChildren = 15;
  static const int syktBarnMaxAgeStandard = 12;

  /// Sykt-barn-dager per 12-måneders periode ut fra registrerte barn under 12.
  static int syktBarnDaysLimit(int childrenUnder12) =>
      childrenUnder12 >= 2
          ? syktBarnDaysTwoOrMoreChildren
          : syktBarnDaysPerChildUnder12;

  // ── Ferie (ferieloven) ─────────────────────────────────────────────────
  static const int ferieLegalMinimumDays = 25;
  static const int ferieMainHolidayDays = 18;
  static const int defaultMaxCarryoverDays = 14;

  static const String lovdataEgenmeldingTitle = 'Egenmelding';
  static const String lovdataEgenmeldingBody =
      'Arbeidstaker kan melde egen sykdom uten sykmelding i inntil 5 kalenderdager '
      'om gangen (bedriftens HR-avtale kan være strengere). Maks 4 egenmeldingsperioder og '
      '24 dager i en 12-måneders periode fra ansettelsesdato (nullstilles ikke 1. januar). '
      'Ved lengre fravær kreves sykmelding fra lege. '
      'Kilde: arbeidsmiljøloven § 4-3, praksis under folketrygdloven.';

  static const String lovdataSyktBarnTitle = 'Omsorgspenger / sykt barn';
  static const String lovdataSyktBarnBody =
      'Foreldre har rett til inntil 10 dager omsorgspenger per 12-måneders periode '
      'fra ansettelsesdato per barn under 12 år (15 dager ved 2+ barn). '
      'For barn 12–18 år gjelder 10 dager ved kronisk/langvarig sykdom eller funksjonshemning. '
      'Kilde: folketrygdloven kap. 5 (Lovdata).';

  static const String lovdataFerieTitle = 'Ferieloven';
  static const String lovdataFerieBody =
      'Minimum 25 virkedager ferie per år. Hovedferie (18 dager) skal som hovedregel '
      'gis i perioden 1. juni – 30. september. Ubrukte dager kan overføres til neste '
      'år etter avtale (ofte inntil 14 dager). '
      'Kilde: ferieloven (Lovdata).';

  static const String lovdataSykmeldingTitle = 'Sykmelding';
  static const String lovdataSykmeldingBody =
      'Arbeidsgiver kan kreve sykmelding fra lege når fravær overstiger det som er '
      'lovlig med egenmelding, eller ved gjentatt korttidsfravær. Sykepenger fra '
      'NAV krever som hovedregel sykmelding. '
      'Kilde: folketrygdloven kap. 8 (Lovdata).';

  static const String lovdataPermisjonTitle = 'Permisjon uten lønn';
  static const String lovdataPermisjonBody =
      'Permisjon uten lønn avtales med arbeidsgiver og skal dokumenteres. Det er ikke '
      'samme rettigheter som ferie eller egenmelding — vurder konsekvens for pensjon '
      'og ferieavregning. '
      'Kilde: arbeidsmiljøloven kap. 12 (Lovdata).';

  static const String lovdataArbeidsmiljoTitle = 'Arbeidsmiljø og fravær';
  static const String lovdataArbeidsmiljoBody =
      'Arbeidsgiver skal følge opp sykefravær og tilrettelegge (aml. § 4-3, § 4-6). '
      'Dialogmøter ved langvarig fravær. HMS-avvik og fravær bør sees i sammenheng. '
      'Kilde: arbeidsmiljøloven (Lovdata).';

  static const String lovdataPersonvernTitle = 'Personvern i fravær';
  static const String lovdataPersonvernBody =
      'Opplysninger om helse og fravær er sensitive personopplysninger (GDPR art. 9). '
      'Del kun det som er nødvendig for godkjenning og planlegging. '
      'Kilde: personopplysningsloven / GDPR.';

  static const String lovdataTipsTitle = 'Gode rutiner for ledere';
  static const String lovdataTipsBody =
      '• Godkjenn ferie i god tid og sjekk overlapping i avdelingen.\n'
      '• Følg opp ansatte uten egenmelding igjen før ny sykemelding.\n'
      '• Dokumenter avtaler skriftlig (ferie, permisjon, overføring).\n'
      '• Ved tvil: sjekk tariffavtale og bedriftens HR-retningslinjer.';

  /// Alle Lovdata-relaterte kort for leder-oversikt.
  static List<LeaveRuleCard> managerOverviewCards() => const [
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
        LeaveRuleCard(
          title: lovdataSykmeldingTitle,
          body: lovdataSykmeldingBody,
          iconName: 'medical',
        ),
        LeaveRuleCard(
          title: lovdataPermisjonTitle,
          body: lovdataPermisjonBody,
          iconName: 'timer',
        ),
        LeaveRuleCard(
          title: lovdataArbeidsmiljoTitle,
          body: lovdataArbeidsmiljoBody,
          iconName: 'shield',
        ),
        LeaveRuleCard(
          title: lovdataPersonvernTitle,
          body: lovdataPersonvernBody,
          iconName: 'lock',
        ),
        LeaveRuleCard(
          title: lovdataTipsTitle,
          body: lovdataTipsBody,
          iconName: 'tips',
        ),
      ];

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
      case AbsenceType.sykmelding:
        return const [
          LeaveRuleCard(
            title: lovdataSykmeldingTitle,
            body: lovdataSykmeldingBody,
            iconName: 'medical',
          ),
        ];
      case AbsenceType.permisjon:
        return const [
          LeaveRuleCard(
            title: lovdataPermisjonTitle,
            body: lovdataPermisjonBody,
            iconName: 'timer',
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
    final rawConsec =
        json['egenmelding_consecutive_max'] as int? ?? LeaveRules.egenmeldingMaxConsecutiveDays;
    return CompanyLeaveSettings(
      egenmeldingDaysPerYear:
          json['egenmelding_days_per_year'] as int? ?? LeaveRules.egenmeldingMaxDaysPerYear,
      // Hard tak: aldri mer enn appens maks (5 dager) per periode.
      egenmeldingConsecutiveMax:
          rawConsec.clamp(1, LeaveRules.egenmeldingMaxConsecutiveDays),
      maxVacationCarryover:
          json['max_vacation_carryover'] as int? ?? LeaveRules.defaultMaxCarryoverDays,
    );
  }

  /// Effektiv maks per egenmeldingsøkt (bedrift ∩ hard tak).
  int get effectiveEgenmeldingConsecutiveMax =>
      egenmeldingConsecutiveMax.clamp(1, LeaveRules.egenmeldingMaxConsecutiveDays);

  /// Maks sykt-barn-dager per periode (10 dager / 15 ved 2+ barn under 12).
  int syktBarnDaysLimit({int childrenUnder12 = 0}) =>
      LeaveRules.syktBarnDaysLimit(childrenUnder12);
}
