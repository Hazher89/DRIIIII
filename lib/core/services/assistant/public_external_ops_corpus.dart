import 'assistant_corpus.dart';

/// Ekstern kunnskapsbase for offentlig chat (/montering).
///
/// Bygd ut fra interne FAQ-er, men omskrevet til hva butikk/CCC/kunde
/// skal gjøre — uten å avsløre MAVI sine interne systemer, filer, roller
/// eller arbeidsinstrukser.
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
        title: 'Hjelp til levering og montering',
        tags: [
          'levering',
          'montering',
          'booking',
          'ombooking',
          'ccc',
          'butikk',
          'kunde',
          'hjelp',
        ],
        body: '''
Denne chatten hjelper kunder, butikk og CCC med hva DE skal gjøre rundt levering og montering.

Vi forklarer:
- Hva du selv må endre i booking/system (adresse, tjenestetype, kansellering)
- Når du må kontakte CCC/butikk
- Hva som er realistisk å forvente ved leveringsvindu, ombooking og ekstra tjenester
- Hva monteringstjenester inkluderer hos kunden

Vi deler ikke interne MAVI-rutiner, systemnavn, interne filer, interne roller eller detaljer om hvordan hub planlegger.

Booking, pris og ordrestatus: alltid via butikken der kjøpet ble gjort, eller Elkjøp CCC.
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
CCC: Elkjøps kundesenter — der endringer i ordre, booking og tjenester normalt gjøres.
NDC: Elkjøps sentrallager (varer kommer ofte derfra før levering).
Curbside: levering til fortauskant / første dør.
Deliverysite: levering inn til anvist plass hos kunden.
SA (standalone service): egen serviceordre (f.eks. montering/oppfølging) uten ny varelevering.
Force tid: spesialgodkjent leveringstid utenom vanlig matrise — må avtales via CCC, og varen må være klar for levering.
Pick & pack: butikken klargjør varen for henting (fremme + skannelapp). Uten dette blir ikke henting planlagt riktig.
''',
      );

  static KnowledgeChunk _rebookScan() => const KnowledgeChunk(
        id: 'ext.rebook_scan',
        source: KnowledgeSourceKind.publicOps,
        title: 'Omboking når varen ikke er skannet inn',
        tags: [
          'ombook',
          'omboking',
          'skanne',
          'hub',
          'booke om',
          'innskann',
        ],
        body: '''
Spørsmål du ofte får: «Kan dere skanne inn varen på hub så vi kan booke om?»

Svar til ekstern: Varen kan først behandles for ombooking når den faktisk er hos oss / returnert og registrert.
Be om at ombooking skjer etter at varen er returnert/ankommet til avtalt tid — ikke før.
Du (CCC/butikk) booker om i deres system når varen er klar.
''',
      );

  static KnowledgeChunk _earlierDelivery() => const KnowledgeChunk(
        id: 'ext.earlier',
        source: KnowledgeSourceKind.publicOps,
        title: 'Ønske om tidligere leveringsdato',
        tags: [
          'tidligere',
          'første leveringsdato',
          'matrise',
          'force',
          'raskere',
        ],
        body: '''
Utgangspunkt: hold dere til datoen som er satt i leveringsmatrisen / bookingen — særlig hvis varen ikke har ankommet ennå.

Unntak: hvis leveringen har feilet flere ganger på grunn av transportør/leverandør (f.eks. «rakk ikke»), kan CCC be om tidligere tidspunkt. Da må varen allerede være klar for levering, og ny tid må avtales via CCC.
''',
      );

  static KnowledgeChunk _timeWindow() => const KnowledgeChunk(
        id: 'ext.time_window',
        source: KnowledgeSourceKind.publicOps,
        title: 'Ønske om spesifikt tidspunkt i vinduet',
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
Leveranser planlegges etter booket tidsvindu. Vi kan ikke garantere f.eks. «først etter kl. 19» innenfor et vindu 17–22.

Hvis kunden ikke kan være tilgjengelig hele vinduet, er beste løsning å booke om til en dag der kunden kan være hjemme i hele tidsrommet (via CCC/butikk).

Har det vært flere bomturer som skyldes leverandør tidligere, kan CCC be om ekstra hensyn ved ny planlegging.
''',
      );

  static KnowledgeChunk _statusToday() => const KnowledgeChunk(
        id: 'ext.status_today',
        source: KnowledgeSourceKind.publicOps,
        title: 'Blir leveringen gjennomført i dag?',
        tags: [
          'i dag',
          'status',
          'forsinket',
          'passert',
          'kommer den',
          'på rute',
        ],
        body: '''
Hvis avtalt tid er passert og kunden lurer på om leveringen kommer i dag:
Be kunden/butikk kontakte CCC med ordrenummer.
CCC kan sjekke status og eventuelt be sjåfør kontakte kunden hvis leveringen er på vei.

Denne chatten viser ikke live ordrestatus.
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
Ved klage på montering eller behov for ny gjennomgang: be CCC sette opp en standalone service (SA) til kunden.

Ved vannlekkasje eller fare for skade i hjemmet: prioriter via CCC så raskt som mulig — dette kan behandles mer akutt enn vanlig matrise.
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
Hvis produktet allerede er levert hos kunden: be CCC opprette en SA (f.eks. installfridge / deliveryunp) som grunnlag for å planlegge fire personer, og oppgi ønsket dato.

Hvis varen kan bookes om: book levering på nytt og merk tydelig at det trengs fire personer + ny tid.

Hvis det først oppdages under levering: sjåfør må ofte fullføre/avbryte etter situasjonen. Oppfølging og ny planlegging går via CCC — ikke forvent at ekstra mannskap alltid er tilgjengelig på kort varsel samme dag.
''',
      );

  static KnowledgeChunk _extraService() => const KnowledgeChunk(
        id: 'ext.extra_service',
        source: KnowledgeSourceKind.publicOps,
        title: 'Glemt / ekstra tjeneste på leveringen',
        tags: [
          'ekstra tjeneste',
          'glemt tjeneste',
          'legge til',
          'deliverysite',
          'payment',
        ],
        body: '''
Levering i dag/i morgen: hvis det er en vanlig tjeneste bilene kan utføre og kunden har deliverysite, kan ekstra tjeneste ofte legges til under levering. Kunden får da betalingslenke etterpå. Avklar via CCC/butikk før levering.

Levering lenger frem: CCC kan legge opp en SA på samme dato/tid (samme kundedata), slik at tjenesten følger med i planleggingen.
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
Adresse, telefonnummer og kundenavn endres av CCC/butikk — ikke av leverandør.
Som oftest må leveringen bookes om for at endringen skal gjelde.

Ved levering samme dag / neste dag på dagtid kan korrekt telefonnummer noen ganger noteres til sjåfør via CCC, men den permanente endringen må fortsatt gjøres i ordren.
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
Noen ganger feiler registrering på sjåførens enhet, selv om leveringen er gjort.
Er leveringen fra i går: vent normalt til neste arbeidsdag for oppdatering.
Er den eldre: kontakt CCC og be dem følge opp status/utlevering i systemet.
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
Endring fra curbside (fortauskant) til deliverysite (anvist plass) gjøres av CCC/butikk i deres system — ikke av leverandør.
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
Hvis varen ikke ble hentet fra butikk: nei — den kan normalt ikke leveres til oppsatt tid likevel.
Ordren må bookes om med både henting og levering.

Butikk må ha gjort pick & pack i tide. Uten klargjøring blir ikke henting planlagt riktig.
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
MAVI kan ikke kansellere ordre i Elkjøps system.
CCC/butikk må kansellere selv.

Be samtidig CCC bekrefte at leveringen ikke skal kjøres, slik at den ikke blir planlagt ut.
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
For returhentinger kan dato ofte justeres ved behov.
Be CCC sende forespørsel med ordrenummer og ønsket dato.
''',
      );

  static KnowledgeChunk _orderNotes() => const KnowledgeChunk(
        id: 'ext.notes',
        source: KnowledgeSourceKind.publicOps,
        title: 'Viktig info til sjåfør / oppdrag',
        tags: [
          'beskjed',
          'note',
          'informasjon',
          'kode',
          'port',
          'ring først',
        ],
        body: '''
Viktig informasjon til oppdraget (portkode, ring først, vanskelig adkomst) må legges inn på ordren via CCC/butikk, slik at den følger sjåføren.

Er leveringen i dag: be også CCC sørge for at sjåfør varsles.
Er leveringen i morgen eller senere: legg inn notat i ordren i god tid.
''',
      );
}
