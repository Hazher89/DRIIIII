import '../routing/app_paths.dart';

/// Kategori i MAVI HMS-håndbok (IK-system + Landax QHSE).
enum HmsHandbookCategory {
  styring,
  miljo,
  risiko,
  revisjon,
  avvik,
  sja,
  beredskap,
  partnere,
  instrukser,
  signatur,
}

extension HmsHandbookCategoryX on HmsHandbookCategory {
  String get title => switch (this) {
        HmsHandbookCategory.styring => 'Styring og policy',
        HmsHandbookCategory.miljo => 'Miljø (ISO 14001)',
        HmsHandbookCategory.risiko => 'Risikovurdering',
        HmsHandbookCategory.revisjon => 'Revisjon og kontroll',
        HmsHandbookCategory.avvik => 'Avvik og RUH',
        HmsHandbookCategory.sja => 'Sikker jobbanalyse',
        HmsHandbookCategory.beredskap => 'Beredskap',
        HmsHandbookCategory.partnere => 'Samarbeidspartnere',
        HmsHandbookCategory.instrukser => 'Instrukser',
        HmsHandbookCategory.signatur => 'Signatur og opplæring',
      };

  String get subtitle => switch (this) {
        HmsHandbookCategory.styring =>
          'IK-system, mål, erklæringer, etikk og dokumentstyring',
        HmsHandbookCategory.miljo =>
          'Miljøhåndbok, aspekter, samsvar og miljørisiko',
        HmsHandbookCategory.risiko =>
          'ROS, SWOT, interesseparter og risikoregistre',
        HmsHandbookCategory.revisjon =>
          'Revisjonsplaner, program og Landax-eksport',
        HmsHandbookCategory.avvik => 'Rapportering av uønskede hendelser',
        HmsHandbookCategory.sja => 'Mal for sikker jobbanalyse',
        HmsHandbookCategory.beredskap =>
          'Alvorlig ulykke, brann og beredskapsplaner',
        HmsHandbookCategory.partnere =>
          'Rutiner, kontrollskjema, rammeavtale og faktura',
        HmsHandbookCategory.instrukser =>
          'Tungløft, rus, avfall, byggekort og ettersyn',
        HmsHandbookCategory.signatur => 'Bekreftelse fra ansatte',
      };

  String get iconName => switch (this) {
        HmsHandbookCategory.styring => 'policy',
        HmsHandbookCategory.miljo => 'eco',
        HmsHandbookCategory.risiko => 'risk',
        HmsHandbookCategory.revisjon => 'audit',
        HmsHandbookCategory.avvik => 'incident',
        HmsHandbookCategory.sja => 'sja',
        HmsHandbookCategory.beredskap => 'emergency',
        HmsHandbookCategory.partnere => 'partners',
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

/// MAVI Logistikk IK-system / Landax QHSE — katalog for DriftPro HMS.
abstract final class MaviHmsHandbook {
  static const docs = <HmsHandbookDoc>[
    // —— Styring ——
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
      id: 'styring_dokumentert_info',
      category: HmsHandbookCategory.styring,
      title: 'Styring av dokumentert informasjon',
      shortLabel: 'Dokumentstyring',
      vedleggNr: 'Landax',
      assetPath: 'assets/hms/handbok/styring_dokumentert_info.txt',
      summary:
          'Hvordan styrende dokumenter opprettes, godkjennes, lagres og holdes ajour.',
    ),

    // —— Miljø ——
    HmsHandbookDoc(
      id: 'handbok_miljo_14001',
      category: HmsHandbookCategory.miljo,
      title: 'Miljøhåndbok (ISO 14001)',
      shortLabel: '14001',
      vedleggNr: 'Landax',
      assetPath: 'assets/hms/handbok/handbok_miljo_14001.txt',
      summary:
          'Ledelsessystem for ytre miljø — policy, risiko, mål, beredskap og forbedring.',
    ),
    HmsHandbookDoc(
      id: 'miljoaspekter_samsvar',
      category: HmsHandbookCategory.miljo,
      title: 'Miljøaspekter og samsvar',
      shortLabel: 'Aspekter',
      vedleggNr: 'Landax',
      assetPath: 'assets/hms/handbok/miljoaspekter_samsvar.txt',
      summary: 'Kartlegging av miljøaspekter og lovkrav / samsvar.',
    ),
    HmsHandbookDoc(
      id: 'miljorapportering_2023',
      category: HmsHandbookCategory.miljo,
      title: 'Miljørapportering 2023',
      shortLabel: 'Rapport 2023',
      vedleggNr: 'Landax',
      assetPath: 'assets/hms/handbok/miljorapportering_2023.txt',
      summary: 'Utdrag fra miljørapportering for 2023.',
    ),
    HmsHandbookDoc(
      id: 'risikokartlegging_miljo',
      category: HmsHandbookCategory.miljo,
      title: 'Risikokartlegging uønsket miljøpåvirkning',
      shortLabel: 'Miljørisiko',
      vedleggNr: 'Landax',
      assetPath: 'assets/hms/handbok/risikokartlegging_miljo.txt',
      summary: 'Identifisering og vurdering av miljørisiko i driften.',
      modulePath: AppPaths.hmsRisikomatrise,
      moduleLabel: 'Åpne risikomatrise',
    ),

    // —— Risiko ——
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
      id: 'risikoidentifisering_styring',
      category: HmsHandbookCategory.risiko,
      title: 'Risikoidentifisering og risikostyring',
      shortLabel: 'Styring',
      vedleggNr: 'Landax',
      assetPath: 'assets/hms/handbok/risikoidentifisering_styring.txt',
      summary: 'Metode for å finne, vurdere og styre risiko i MAVI.',
      modulePath: AppPaths.hmsRisiko,
      moduleLabel: 'Åpne risikoanalyser',
    ),
    HmsHandbookDoc(
      id: 'risikobasert_forbedring',
      category: HmsHandbookCategory.risiko,
      title: 'Risikobasert forebyggende forbedringsarbeid',
      shortLabel: 'Forebyggende',
      vedleggNr: 'Landax',
      assetPath: 'assets/hms/handbok/risikobasert_forbedringsarbeid.txt',
      summary: 'Hvordan risiko brukes til å prioritere forbedringstiltak.',
    ),
    HmsHandbookDoc(
      id: 'risikovurdering_swot',
      category: HmsHandbookCategory.risiko,
      title: 'Risikovurdering — SWOT-analyse',
      shortLabel: 'SWOT',
      vedleggNr: 'Landax',
      assetPath: 'assets/hms/handbok/risikovurdering_swot.txt',
      summary: 'SWOT som del av risikovurdering og strategisk planlegging.',
    ),
    HmsHandbookDoc(
      id: 'interessepart_risiko',
      category: HmsHandbookCategory.risiko,
      title: 'Interessepart og risikovurdering',
      shortLabel: 'Interesseparter',
      vedleggNr: 'Landax',
      assetPath: 'assets/hms/handbok/interessepart_risikovurdering.txt',
      summary: 'Interessenter, krav/forventninger og tilhørende risiko.',
      modulePath: AppPaths.hmsRisiko,
      moduleLabel: 'Stakeholder-risiko',
    ),
    HmsHandbookDoc(
      id: 'kartlegging_interesseparter',
      category: HmsHandbookCategory.risiko,
      title: 'Kartlegging av eksterne interesseparter',
      shortLabel: 'Kartlegging',
      vedleggNr: 'Landax',
      assetPath: 'assets/hms/handbok/kartlegging_interesseparter.txt',
      summary: 'Eksterne parter med krav og forventninger til MAVI.',
    ),
    HmsHandbookDoc(
      id: 'export_risks_list',
      category: HmsHandbookCategory.risiko,
      title: 'Eksport risikoliste',
      shortLabel: 'Risikoliste',
      vedleggNr: 'Landax',
      assetPath: 'assets/hms/handbok/export_risks_list.txt',
      summary: 'Eksportert risikoliste fra Landax for oversikt og oppfølging.',
      modulePath: AppPaths.hmsRisiko,
      moduleLabel: 'Åpne risikoanalyser',
    ),
    HmsHandbookDoc(
      id: 'risk_export_landax',
      category: HmsHandbookCategory.risiko,
      title: 'Risikoregister (Landax)',
      shortLabel: 'Register',
      vedleggNr: 'Export',
      assetPath: 'assets/hms/handbok/risk_export_landax.txt',
      summary: 'Utdrag fra Risk-eksport 2025-12-23.',
    ),

    // —— Revisjon ——
    HmsHandbookDoc(
      id: 'revisjonsplan_3_aar',
      category: HmsHandbookCategory.revisjon,
      title: '3-års revisjonsplan',
      shortLabel: '3-årsplan',
      vedleggNr: 'Landax',
      assetPath: 'assets/hms/handbok/revisjonsplan_3_aar.txt',
      summary: 'Plan for intern revisjon over tre år.',
    ),
    HmsHandbookDoc(
      id: 'intern_ekstern_revisjon',
      category: HmsHandbookCategory.revisjon,
      title: 'Intern og ekstern revisjon',
      shortLabel: 'Revisjon',
      vedleggNr: 'Landax',
      assetPath: 'assets/hms/handbok/intern_ekstern_revisjon.txt',
      summary: 'Prosedyre for intern og ekstern revisjon av ledelsessystemet.',
    ),
    HmsHandbookDoc(
      id: 'internt_revisjonsprogram',
      category: HmsHandbookCategory.revisjon,
      title: 'Internt revisjonsprogram',
      shortLabel: 'Program',
      vedleggNr: 'Landax',
      assetPath: 'assets/hms/handbok/internt_revisjonsprogram.txt',
      summary: 'Program og omfang for interne revisjoner.',
    ),
    HmsHandbookDoc(
      id: 'standardmal_revisjon',
      category: HmsHandbookCategory.revisjon,
      title: 'Standardmal (audit)',
      shortLabel: 'Mal',
      vedleggNr: 'Landax',
      assetPath: 'assets/hms/handbok/standardmal_revisjon.txt',
      summary: 'Eksempel / standardmal fra Landax-audit.',
    ),
    HmsHandbookDoc(
      id: 'audit_object_export',
      category: HmsHandbookCategory.revisjon,
      title: 'Audit-objekter (eksport)',
      shortLabel: 'Objekter',
      vedleggNr: 'Export',
      assetPath: 'assets/hms/handbok/audit_object_export.txt',
      summary: 'Landax-eksport av audit-objekter.',
    ),
    HmsHandbookDoc(
      id: 'equipment_export',
      category: HmsHandbookCategory.revisjon,
      title: 'Utstyr (Landax-eksport)',
      shortLabel: 'Utstyr',
      vedleggNr: 'Export',
      assetPath: 'assets/hms/handbok/equipment_export.txt',
      summary: 'Eksport av utstyrsregister — bruk gjerne Maskiner & utstyr i DriftPro.',
      modulePath: AppPaths.hmsUtstyr,
      moduleLabel: 'Åpne utstyrsregister',
    ),
    HmsHandbookDoc(
      id: 'incident_export',
      category: HmsHandbookCategory.revisjon,
      title: 'Hendelser (Landax-eksport)',
      shortLabel: 'Hendelser',
      vedleggNr: 'Export',
      assetPath: 'assets/hms/handbok/incident_export.txt',
      summary: 'Eksport av hendelser — nye saker meldes som Avvik i DriftPro.',
      modulePath: AppPaths.hmsAvvik,
      moduleLabel: 'Registrer avvik',
    ),

    // —— Avvik / SJA ——
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

    // —— Beredskap ——
    HmsHandbookDoc(
      id: 'beredskapsplan_mavi',
      category: HmsHandbookCategory.beredskap,
      title: 'Beredskapsplan i MAVI Logistikk',
      shortLabel: 'Beredskap',
      vedleggNr: 'Landax',
      assetPath: 'assets/hms/handbok/beredskapsplan_mavi.txt',
      summary:
          'Overordnet beredskapsplan — ansvar, varsling og oppfølging ved kritiske hendelser.',
    ),
    HmsHandbookDoc(
      id: 'beredskapsplan_sjaforer',
      category: HmsHandbookCategory.beredskap,
      title: 'Beredskapsplan sjåfører og underleverandører',
      shortLabel: 'Sjåfør',
      vedleggNr: '2024',
      assetPath: 'assets/hms/handbok/beredskapsplan_sjaforer.txt',
      summary:
          'Operativ beredskap for sjåfører og underleverandører ved ulykke, brann og utslipp.',
      modulePath: AppPaths.hmsOpplaering,
      moduleLabel: 'Sjåføropplæring',
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

    // —— Partnere ——
    HmsHandbookDoc(
      id: 'rutiner_samarbeidspartnere',
      category: HmsHandbookCategory.partnere,
      title: 'Rutiner til samarbeidspartnere',
      shortLabel: 'Rutiner',
      vedleggNr: 'Landax',
      assetPath: 'assets/hms/handbok/rutiner_samarbeidspartnere.txt',
      summary: 'Krav og rutiner som gjelder for eksterne samarbeidspartnere.',
    ),
    HmsHandbookDoc(
      id: 'kontrollskjema_samarbeidspartnere',
      category: HmsHandbookCategory.partnere,
      title: 'Kontrollskjema nye samarbeidspartnere',
      shortLabel: 'Kontroll',
      vedleggNr: 'Landax',
      assetPath: 'assets/hms/handbok/kontrollskjema_samarbeidspartnere.txt',
      summary: 'Sjekkliste ved inntak av nye samarbeidspartnere.',
    ),
    HmsHandbookDoc(
      id: 'godkjenning_faktura_underleverandor',
      category: HmsHandbookCategory.partnere,
      title: 'Godkjenning av faktura fra underleverandør',
      shortLabel: 'Faktura',
      vedleggNr: 'Landax',
      assetPath: 'assets/hms/handbok/godkjenning_faktura_underleverandor.txt',
      summary: 'Rutine for kontroll og godkjenning av underleverandørfakturaer.',
    ),
    HmsHandbookDoc(
      id: 'rammeavtale_mal',
      category: HmsHandbookCategory.partnere,
      title: 'Rammeavtale — mal',
      shortLabel: 'Rammeavtale',
      vedleggNr: 'Landax',
      assetPath: 'assets/hms/handbok/rammeavtale_mal.txt',
      summary: 'Mal for rammeavtale om kjøp av transporttjenester.',
    ),
    HmsHandbookDoc(
      id: 'vedlegg_3_mal',
      category: HmsHandbookCategory.partnere,
      title: 'Vedlegg 3 — databehandleravtale (mal)',
      shortLabel: 'Vedlegg 3',
      vedleggNr: 'Landax',
      assetPath: 'assets/hms/handbok/vedlegg_3_mal.txt',
      summary: 'Mal for avtale om databehandling mellom MAVI og leverandør.',
    ),

    // —— Instrukser ——
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
      id: 'ettersyn_trucker',
      category: HmsHandbookCategory.instrukser,
      title: 'Daglig og ukentlig ettersyn av trucker og sniler',
      shortLabel: 'Ettersyn',
      vedleggNr: 'Landax',
      assetPath: 'assets/hms/handbok/ettersyn_trucker_sniler.txt',
      summary: 'Sjekkliste for daglig/ukentlig kontroll av trucker og sniler.',
      modulePath: AppPaths.hmsUtstyr,
      moduleLabel: 'Maskiner & utstyr',
    ),

    // —— Signatur ——
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
