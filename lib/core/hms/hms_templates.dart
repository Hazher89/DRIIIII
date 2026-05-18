/// HMS-maler (Landax-inspirert) — klare til utfylling og lagring i Supabase.
enum HmsModuleKind { risk, sja, safetyRound }

class HmsRiskTemplate {
  final String id;
  final String title;
  final String area;
  final String description;
  final int probability;
  final int consequence;
  final String existingMeasures;
  final String proposedMeasures;

  const HmsRiskTemplate({
    required this.id,
    required this.title,
    required this.area,
    required this.description,
    this.probability = 3,
    this.consequence = 3,
    this.existingMeasures = '',
    this.proposedMeasures = '',
  });
}

class HmsSjaTemplate {
  final String id;
  final String title;
  final String workDescription;
  final String location;
  final List<String> ppe;
  final List<Map<String, dynamic>> hazards;
  final List<Map<String, dynamic>> measures;

  const HmsSjaTemplate({
    required this.id,
    required this.title,
    required this.workDescription,
    this.location = '',
    this.ppe = const [],
    this.hazards = const [],
    this.measures = const [],
  });
}

class HmsSafetyRoundTemplate {
  final String id;
  final String title;
  final List<Map<String, dynamic>> checklist;

  const HmsSafetyRoundTemplate({
    required this.id,
    required this.title,
    required this.checklist,
  });
}

class HmsTemplates {
  HmsTemplates._();

  static const riskTemplates = [
    HmsRiskTemplate(
      id: 'fall_hoyde',
      title: 'Arbeid i høyden',
      area: 'Bygg / stillas',
      description: 'Fall fra stillas, lift eller tak',
      probability: 3,
      consequence: 5,
      existingMeasures: 'Sikring, autorisert stillas, inspeksjon',
      proposedMeasures: 'Fallsikring, opplæring, daglig sjekk av stillas',
    ),
    HmsRiskTemplate(
      id: 'kjemikalier',
      title: 'Håndtering av kjemikalier',
      area: 'Lager / verksted',
      description: 'Eksponering ved søl eller feil dosering',
      probability: 2,
      consequence: 4,
      existingMeasures: 'SDS tilgjengelig, verneutstyr',
      proposedMeasures: 'Spillkit, årlig opplæring, merking',
    ),
    HmsRiskTemplate(
      id: 'trafikk',
      title: 'Kjøring i anleggsområde',
      area: 'Anlegg / gate',
      description: 'Påkjørsel av person eller utstyr',
      probability: 3,
      consequence: 4,
      existingMeasures: 'Skilting, refleksvest',
      proposedMeasures: 'Kjøreplan, fartsgrense, avsperring',
    ),
    HmsRiskTemplate(
      id: 'maskin',
      title: 'Bruk av maskin/verktøy',
      area: 'Verksted',
      description: 'Klemskade eller prosjektil',
      probability: 3,
      consequence: 3,
      existingMeasures: 'Verneutstyr, sperrer',
      proposedMeasures: 'Sjekkliste før bruk, autorisasjon',
    ),
  ];

  static const sjaTemplates = [
    HmsSjaTemplate(
      id: 'sja_hoyde',
      title: 'SJA – Arbeid i høyden',
      workDescription: 'Montering/demontering med fallsikring',
      location: 'Byggplass',
      ppe: ['Hjelm', 'Fallsikring', 'Verneskog', 'Synlighetsbekledning'],
      hazards: [
        {'title': 'Fall', 'risk': 'Høy', 'control': 'Sikringspunkt + dobbel sikring'},
        {'title': 'Fallende gjenstander', 'risk': 'Middels', 'control': 'Sperret sone under arbeid'},
      ],
      measures: [
        {'action': 'Inspeksjon av stillas før start', 'responsible': 'Leder'},
        {'action': 'Tool box talk med team', 'responsible': 'Utførende'},
      ],
    ),
    HmsSjaTemplate(
      id: 'sja_graving',
      title: 'SJA – Graving / gravearbeid',
      workDescription: 'Graving med maskin og håndgraving',
      location: 'Anlegg',
      ppe: ['Hjelm', 'Verneskog', 'Synlighetsbekledning'],
      hazards: [
        {'title': 'Kollaps av grøft', 'risk': 'Høy', 'control': 'Grøftesikring'},
        {'title': 'Treff i kabler', 'risk': 'Kritisk', 'control': 'GRAAK / påvisning'},
      ],
      measures: [
        {'action': 'Innhente ledningskart', 'responsible': 'Prosjektleder'},
      ],
    ),
  ];

  /// Legacy – bruk [SafetyRoundTemplates] i vernerunde-flyten.
  static List<HmsSafetyRoundTemplate> get safetyRoundTemplates => [
        HmsSafetyRoundTemplate(
          id: 'vr_legacy',
          title: 'Enkel mal (eldre)',
          checklist: [
            {'item': 'Orden og ryddighet', 'ok': null, 'comment': ''},
            {'item': 'Nødutganger frie', 'ok': null, 'comment': ''},
          ],
        ),
      ];
}
