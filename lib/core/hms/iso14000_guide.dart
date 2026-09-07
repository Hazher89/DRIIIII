import '../routing/app_paths.dart';

/// Høy-nivå oversikt over ISO 14000-serien for DriftPro HMS.
///
/// Inneholder ikke opphavsrettsbeskyttet standardtekst — kun veiledende
/// oppsummering + kobling til MAVI sitt miljøarbeid i appen.
abstract final class Iso14000Guide {
  static const seriesTitle = 'NS-EN ISO 14000-serien';
  static const seriesSubtitle = 'Ledelsessystemer for miljø';

  static const disclaimer =
      'Denne siden er en praktisk oversikt for MAVI — ikke en erstatning for '
      'originale standarder fra Standard Norge. Bruk standardsamlingen for '
      'full tekst ved revisjon og sertifisering.';

  static const standards = <IsoStandardCard>[
    IsoStandardCard(
      id: 'iso14001',
      code: 'NS-EN ISO 14001:2015',
      title: 'Ledelsessystemer for miljø',
      shortTitle: '14001',
      role: 'Kravstandard (sertifiserbar)',
      summary:
          'Setter krav til et miljøledelsessystem: kontekst, lederskap, planlegging, '
          'støtte, drift, evaluering og forbedring (PDCA). Dette er ryggraden i MAVI sin miljøhåndbok.',
      forMavi: [
        'Miljøpolicy og lederskap',
        'Miljøaspekter, risiko og muligheter',
        'Samsvar med lovkrav',
        'Drift, beredskap og innkjøp',
        'Internrevisjon og ledelsens gjennomgåelse',
      ],
      handbookDocId: 'handbok_miljo_14001',
      modulePath: AppPaths.hmsRisikomatrise,
      moduleLabel: 'Risikomatrise (miljø)',
    ),
    IsoStandardCard(
      id: 'iso14004',
      code: 'NS-EN ISO 14004:2016',
      title: 'Generelle retningslinjer for implementering',
      shortTitle: '14004',
      role: 'Veiledning',
      summary:
          'Forklarer hvordan du bygger og vedlikeholder et miljøledelsessystem i praksis. '
          'Støtter implementering av 14001 uten å være sertifiseringsgrunnlag alene.',
      forMavi: [
        'Hvordan beskrive kontekst og interesseparter',
        'Hvordan prioritere miljøaspekter',
        'Hvordan forankre systemet i daglig drift',
        'Eksempler på god praksis ved innføring',
      ],
      handbookDocId: 'kartlegging_interesseparter',
      modulePath: AppPaths.hmsRisiko,
      moduleLabel: 'Risikovurdering',
    ),
    IsoStandardCard(
      id: 'iso14031',
      code: 'NS-EN ISO 14031:2013',
      title: 'Evaluering av miljøprestasjon',
      shortTitle: '14031',
      role: 'Veiledning',
      summary:
          'Gir retningslinjer for å velge indikatorer og følge miljøprestasjon over tid — '
          'f.eks. avfall, energi/CO₂ og sorteringsgrad.',
      forMavi: [
        'Velge relevante miljøindikatorer',
        'Følge prestasjon mot miljømål',
        'Bruke tall i ledelsens gjennomgåelse',
      ],
      handbookDocId: 'miljoaspekter_samsvar',
      modulePath: null,
      moduleLabel: null,
    ),
    IsoStandardCard(
      id: 'iso14063',
      code: 'NS-EN ISO 14063:2020',
      title: 'Miljøkommunikasjon',
      shortTitle: '14063',
      role: 'Veiledning',
      summary:
          'Hvordan kommunisere miljøinformasjon internt og eksternt — ærlig, forståelig og tilpasset mottaker.',
      forMavi: [
        'Intern bevisstgjøring av ansatte og partnere',
        'Ekstern dialog med kunder og myndigheter',
        'Unngå grønnvasking — vær konkret',
      ],
      handbookDocId: 'rutiner_samarbeidspartnere',
      modulePath: null,
      moduleLabel: null,
    ),
    IsoStandardCard(
      id: 'iso19011',
      code: 'NS-EN ISO 19011:2018',
      title: 'Retningslinjer for revisjon av ledelsessystemer',
      shortTitle: '19011',
      role: 'Veiledning (revisjon)',
      summary:
          'Felles revisjonsprinsipper for ledelsessystemer (inkl. miljø). Brukes ved intern '
          'og ekstern revisjon — planlegging, gjennomføring og oppfølging.',
      forMavi: [
        '3-års revisjonsplan og revisjonsprogram',
        'Intern / ekstern revisjon',
        'Avvik og forbedring etter revisjon',
      ],
      handbookDocId: 'intern_ekstern_revisjon',
      modulePath: AppPaths.hmsHandbok,
      moduleLabel: 'HMS-håndbok · Revisjon',
    ),
  ];

  static const pdca = <IsoPdcaStep>[
    IsoPdcaStep(
      letter: 'P',
      title: 'Plan',
      subtitle: 'Planlegg',
      points: [
        'Kontekst og interesseparter',
        'Miljøaspekter, risiko og muligheter',
        'Miljømål og handlingsplaner',
        'Samsvarskrav',
      ],
    ),
    IsoPdcaStep(
      letter: 'D',
      title: 'Do',
      subtitle: 'Gjennomfør',
      points: [
        'Kompetanse og bevissthet',
        'Drift og innkjøp',
        'Beredskap',
        'Dokumentert informasjon',
      ],
    ),
    IsoPdcaStep(
      letter: 'C',
      title: 'Check',
      subtitle: 'Kontroller',
      points: [
        'Overvåking og måling',
        'Samsvarsevaluering',
        'Internrevisjon',
        'Ledelsens gjennomgåelse',
      ],
    ),
    IsoPdcaStep(
      letter: 'A',
      title: 'Act',
      subtitle: 'Forbedre',
      points: [
        'Avvik og korrigerende tiltak',
        'Kontinuerlig forbedring',
        'Oppdater mål og risiko',
      ],
    ),
  ];

  static IsoStandardCard? byId(String id) {
    for (final s in standards) {
      if (s.id == id) return s;
    }
    return null;
  }
}

class IsoStandardCard {
  const IsoStandardCard({
    required this.id,
    required this.code,
    required this.title,
    required this.shortTitle,
    required this.role,
    required this.summary,
    required this.forMavi,
    this.handbookDocId,
    this.modulePath,
    this.moduleLabel,
  });

  final String id;
  final String code;
  final String title;
  final String shortTitle;
  final String role;
  final String summary;
  final List<String> forMavi;
  final String? handbookDocId;
  final String? modulePath;
  final String? moduleLabel;
}

class IsoPdcaStep {
  const IsoPdcaStep({
    required this.letter,
    required this.title,
    required this.subtitle,
    required this.points,
  });

  final String letter;
  final String title;
  final String subtitle;
  final List<String> points;
}
