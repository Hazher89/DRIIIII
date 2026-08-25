import '../../constants/vehicle_rental_agreement.dart';
import '../../routing/app_paths.dart';
import '../hms/sop_training_models.dart';
import '../hms/sop_training_service.dart';
import '../../../screens/more/driftpro_platform_catalog.dart';

enum KnowledgeSourceKind { sop, rental, help }

/// Én indekserbar kunnskapsbit for DriftPro-assistenten.
class KnowledgeChunk {
  const KnowledgeChunk({
    required this.id,
    required this.source,
    required this.title,
    required this.body,
    this.routePath,
    this.tags = const [],
  });

  final String id;
  final KnowledgeSourceKind source;
  final String title;
  final String body;
  final String? routePath;
  final List<String> tags;

  String get searchableText => '$title $body ${tags.join(' ')}';

  String get sourceLabel {
    switch (source) {
      case KnowledgeSourceKind.sop:
        return 'SOP / opplæring';
      case KnowledgeSourceKind.rental:
        return 'Bilutleie';
      case KnowledgeSourceKind.help:
        return 'Hjelp & støtte';
    }
  }
}

/// Bygger kunnskapsindeks fra SOP, bilutleie og hjelpetekster.
class AssistantCorpus {
  AssistantCorpus._();

  static Future<List<KnowledgeChunk>> build() async {
    final chunks = <KnowledgeChunk>[
      ..._rentalChunks(),
      ..._helpChunks(),
      ..._catalogChunks(),
    ];

    try {
      final doc = await SopTrainingService.instance.load();
      chunks.addAll(_sopChunks(doc));
    } catch (_) {
      // SOP-asset kan mangle lokalt — resten av corpus fungerer fortsatt.
    }

    return chunks;
  }

  static List<KnowledgeChunk> _sopChunks(SopTrainingDocument doc) {
    return doc.entries.map((e) {
      final body = e.answer.trim().isEmpty ? e.body : e.answer;
      return KnowledgeChunk(
        id: 'sop:${e.id}',
        source: KnowledgeSourceKind.sop,
        title: e.title.isEmpty ? (e.subsection.isEmpty ? e.section : e.subsection) : e.title,
        body: body,
        routePath: AppPaths.hmsOpplaering,
        tags: [
          ...e.tags,
          if (e.system != null) e.system!,
          e.section,
          e.subsection,
          e.kind.name,
        ],
      );
    }).toList();
  }

  static List<KnowledgeChunk> _rentalChunks() {
    final agreement = VehicleRentalAgreement.body(
      registrationNumber: 'EKSEMPEL',
      vehicleMake: 'EKSEMPEL',
    );

    return [
      KnowledgeChunk(
        id: 'rental:approvers',
        source: KnowledgeSourceKind.rental,
        title: 'Godkjenningsrekkefølge bilutleie',
        body: VehicleRentalAgreement.approverPriorityText,
        routePath: AppPaths.partners,
        tags: const ['bilutleie', 'godkjenning', 'jassy', 'herish', 'julie', 'karwan', 'retur'],
      ),
      KnowledgeChunk(
        id: 'rental:handout',
        source: KnowledgeSourceKind.rental,
        title: 'Sjekkliste ved utlevering av bil',
        body: VehicleRentalAgreement.handoutChecklist.map((e) => '• $e').join('\n'),
        routePath: AppPaths.partners,
        tags: const ['bilutleie', 'utlevering', 'bilder', 'drivstoff', 'kilometer', 'sjekkliste'],
      ),
      KnowledgeChunk(
        id: 'rental:return',
        source: KnowledgeSourceKind.rental,
        title: 'Sjekkliste ved retur av bil',
        body: VehicleRentalAgreement.returnChecklist.map((e) => '• $e').join('\n'),
        routePath: AppPaths.partners,
        tags: const ['bilutleie', 'retur', 'bilder', 'skader', 'sjekkliste'],
      ),
      KnowledgeChunk(
        id: 'rental:agreement',
        source: KnowledgeSourceKind.rental,
        title: 'Leieavtale for kjøretøy — regler',
        body: agreement,
        routePath: AppPaths.partners,
        tags: const [
          'bilutleie',
          'leieavtale',
          'pris',
          'forsikring',
          'egenandel',
          'bøter',
          'drivstoff',
          'bompenger',
        ],
      ),
      const KnowledgeChunk(
        id: 'rental:price',
        source: KnowledgeSourceKind.rental,
        title: 'Pris og gebyrer for bilutleie',
        body:
            'Leiepris er 1.000,- pr påbegynte dag. Drivstoff etterfylles til samme nivå '
            'som ved utlevering; manglende etterfylling gir administrasjonsgebyr 500,- '
            'ekskl. drivstoff. Bompenger, vask og service ved lang leie er inkludert. '
            'Fakturering skjer ved motregning på oppsummering.',
        routePath: AppPaths.partners,
        tags: ['pris', 'gebyr', 'drivstoff', 'bompenger', 'faktura', 'bilutleie'],
      ),
    ];
  }

  static List<KnowledgeChunk> _helpChunks() {
    return [
      const KnowledgeChunk(
        id: 'help:start',
        source: KnowledgeSourceKind.help,
        title: 'Kom i gang med DriftPro',
        body:
            'DriftPro er en skybasert plattform for hele bedriften. '
            'Du logger inn med ansattnummer og passord (eller partner-brukernavn). '
            'Konto opprettes av administrator — det er ikke offentlig selvregistrering. '
            'Dashbord gir daglig oversikt. Fravær: søk ferie og egenmelding — leder godkjenner. '
            'HMS: meld avvik, fyll SJA og se vernerunder. Mer: personalmappe, profil og hjelp.',
        routePath: AppPaths.moreHjelp,
        tags: ['innlogging', 'start', 'ansattnummer', 'passord', 'onboarding'],
      ),
      KnowledgeChunk(
        id: 'help:absence',
        source: KnowledgeSourceKind.help,
        title: 'Fravær og ferie',
        body:
            'Fraværsmodulen dekker søknad til godkjenning. Leder ser ventende saker under Godkjenn. '
            'Typer: ferie, egenmelding, sykt barn, permisjon og sykmelding. '
            'Saldo og kvoter per ansatt og år. Dobbel kalender for ferie og fravær. '
            'Røde dager og Lovdata-regelhjelp er innebygd. '
            'Superadmin kan registrere ferie direkte uten godkjenningskø.',
        routePath: AppPaths.moreHjelp,
        tags: ['fravær', 'ferie', 'egenmelding', 'permisjon', 'sykmelding', 'kvote'],
      ),
      KnowledgeChunk(
        id: 'help:hms',
        source: KnowledgeSourceKind.help,
        title: 'HMS — kvalitet og sikkerhet',
        body:
            'HMS-huben samler avvik (bilder, GPS, alvorlighet), risikoanalyse (ROS 5×5), '
            'SJA med maler og signatur, vernerunder, maskiner/utstyr, kompetansematrise, '
            'DMS for håndbok, og anonym varsling. Et avvik kan kobles til risikoanalyse.',
        routePath: AppPaths.moreHjelp,
        tags: ['hms', 'avvik', 'sja', 'vernerunde', 'risiko', 'kompetanse', 'dms'],
      ),
      KnowledgeChunk(
        id: 'help:partners',
        source: KnowledgeSourceKind.help,
        title: 'Partnere, ruter og logistikk',
        body:
            'Partnermodulen dekker Brreg, kjøretøy, EU-kontroll, rute-PDF, publisering, '
            'sjåfør- og eierportal, SMS fra rute-PDF, bilutleie og inspeksjon. '
            'Ruter kan komme fra manuell opplasting, mass auto, AUTO MASS eller '
            'SAP e-post innboks (ruter@driftpro.no).',
        routePath: AppPaths.moreHjelp,
        tags: ['partner', 'rute', 'sap', 'sms', 'bilutleie', 'brreg', 'sjåfør'],
      ),
      KnowledgeChunk(
        id: 'help:password',
        source: KnowledgeSourceKind.help,
        title: 'Bytt passord',
        body:
            'Ansatte logger inn med ansattnummer. Standardpassord ved ny bruker er 000000. '
            'Du kan bytte passord selv under Mer → Min profil → Bytt passord. '
            'Passordet må være minst 6 tegn.',
        routePath: AppPaths.moreProfil,
        tags: ['passord', 'innlogging', 'profil', 'sikkerhet', '000000'],
      ),
      KnowledgeChunk(
        id: 'help:support',
        source: KnowledgeSourceKind.help,
        title: 'Kontakt support',
        body:
            'Har du spørsmål om innlogging, ruter, HMS, fravær eller tilganger? '
            'Send e-post til hazher@mavilogistikk.no. '
            'Support-side: https://hazher.no/DRIFTPRO/Support/.',
        routePath: AppPaths.moreHjelp,
        tags: ['support', 'hjelp', 'kontakt', 'e-post'],
      ),
    ];
  }

  static List<KnowledgeChunk> _catalogChunks() {
    final out = <KnowledgeChunk>[];
    var i = 0;
    for (final group in DriftProPlatformCatalog.groups) {
      for (final f in group.features) {
        i++;
        final highlights = f.highlights.map((h) => '• $h').join('\n');
        out.add(
          KnowledgeChunk(
            id: 'catalog:$i',
            source: KnowledgeSourceKind.help,
            title: '${group.title}: ${f.title}',
            body: [
              f.description,
              if (highlights.isNotEmpty) highlights,
            ].join('\n'),
            routePath: AppPaths.moreOm,
            tags: [group.title, f.title, ...f.highlights],
          ),
        );
      }
    }
    return out;
  }
}
