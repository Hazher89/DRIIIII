import '../routing/app_paths.dart';

/// Kategori i MAVI HMS-håndbok (IK-system + vedlegg).
enum HmsHandbookCategory {
  styring,
  risiko,
  avvik,
  sja,
  beredskap,
  instrukser,
  signatur,
}

extension HmsHandbookCategoryX on HmsHandbookCategory {
  String get title => switch (this) {
        HmsHandbookCategory.styring => 'Styring og policy',
        HmsHandbookCategory.risiko => 'Risikovurdering',
        HmsHandbookCategory.avvik => 'Avvik og RUH',
        HmsHandbookCategory.sja => 'Sikker jobbanalyse',
        HmsHandbookCategory.beredskap => 'Beredskap',
        HmsHandbookCategory.instrukser => 'Instrukser',
        HmsHandbookCategory.signatur => 'Signatur og opplæring',
      };

  String get subtitle => switch (this) {
        HmsHandbookCategory.styring => 'IK-system, mål, erklæringer og etikk',
        HmsHandbookCategory.risiko => 'Diagrammer og kobling til ROS i DriftPro',
        HmsHandbookCategory.avvik => 'Rapportering av uønskede hendelser',
        HmsHandbookCategory.sja => 'Mal for sikker jobbanalyse',
        HmsHandbookCategory.beredskap => 'Alvorlig ulykke og brann',
        HmsHandbookCategory.instrukser => 'Tungløft, rus, avfall, byggekort',
        HmsHandbookCategory.signatur => 'Bekreftelse fra ansatte',
      };

  String get iconName => switch (this) {
        HmsHandbookCategory.styring => 'policy',
        HmsHandbookCategory.risiko => 'risk',
        HmsHandbookCategory.avvik => 'incident',
        HmsHandbookCategory.sja => 'sja',
        HmsHandbookCategory.beredskap => 'emergency',
        HmsHandbookCategory.instrukser => 'instructions',
        HmsHandbookCategory.signatur => 'signature',
      };
}

/// Ett dokument i håndboka — tekst fra assets + valgfri modul-lenke.
class HmsHandbookDoc {
  const HmsHandbookDoc({
    required this.id,
    required this.category,
    required this.title,
    required this.shortLabel,
    required this.assetPath,
    required this.summary,
    this.vedleggNr,
    this.modulePath,
    this.moduleLabel,
  });

  final String id;
  final HmsHandbookCategory category;
  final String title;
  final String shortLabel;
  final String assetPath;
  final String summary;
  final String? vedleggNr;
  final String? modulePath;
  final String? moduleLabel;
}

/// MAVI Logistikk IK-system / vedlegg — ryddig katalog for DriftPro HMS.
abstract final class MaviHmsHandbook {
  static const docs = <HmsHandbookDoc>[
    HmsHandbookDoc(
      id: 'ik_system',
      category: HmsHandbookCategory.styring,
      title: 'Internkontrollsystem HMS',
      shortLabel: 'IK-system',
      vedleggNr: 'Hoveddok.',
      assetPath: 'assets/hms/handbok/ik_system_hms.txt',
      summary:
          'Hoveddokument for systematisk HMS-arbeid i MAVI Logistikk AS (org.nr 912 332 209).',
      modulePath: AppPaths.hms,
      moduleLabel: 'Tilbake til HMS-hub',
    ),
    HmsHandbookDoc(
      id: 'hms_plan',
      category: HmsHandbookCategory.styring,
      title: 'HMS-plan og målsetting',
      shortLabel: 'HMS-plan',
      vedleggNr: 'Plan',
      assetPath: 'assets/hms/handbok/hms_plan_maalsetting.txt',
      summary:
          'Mål for helse, miljø og sikkerhet, ansvarsfordeling og risikokartlegging.',
    ),
    HmsHandbookDoc(
      id: 'hms_erklaering',
      category: HmsHandbookCategory.styring,
      title: 'HMS-erklæring',
      shortLabel: 'Erklæring',
      vedleggNr: '1',
      assetPath: 'assets/hms/handbok/vedlegg_01_hms_erklaering.txt',
      summary:
          'Ledelsens forpliktelse til trygt arbeidsmiljø, internkontroll og forbedring.',
    ),
    HmsHandbookDoc(
      id: 'egenerklaering',
      category: HmsHandbookCategory.styring,
      title: 'HMS-egenerklæring',
      shortLabel: 'Egenerklæring',
      vedleggNr: '1.1',
      assetPath: 'assets/hms/handbok/vedlegg_01_1_egenerklaering.txt',
      summary:
          'Bekreftelse på at virksomheten arbeider etter internkontrollforskriften.',
    ),
    HmsHandbookDoc(
      id: 'etikk',
      category: HmsHandbookCategory.styring,
      title: 'Etiske retningslinjer',
      shortLabel: 'Etikk',
      vedleggNr: '2',
      assetPath: 'assets/hms/handbok/vedlegg_02_etiske.txt',
      summary:
          'Etikk for ansatte og samarbeidspartnere — menneskerettigheter, anti-korrupsjon og miljø.',
    ),
    HmsHandbookDoc(
      id: 'risiko_mennesker',
      category: HmsHandbookCategory.risiko,
      title: 'Risikodiagram — mennesker',
      shortLabel: 'Mennesker',
      vedleggNr: '3.3',
      assetPath: 'assets/hms/handbok/vedlegg_03_3_risiko_mennesker.txt',
      summary:
          'Risikodiagram for personskade. Bruk DriftPro risikoanalyse for aktive vurderinger.',
      modulePath: AppPaths.hmsRisiko,
      moduleLabel: 'Åpne risikoanalyser',
    ),
    HmsHandbookDoc(
      id: 'risiko_miljo',
      category: HmsHandbookCategory.risiko,
      title: 'Risikodiagram — miljø',
      shortLabel: 'Miljø',
      vedleggNr: '3.2',
      assetPath: 'assets/hms/handbok/vedlegg_03_2_risiko_miljo.txt',
      summary:
          'Risikodiagram for ytre miljø. Koble til ROS og tiltak i DriftPro.',
      modulePath: AppPaths.hmsRisikomatrise,
      moduleLabel: 'Åpne risikomatrise',
    ),
    HmsHandbookDoc(
      id: 'risiko_okonomi',
      category: HmsHandbookCategory.risiko,
      title: 'Risikodiagram — økonomi',
      shortLabel: 'Økonomi',
      vedleggNr: '3.1',
      assetPath: 'assets/hms/handbok/vedlegg_03_1_risiko_okonomi.txt',
      summary:
          'Risikodiagram for økonomiske konsekvenser av hendelser.',
      modulePath: AppPaths.hmsRisiko,
      moduleLabel: 'Åpne risikoanalyser',
    ),
    HmsHandbookDoc(
      id: 'ruh',
      category: HmsHandbookCategory.avvik,
      title: 'RUH — Rapportering av uønsket hendelse',
      shortLabel: 'RUH',
      vedleggNr: '5',
      assetPath: 'assets/hms/handbok/vedlegg_05_ruh.txt',
      summary:
          'Skjema og saksgang for nestenulykker, farlige forhold og avvik. I DriftPro: bruk Avvik.',
      modulePath: AppPaths.hmsAvvik,
      moduleLabel: 'Registrer avvik / RUH',
    ),
    HmsHandbookDoc(
      id: 'sja_mal',
      category: HmsHandbookCategory.sja,
      title: 'SJA-mal',
      shortLabel: 'SJA',
      vedleggNr: '6',
      assetPath: 'assets/hms/handbok/vedlegg_06_sja_mal.txt',
      summary:
          'Papirmal for sikker jobbanalyse. Digitale SJA-er med maler finnes under SJA.',
      modulePath: AppPaths.hmsSja,
      moduleLabel: 'Opprett SJA',
    ),
    HmsHandbookDoc(
      id: 'ulykke',
      category: HmsHandbookCategory.beredskap,
      title: 'Instruks ved alvorlig ulykke',
      shortLabel: 'Ulykke',
      vedleggNr: '9',
      assetPath: 'assets/hms/handbok/vedlegg_09_alvorlig_ulykke.txt',
      summary:
          'Varselrutine (113/112/110), adresse Solheimveien 3, førstehjelp og varsling av leder.',
      modulePath: AppPaths.hmsVernerunde,
      moduleLabel: 'Vernerunde / beredskap',
    ),
    HmsHandbookDoc(
      id: 'brann',
      category: HmsHandbookCategory.beredskap,
      title: 'Branninstruks',
      shortLabel: 'Brann',
      vedleggNr: '10',
      assetPath: 'assets/hms/handbok/vedlegg_10_brann.txt',
      summary:
          'Rømning, alarm, slukking og varsling av brannvesen (110).',
      modulePath: AppPaths.hmsVernerunde,
      moduleLabel: 'Start vernerunde',
    ),
    HmsHandbookDoc(
      id: 'tungloft',
      category: HmsHandbookCategory.instrukser,
      title: 'Instruks for tunge løft',
      shortLabel: 'Tungløft',
      vedleggNr: '12',
      assetPath: 'assets/hms/handbok/vedlegg_12_tungloft.txt',
      summary:
          'Grønn / gul / rød vurdering, hjelpemidler og arbeidsstillinger. Se også bildeguiden.',
      modulePath: AppPaths.hmsTungloft,
      moduleLabel: 'Åpne Tungløft-guide',
    ),
    HmsHandbookDoc(
      id: 'rus',
      category: HmsHandbookCategory.instrukser,
      title: 'Instruks for alkohol og rus',
      shortLabel: 'Rus',
      vedleggNr: '11',
      assetPath: 'assets/hms/handbok/vedlegg_11_rus.txt',
      summary:
          'Nulltoleranse for ruspåvirkning på jobb; regler ved representasjon.',
    ),
    HmsHandbookDoc(
      id: 'avfall',
      category: HmsHandbookCategory.instrukser,
      title: 'Avfallsinstruks',
      shortLabel: 'Avfall',
      vedleggNr: '13',
      assetPath: 'assets/hms/handbok/vedlegg_13_avfall.txt',
      summary:
          'Sortering: papir/papp, plast, EE-avfall, restavfall/isopor. Tømming via Norsk Ombruk.',
    ),
    HmsHandbookDoc(
      id: 'byggekort',
      category: HmsHandbookCategory.instrukser,
      title: 'Instruks for byggekort',
      shortLabel: 'Byggekort',
      vedleggNr: '14',
      assetPath: 'assets/hms/handbok/vedlegg_14_byggekort.txt',
      summary:
          'Bestilling, personlig bruk og fornyelse av byggekort før arbeid på byggeplass.',
      modulePath: AppPaths.hmsKompetanse,
      moduleLabel: 'Kompetanse / kurs',
    ),
    HmsHandbookDoc(
      id: 'signatur',
      category: HmsHandbookCategory.signatur,
      title: 'Signaturdokument ansatte',
      shortLabel: 'Signatur',
      vedleggNr: '8',
      assetPath: 'assets/hms/handbok/vedlegg_08_signatur.txt',
      summary:
          'Bekreftelse på at ansatte kjenner IK-system, etikk, RUH, SJA, rett til å stanse farlig arbeid m.m.',
      modulePath: AppPaths.hmsOpplaering,
      moduleLabel: 'HMS-opplæring',
    ),
  ];

  static List<HmsHandbookCategory> get categories => HmsHandbookCategory.values;

  static List<HmsHandbookDoc> docsIn(HmsHandbookCategory c) =>
      docs.where((d) => d.category == c).toList();

  static HmsHandbookDoc? byId(String id) {
    for (final d in docs) {
      if (d.id == id) return d;
    }
    return null;
  }
}
