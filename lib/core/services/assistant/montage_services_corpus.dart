import 'assistant_corpus.dart';

/// Offentlig kunnskapsbase: Elkjøp monteringstjenester (PDF 23.07.2026).
/// Utføres av MAVI hos kunden — enkle (sjåfør) og avanserte (montør).
abstract final class MontageServicesCorpus {
  static const overviewId = 'montage.overview';

  static List<KnowledgeChunk> chunks() => [
        _overview(),
        ..._simpleServices(),
        ..._advancedServices(),
      ];

  /// Kort tekst til Edge Function / prompt (server-side).
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
        id: overviewId,
        source: KnowledgeSourceKind.montage,
        title: 'Oversikt monteringstjenester',
        tags: [
          'montering',
          'elkjop',
          'elkjøp',
          'mavi',
          'levering',
          'enkel',
          'avansert',
        ],
        body: '''
MAVI utfører monteringstjenester hos kunden for Elkjøp.

Enkle tjenester: utføres av sjåfør ved levering.
Steg: frakobling → bæring → transport → montering.

Avanserte tjenester: utføres av montør.

Denne chatten er for CCC og butikk: hva dere skal gjøre i booking,
og hva som er inkludert / ikke inkludert i monteringstjenester.

Ikke si «kontakt CCC/butikk». Ingen priser eller live ordrestatus her.
''',
      );

  static List<KnowledgeChunk> _simpleServices() => [
        _service(
          id: 'montage.simple.fridge',
          title: 'InstallFridge / Freezer (enkel — ikke SBS)',
          tags: [
            'enkel',
            'kjøleskap',
            'fryser',
            'fridge',
            'freezer',
            'installfridge',
            'sjåfør',
          ],
          included: [
            'Frakopling av gammelt produkt',
            'Fjerning av produktemballasje',
            'Plassering av produkt på ønsket sted',
            'Tilkobling til eksisterende strømuttak (kun hvis skapet har av/på-knapp)',
            'Informere kunde om at produktet ikke må kobles til strøm før etter 3 timer',
            'Justere produktet',
            'Retur av emballasje',
          ],
          customer: [
            'Klargjøre anvist plass',
            'Velge skap med riktig side av dørhengsel',
            'Tømme gammelt produkt',
          ],
          excluded: [
            'Omhengsle produkt',
            'Klargjøring/tømme gammelt produkt',
            'Tilkobling til strøm hvis skapet ikke har av/på-knapp',
            'Funksjonstest',
          ],
          note: 'Gjelder ikke side-by-side (SBS). SBS er avansert tjeneste.',
        ),
        _service(
          id: 'montage.simple.cooker',
          title: 'InstallCooker (enkel komfyr)',
          tags: [
            'enkel',
            'komfyr',
            'cooker',
            'installcooker',
            'ovn',
            'sjåfør',
          ],
          included: [
            'Frakopling av gammelt produkt',
            'Fjerning av produktemballasje',
            'Plassering på ønsket sted (snekkerarbeid ikke inkludert)',
            'Montering av støpsel (ikke 4/5 ledere)',
            'Tilkobling til eksisterende strømuttak',
            'Justere i høyde etter kundens benkeplate/sokkel dersom komfyren har justerbare bein/sokkel',
            'Funksjonstest: over/undervarme 100°, lys og temperaturindikator',
            'Retur av emballasje',
          ],
          customer: [
            'Klargjøre anvist plass',
            'Sørge for at komfyren kan tilpasses etter benkeplatens høyde',
            'Anvist plass ikke lenger enn 0,5 m fra strømuttak (bransjestandard)',
          ],
          excluded: [
            'Tilkobling gasskomfyr',
          ],
        ),
        _service(
          id: 'montage.simple.wash',
          title: 'InstallWash (enkel vaskemaskin)',
          tags: [
            'enkel',
            'vaskemaskin',
            'wash',
            'installwash',
            'vask',
            'sjåfør',
          ],
          included: [
            'Frakopling av gammelt produkt',
            'Fjerning av produktemballasje',
            'Plassering på ønsket sted',
            'Tilkobling til vann/avløp',
            'Tilkobling til strømuttak',
            'Justere produktet i vater',
            'Funksjonstest: lekkasjekontroll, vanninntak, kalibrering, avløpsslange',
            'Retur av emballasje',
          ],
          customer: [
            'Klargjøre anvist plass',
            'Anvist plass maks 1,2 m fra strøm, vann og avløp',
            'Rommet må være godkjent våtrom etter norsk lov — ellers må installasjon gjøres av fagperson',
            'Kunde ansvarlig for vibrasjonsdempere/stableramme ved stabling',
          ],
          excluded: [
            'Vibrasjonsdempere/stableramme',
            'Skjøting/skjøteledning til strøm, skjøteslanger vann eller avløp',
            'Installasjon av fagperson',
          ],
        ),
        _service(
          id: 'montage.simple.dryer',
          title: 'InstallDryer (enkel tørketrommel)',
          tags: [
            'enkel',
            'tørketrommel',
            'torketrommel',
            'dryer',
            'installdryer',
            'sjåfør',
          ],
          included: [
            'Frakopling av gammelt produkt',
            'Fjerning av produktemballasje',
            'Plassering på ønsket sted',
            'Tilkobling til avløp dersom relevant',
            'Tilkobling til strømuttak',
            'Justere produktet i vater',
            'Funksjonstest',
            'Retur av emballasje',
          ],
          customer: [
            'Klargjøre anvist plass',
            'Kunde ansvarlig for vibrasjonsdempere/stableramme ved stabling',
          ],
          excluded: [
            'Vibrasjonsdempere/stableramme',
          ],
        ),
        _service(
          id: 'montage.simple.tvstand',
          title: 'TVonStand (enkel TV på fot)',
          tags: [
            'enkel',
            'tv',
            'tvonstand',
            'fot',
            'stand',
            'sjåfør',
          ],
          included: [
            'Frakopling av gammelt produkt',
            'Fjerning av produktemballasje',
            'Montere TV på medfølgende fot',
            'Plassering på anvist plass',
            'Tilkobling av eksisterende komponenter (inntil 3 stk)',
            'Tilkobling til strøm',
            'Funksjonstest: skjerm og synlige skader',
            'Retur av emballasje',
          ],
          customer: [
            'Klargjøre anvist plass',
            'Klar tilgang til strømuttak',
            'Møbel som TV skal stå på må tåle vekten',
            'TV-møbler må være montert før TV ankommer',
            'Kjøp av riktige kabler i riktig lengde',
          ],
          excluded: [
            'Tilkobling av nye komponenter',
            'Skjule kabler',
            'Tilleggsutstyr som veggfeste, div. kabler osv.',
            'Opphengt TV på vegg',
            'Oppsett av TV (WIFI, kanalsøk etc.)',
          ],
        ),
      ];

  static List<KnowledgeChunk> _advancedServices() => [
        _service(
          id: 'montage.adv.fridge_front',
          title: 'InstallFridge med integrert front (avansert)',
          tags: [
            'avansert',
            'kjøleskap',
            'integrert',
            'front',
            'fridge',
            'montør',
          ],
          included: [
            'Frakopling av gammelt produkt',
            'Fjerning av produktemballasje',
            'Plassering på ønsket sted',
            'Tilkobling til eksisterende strømuttak (kun hvis av/på-knapp)',
            'Justere produktet i vater',
            'Installasjon av front',
            'Retur av emballasje',
          ],
          customer: [
            'Riktig størrelse i henhold til innredning',
            'Riktig type stikkontakt tilgjengelig uten demontering av støpsel',
            'Tilstrekkelig lufting etter anvisning fra leverandør',
            'Klargjøre anvist plass',
          ],
          excluded: [
            'Endringer på innredning',
            'Endringer på fast strømanlegg',
            'Skjøting/skjøteledning til strøm',
            'Funksjonstest',
          ],
          note: 'Avansert tjeneste — utføres av montør.',
        ),
        _service(
          id: 'montage.adv.sbs',
          title: 'InstallSBS (avansert side-by-side)',
          tags: [
            'avansert',
            'sbs',
            'side-by-side',
            'kjøleskap',
            'installsbs',
            'montør',
          ],
          included: [
            'Frakopling av gammelt produkt',
            'Fjerning av produktemballasje',
            'Plassering på ønsket sted',
            'Tilkobling til eksisterende strømuttak (kun hvis av/på-knapp)',
            'Tilkobling til vann av rørlegger',
            'Justere produktet',
            'Retur av emballasje',
          ],
          customer: [
            'Riktig størrelse i henhold til innredning',
            'Riktig type stikkontakt tilgjengelig uten demontering av støpsel',
            'Tilstrekkelig lufting etter anvisning fra leverandør',
            'Klargjøre anvist plass',
          ],
          excluded: [
            'Endringer på innredning',
            'Endringer på fast strømanlegg',
            'Skjøting/skjøteledning/slanger til strøm/vann',
            'Funksjonstest',
          ],
          note: 'Avansert. Vannkobling gjøres av rørlegger som del av tjenesten.',
        ),
        _service(
          id: 'montage.adv.dish',
          title: 'InstallDish (avansert oppvaskmaskin)',
          tags: [
            'avansert',
            'oppvaskmaskin',
            'dish',
            'installdish',
            'integrert',
            'montør',
          ],
          included: [
            'Frakopling av gammelt produkt',
            'Fjerning av produktemballasje',
            'Plassering på ønsket sted',
            'Tilkobling til vann/avløp av rørlegger',
            'Tilkobling til strømuttak',
            'Justere produktet i vater',
            'Montering av sokkel dersom denne finnes fra før',
            'Montering av waterguard dersom relevant',
            'Ev. installering av front på InstallDishI',
            'Utskjæring av hull til Aquastop',
            'Funksjonstest',
            'Retur av emballasje',
          ],
          customer: [
            'Opplegg og tilgang til vann og strøm',
            'Nok lengde på slanger til avløp/inntak (skal ikke skjøtes)',
            'Klargjøre anvist plass',
          ],
          excluded: [
            'Montering/fjerning av oppbygging under maskin',
            'Endringer på innredning (gjelder ikke hull til Aquastop)',
            'Montering av front dersom InstallDishI ikke er bestilt',
            'Utskjæring av sokkel-list',
          ],
        ),
        _service(
          id: 'montage.adv.hood',
          title: 'InstallHood S/M/L (avansert ventilator)',
          tags: [
            'avansert',
            'ventilator',
            'hood',
            'installhood',
            'kjøkkenvifte',
            'montør',
          ],
          included: [
            'Frakopling av gammelt produkt',
            'Fjerning av produktemballasje',
            'Plassering på ønsket sted',
            'Tilkobling til eksisterende strømuttak',
            'Justere produktet i vater',
            'Funksjonstest',
            'Retur av emballasje',
          ],
          customer: [
            'Klargjøre anvist plass',
            'Riktig størrelse i henhold til innredning',
            'Riktig type ventilator (kullfilter/utblåsing/sentralanlegg)',
            'Hull til ventilator',
            'Tilstrekkelig lufting etter anvisning fra leverandør',
          ],
          excluded: [
            'Hull til ventilator',
            'Endringer på innredning',
            'Oppgradering av strømanlegg',
            'Oppgradering av lufteanlegg',
          ],
        ),
        _service(
          id: 'montage.adv.micro',
          title: 'InstallMicro (avansert integrert mikro)',
          tags: [
            'avansert',
            'mikro',
            'mikrobølgeovn',
            'micro',
            'installmicro',
            'integrert',
            'montør',
          ],
          included: [
            'Frakopling av gammelt produkt',
            'Fjerning av produktemballasje',
            'Plassering på ønsket sted',
            'Tilkobling til eksisterende strømuttak',
            'Funksjonstest',
            'Retur av emballasje',
          ],
          customer: [
            'Riktig størrelse i henhold til innredning',
            'Riktig type stikkontakt tilgjengelig uten demontering av støpsel',
            'Tilstrekkelig lufting etter anvisning fra leverandør',
            'Klargjøre anvist plass',
          ],
          excluded: [
            'Endringer på innredning',
            'Endringer på fast strømanlegg',
            'Skjøting til strøm (skjøteledning ikke godkjent)',
          ],
        ),
        _service(
          id: 'montage.adv.hob',
          title: 'InstallHob (avansert platetopp)',
          tags: [
            'avansert',
            'platetopp',
            'hob',
            'installhob',
            'koketopp',
            'montør',
          ],
          included: [
            'Frakopling av gammelt produkt',
            'Fjerning av produktemballasje',
            'Plassering på ønsket sted (snekkerarbeid ikke inkludert)',
            'Montering av støpsel (gjelder ikke 4/5 ledere)',
            'Tilkobling til eksisterende strømuttak',
            'Forsegle skjøtet mellom platetopp og benkeplate',
            'Justere produktet i vater',
            'Funksjonstest: se at platen skrur seg på',
            'Retur av emballasje',
          ],
          customer: [
            'Riktig størrelse i henhold til innredning',
            'Riktig type stikkontakt tilgjengelig uten demontering av støpsel',
            'Tilstrekkelig lufting etter anvisning fra leverandør',
            'Klargjøre anvist plass',
          ],
          excluded: [
            'Utskjæring av benkeplate',
            'Endringer på innredning',
            'Platetopp med gass',
            'Endringer på fast strømanlegg',
            'Koble på løs ledning',
          ],
        ),
        _service(
          id: 'montage.adv.oven',
          title: 'InstallOven (avansert ovn)',
          tags: [
            'avansert',
            'ovn',
            'oven',
            'installoven',
            'integrert',
            'montør',
          ],
          included: [
            'Frakopling av gammelt produkt',
            'Fjerning av produktemballasje',
            'Plassering på ønsket sted (snekkerarbeid ikke inkludert)',
            'Tilkobling til strømuttak. Ikke samme kurs som platetopp med mindre 3-fas 400V',
            'Funksjonstest: over/undervarme',
            'Retur av emballasje',
          ],
          customer: [
            'Riktig størrelse i henhold til innredning',
            'Riktig type stikkontakt tilgjengelig uten demontering av støpsel',
            'Tilstrekkelig lufting etter anvisning fra leverandør',
            'Klargjøre anvist plass',
          ],
          excluded: [
            'Endringer på innredning',
            'Endringer på fast strømanlegg',
            'Skjøting til strøm (skjøteledning ikke godkjent)',
          ],
        ),
        _service(
          id: 'montage.adv.tvwall',
          title: 'TVonWall (avansert TV på vegg)',
          tags: [
            'avansert',
            'tv',
            'tvonwall',
            'vegg',
            'veggmontering',
            'montør',
          ],
          included: [
            'Utpakking',
            'Tilkobling av eksisterende komponenter (inntil 3), kilde',
            'Montering på vegg',
            'Funksjonstest: skjerm og synlige skader',
            'Retur av emballasje',
          ],
          customer: [
            'Klargjøre anvist plass',
            'Enkel tilgjengelighet til vegg og strømuttak',
            'Nok bæring i veggen til at TV kan henges opp',
            'Veggfeste må kjøpes separat (når veggfeste ikke er inkludert sammen med TVen)',
          ],
          excluded: [
            'Koble til nye komponenter som ikke har vært koblet til før',
            'Forsterkning av vegg uten nok bæring',
            'Oppsett av TV (WIFI, kanalsøk etc.)',
            'Skjule kabler',
          ],
        ),
        _service(
          id: 'montage.adv.turndoor',
          title: 'TurnDoor (avansert omhengsling)',
          tags: [
            'avansert',
            'omhengsling',
            'turndoor',
            'dør',
            'hengsel',
            'montør',
          ],
          included: [
            'Endre døråpning fra venstre til høyre eller motsatt',
            'Dobbeltsjekke at elektronikk sitter riktig',
            'Funksjonstest: dørene åpnes/lukkes uten utfordringer eller knirkelyder',
          ],
          customer: [
            'Bekrefte fra hvilken side døren skal åpnes',
            'Finne ut om produktet faktisk kan omhengsles',
            'Skaffe ekstra utstyr dersom nødvendig',
          ],
          excluded: [
            'Omhengsle skap som ikke fysisk kan omhengsles',
            'Bestilling av omhengslingssett dersom det ikke følger med skapet',
          ],
        ),
      ];

  static KnowledgeChunk _service({
    required String id,
    required String title,
    required List<String> tags,
    required List<String> included,
    required List<String> customer,
    required List<String> excluded,
    String? note,
  }) {
    final body = StringBuffer()
      ..writeln(note ?? '')
      ..writeln('Inkludert:')
      ..writeln(included.map((e) => '• $e').join('\n'))
      ..writeln()
      ..writeln('Kunden sørger for:')
      ..writeln(customer.map((e) => '• $e').join('\n'))
      ..writeln()
      ..writeln('Ikke inkludert:')
      ..writeln(excluded.map((e) => '• $e').join('\n'));
    return KnowledgeChunk(
      id: id,
      source: KnowledgeSourceKind.montage,
      title: title,
      tags: tags,
      body: body.toString().trim(),
    );
  }
}
