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
    HmsRiskTemplate(
      id: 'truck_lager',
      title: 'Truckkjøring i lagerhall',
      area: 'Lager',
      description: 'Kollisjon med gående, tipputstyr eller reoler',
      probability: 4,
      consequence: 4,
      existingMeasures: 'Truckførerbevis, fartsgrense, speil',
      proposedMeasures: 'Gående-soner, blått lys, kollektivsikring',
    ),
    HmsRiskTemplate(
      id: 'pall_stabling',
      title: 'Stabling av paller',
      area: 'Lager',
      description: 'Veltende pall eller fallende gods',
      probability: 3,
      consequence: 4,
      existingMeasures: 'Max høyde-skilt, shrink',
      proposedMeasures: 'Inspeksjon av paller, opplæring i stabling',
    ),
    HmsRiskTemplate(
      id: 'lossing_container',
      title: 'Lossing av container',
      area: 'Terminal / logistikk',
      description: 'Fallende gods ved åpning, klemskade',
      probability: 3,
      consequence: 5,
      existingMeasures: 'Lossingssone, verneutstyr',
      proposedMeasures: 'Sikring av dør, to-person prinsipp',
    ),
    HmsRiskTemplate(
      id: 'manuelt_løft',
      title: 'Manuelt løft på lager',
      area: 'Lager',
      description: 'Ryggskade ved gjentatte løft',
      probability: 4,
      consequence: 3,
      existingMeasures: 'Løfteveiledning',
      proposedMeasures: 'Hjelpemidler, roterende oppgaver',
    ),
    HmsRiskTemplate(
      id: 'last_sikring',
      title: 'Lastsikring på bil',
      area: 'Transport / logistikk',
      description: 'Last som forskyver seg under kjøring',
      probability: 3,
      consequence: 5,
      existingMeasures: 'Stropper, surreregler',
      proposedMeasures: 'Sjekkliste før avgang, egenkontroll',
    ),
    HmsRiskTemplate(
      id: 'natt_kjoring',
      title: 'Nattkjøring / distribusjon',
      area: 'Logistikk',
      description: 'Tretthet, dårlig sikt, vilt',
      probability: 3,
      consequence: 4,
      existingMeasures: 'Kjøre- og hviletid',
      proposedMeasures: 'Ruteplan, hvilepauser, varsling ved forsinkelse',
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
    HmsSjaTemplate(
      id: 'sja_truck_lager',
      title: 'SJA – Truckkjøring i lager',
      workDescription: 'Inn- og utkjøring av gods med motortruck',
      location: 'Lagerhall',
      ppe: ['Verneskog', 'Synlighetsbekledning', 'Hjelm'],
      hazards: [
        {'title': 'Påkjørsel av gående', 'control': 'Blått lys, horn ved kryss, gående-soner'},
        {'title': 'Velt av last', 'control': 'Kontroll av mast og lastfeste'},
      ],
      measures: [
        {'action': 'Sjekk truck før bruk', 'responsible': 'Fører'},
        {'action': 'Avsperre aktiv sone', 'responsible': 'Leder'},
      ],
    ),
    HmsSjaTemplate(
      id: 'sja_lossing',
      title: 'SJA – Lossing av container/trailer',
      workDescription: 'Åpning og lossing av container eller trailer',
      location: 'Terminal',
      ppe: ['Hjelm', 'Verneskog', 'Hansker', 'Synlighetsbekledning'],
      hazards: [
        {'title': 'Fallende gods', 'control': 'Stå bak dør, bruk surring'},
        {'title': 'Klemskade', 'control': 'Hold avstand til dør og last'},
      ],
      measures: [
        {'action': 'To-person ved åpning', 'responsible': 'Losser'},
      ],
    ),
    HmsSjaTemplate(
      id: 'sja_høyde_lager',
      title: 'SJA – Arbeid i høyden (reol/stige)',
      workDescription: 'Plukk fra høy reol eller bruk av stige i lager',
      location: 'Lager',
      ppe: ['Hjelm', 'Fallsikring', 'Verneskog'],
      hazards: [
        {'title': 'Fall fra stige/reol', 'control': 'Sikre stige, bruk fallsikring over 2m'},
        {'title': 'Fallende gjenstander', 'control': 'Sperre sone under arbeid'},
      ],
      measures: [
        {'action': 'Visuell sjekk av stige/reol', 'responsible': 'Utførende'},
      ],
    ),
    HmsSjaTemplate(
      id: 'sja_kjøling',
      title: 'SJA – Arbeid i kjølerom/frys',
      workDescription: 'Plukk og kontroll i kjøle- eller fryserom',
      location: 'Lager – kjøle/frys',
      ppe: ['Vinterklær', 'Hansker', 'Verneskog'],
      hazards: [
        {'title': 'Kuldeskade', 'control': 'Maks tid i rom, varmepause'},
        {'title': 'Glatt gulv', 'control': 'Rengjøring, riktig fottøy'},
      ],
      measures: [
        {'action': 'Timer for oppholdstid', 'responsible': 'Leder'},
      ],
    ),
    HmsSjaTemplate(
      id: 'sja_lasting',
      title: 'SJA – Lasting og sikring av bil',
      workDescription: 'Lasting av pall/gods og surring før avgang',
      location: 'Rampe / terminal',
      ppe: ['Verneskog', 'Hansker', 'Synlighetsbekledning'],
      hazards: [
        {'title': 'Utslitt last', 'control': 'Surreregler, strekkfilm, stropper'},
        {'title': 'Klemskade ved last', 'control': 'Kommunikasjon med sjåfør'},
      ],
      measures: [
        {'action': 'Egenkontroll-sjekkliste', 'responsible': 'Losser'},
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
