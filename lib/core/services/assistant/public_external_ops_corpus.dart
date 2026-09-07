import 'assistant_corpus.dart';

/// Kunnskap for offentlig chat — målgruppe: CCC og butikk (Elkjøp).
/// Forteller hva DU skal gjøre i booking/ordre — aldri «kontakt CCC/butikk».
/// Ingen interne MAVI-systemdetaljer.
abstract final class PublicExternalOpsCorpus {
  static List<KnowledgeChunk> chunks() => [
        _overview(),
        _terms(),
        _rebookScan(),
        _earlierDelivery(),
        _timeWindow(),
        _statusToday(),
        _montageFollowUp(),
        _fourPerson(),
        _extraService(),
        _changeCustomerInfo(),
        _deliveryConfirm(),
        _curbsideVsSite(),
        _storePickupMissed(),
        _cancelOrder(),
        _returnPickup(),
        _orderNotes(),
      ];

  static String compactServerCorpus() {
    final buf = StringBuffer();
    for (final c in chunks()) {
      buf.writeln('## ${c.title}');
      buf.writeln(c.body);
      buf.writeln();
    }
    return buf.toString();
  }

  static KnowledgeChunk _overview() => const KnowledgeChunk(
        id: 'ext.overview',
        source: KnowledgeSourceKind.publicOps,
        title: 'Hjelp for CCC og butikk',
        tags: [
          'levering',
          'montering',
          'booking',
          'ombooking',
          'ccc',
          'butikk',
          'hjelp',
        ],
        body: '''
Du snakker med CCC eller butikk. Gi konkrete handlinger de kan gjøre selv:
ombooking, endre kundedata, sette opp SA, endre tjenestetype, kansellere, notater på ordre.

Ikke si «kontakt CCC» eller «kontakt butikken» — brukeren er allerede der.
Ikke avslør interne MAVI-systemer eller hub-rutiner.
Forklar begrensninger tydelig (f.eks. hva leverandør ikke kan gjøre) og hva som er riktig grep hos deg.
''',
      );

  static KnowledgeChunk _terms() => const KnowledgeChunk(
        id: 'ext.terms',
        source: KnowledgeSourceKind.publicOps,
        title: 'Vanlige begreper',
        tags: [
          'ccc',
          'ndc',
          'curbside',
          'deliverysite',
          'sa',
          'force',
          'pick pack',
          'begrep',
        ],
        body: '''
NDC: sentrallager varer ofte kommer fra før levering.
Curbside: levering til fortauskant / første dør.
Deliverysite: levering inn til anvist plass.
SA: standalone service — egen serviceordre uten ny varelevering.
Force tid: spesialtid utenom matrise — bare når varen er klar og det er avtalt.
Pick & pack: butikk klargjør vare for henting (fremme + skannelapp). Uten dette blir ikke henting planlagt riktig.
''',
      );

  static KnowledgeChunk _rebookScan() => const KnowledgeChunk(
        id: 'ext.rebook_scan',
        source: KnowledgeSourceKind.publicOps,
        title: 'Omboking før varen er klar',
        tags: [
          'ombook',
          'omboking',
          'skanne',
          'hub',
          'booke om',
          'innskann',
        ],
        body: '''
Varen kan ikke bookes om før den faktisk er ankommet/returnert og registrert hos leverandør.
Book ikke om «på forskudd». Vent til varen er klar, deretter ombook i deres system.
''',
      );

  static KnowledgeChunk _earlierDelivery() => const KnowledgeChunk(
        id: 'ext.earlier',
        source: KnowledgeSourceKind.publicOps,
        title: 'Tidligere leveringsdato',
        tags: [
          'tidligere',
          'første leveringsdato',
          'matrise',
          'force',
          'raskere',
        ],
        body: '''
Hold matrise-/booket dato som standard — særlig hvis varen ikke har ankommet.
Unntak: flere feilleveranser på leverandørsiden (f.eks. «rakk ikke»). Da kan du forespørre tidligere tid, men varen må være klar først. Bruk force-tid kun når det er avtalt og varen er klar.
''',
      );

  static KnowledgeChunk _timeWindow() => const KnowledgeChunk(
        id: 'ext.time_window',
        source: KnowledgeSourceKind.publicOps,
        title: 'Spesifikt tidspunkt i vinduet',
        tags: [
          'tidsrom',
          'vindu',
          'etter kl',
          'før kl',
          '17-22',
          'bomtur',
          'tilgjengelig',
        ],
        body: '''
Levering planlegges etter booket tidsvindu. Spesifikke klokkeslett inni vinduet (f.eks. «etter 19») kan ikke loves.
Hvis kunden ikke kan hele vinduet: book om til en dag der hele tidsrommet passer.
Ved flere tidligere bomturer på leverandørsiden: merk behov for hensyn ved ombooking/planlegging.
''',
      );

  static KnowledgeChunk _statusToday() => const KnowledgeChunk(
        id: 'ext.status_today',
        source: KnowledgeSourceKind.publicOps,
        title: 'Status — kommer leveringen i dag?',
        tags: [
          'i dag',
          'status',
          'forsinket',
          'passert',
          'kommer den',
          'på rute',
        ],
        body: '''
Chatten har ikke live ordrestatus. Sjekk status i deres egne ordresystemer med ordrenummer.
Hvis leveringen er ute: følg opp slik at kunden får beskjed / sjåfør kontaktes via vanlig kanal.
''',
      );

  static KnowledgeChunk _montageFollowUp() => const KnowledgeChunk(
        id: 'ext.montage_followup',
        source: KnowledgeSourceKind.publicOps,
        title: 'Klage på montering / ny service',
        tags: [
          'klage',
          'montering',
          'sa',
          'standalone',
          'vannlekkasje',
          'oppfølging',
        ],
        body: '''
Sett opp en standalone service (SA) til kunden for ny gjennomgang.
Ved vannlekkasje eller skaderisiko: prioriter — kan behandles mer akutt enn vanlig matrise.
''',
      );

  static KnowledgeChunk _fourPerson() => const KnowledgeChunk(
        id: 'ext.four_person',
        source: KnowledgeSourceKind.publicOps,
        title: 'Behov for fire personer',
        tags: [
          'fire mann',
          'fire personer',
          'bære',
          'tungt',
          'deliveryunp',
          'installfridge',
        ],
        body: '''
Allerede levert: opprett SA (f.eks. installfridge / deliveryunp) og oppgi ønsket dato.
Ikke levert: book om og merk tydelig at fire personer trengs + ny tid.
Oppdaget under levering: ekstra mannskap samme dag er ikke alltid mulig — planlegg på nytt med SA/omboking.
Merk behovet tidlig på ordren.
''',
      );

  static KnowledgeChunk _extraService() => const KnowledgeChunk(
        id: 'ext.extra_service',
        source: KnowledgeSourceKind.publicOps,
        title: 'Ekstra / glemt tjeneste',
        tags: [
          'ekstra tjeneste',
          'glemt tjeneste',
          'legge til',
          'deliverysite',
          'payment',
        ],
        body: '''
I dag/i morgen + vanlig tjeneste + deliverysite: tjenesten kan ofte legges til under levering (kunden får betalingslenke etterpå). Avklar før levering.
Lenger frem: legg opp SA på samme dato/tid med samme kundedata.
''',
      );

  static KnowledgeChunk _changeCustomerInfo() => const KnowledgeChunk(
        id: 'ext.customer_info',
        source: KnowledgeSourceKind.publicOps,
        title: 'Endre adresse, telefon eller navn',
        tags: [
          'adresse',
          'telefon',
          'kundenavn',
          'endre kunde',
          'kundeinformasjon',
        ],
        body: '''
Du endrer adresse/telefon/navn selv i ordresystemet. Leverandør kan ikke gjøre det.
Som oftest må leveringen bookes om for at endringen skal gjelde.
Samme dag / i morgen: du kan i tillegg sikre at korrekt tlf følger med til sjåfør, men permanent endring må inn i ordren.
''',
      );

  static KnowledgeChunk _deliveryConfirm() => const KnowledgeChunk(
        id: 'ext.utlevere',
        source: KnowledgeSourceKind.publicOps,
        title: 'Levering ikke registrert som levert',
        tags: [
          'utlevere',
          'ikke skannet',
          'pda',
          'levert status',
          'teknisk feil',
        ],
        body: '''
Registrering hos sjåfør kan feile selv om leveringen er gjort.
Fra i går: vent normalt til neste arbeidsdag for oppdatering.
Eldre: følg opp status/utlevering i deres system / med leverandør med ordrenummer.
''',
      );

  static KnowledgeChunk _curbsideVsSite() => const KnowledgeChunk(
        id: 'ext.curbside_site',
        source: KnowledgeSourceKind.publicOps,
        title: 'Curbside vs deliverysite',
        tags: [
          'curbside',
          'deliverysite',
          'fortauskant',
          'anvist plass',
          'endre tjeneste',
        ],
        body: '''
Du endrer selv fra curbside til deliverysite i ordresystemet. Leverandør kan ikke bytte tjenestetype.
Gjør endringen før leveringsdagen.
''',
      );

  static KnowledgeChunk _storePickupMissed() => const KnowledgeChunk(
        id: 'ext.store_pickup',
        source: KnowledgeSourceKind.publicOps,
        title: 'Vare ikke hentet fra butikk',
        tags: [
          'butikk',
          'hentet',
          'pick pack',
          'pickup',
          'ndc',
          'klargjort',
        ],
        body: '''
Hvis varen ikke ble hentet fra butikk: den kan normalt ikke leveres til oppsatt tid.
Book om med både henting og levering.
Sørg for at pick & pack er gjort i tide — uten klargjøring blir ikke henting planlagt riktig.
''',
      );

  static KnowledgeChunk _cancelOrder() => const KnowledgeChunk(
        id: 'ext.cancel',
        source: KnowledgeSourceKind.publicOps,
        title: 'Kansellere levering',
        tags: [
          'kansellere',
          'avlyse',
          'stoppe levering',
          'ikke utføre',
        ],
        body: '''
Du kansellerer ordren selv i Elkjøp-systemet. Leverandør kan ikke kansellere for deg.
Sørg samtidig for at leveringen ikke blir kjørt (stopp/merk ordren slik at den ikke planlegges ut).
''',
      );

  static KnowledgeChunk _returnPickup() => const KnowledgeChunk(
        id: 'ext.return_pickup',
        source: KnowledgeSourceKind.publicOps,
        title: 'Returhenting / return store',
        tags: [
          'retur',
          'returnstore',
          'henting',
          'endre dato',
        ],
        body: '''
Returhentingsdato kan ofte justeres. Send forespørsel med ordrenummer og ønsket dato til leverandør/planlegging.
''',
      );

  static KnowledgeChunk _orderNotes() => const KnowledgeChunk(
        id: 'ext.notes',
        source: KnowledgeSourceKind.publicOps,
        title: 'Info til sjåfør på ordren',
        tags: [
          'beskjed',
          'note',
          'informasjon',
          'kode',
          'port',
          'ring først',
        ],
        body: '''
Legg viktige notater (portkode, ring først, adkomst) direkte på ordren slik at det følger sjåføren.
I dag: sørg for at beskjeden også når frem raskt.
I morgen eller senere: legg inn notatet i god tid.
''',
      );
}
