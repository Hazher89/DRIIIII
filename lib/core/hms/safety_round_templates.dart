/// Vernerunde-maler etter norsk HMS (AML, brannforskrift, kontor/lager).
class SafetyRoundTemplateSection {
  final String id;
  final String title;
  final String legalReference;
  final List<String> items;

  const SafetyRoundTemplateSection({
    required this.id,
    required this.title,
    required this.legalReference,
    required this.items,
  });
}

class SafetyRoundTemplateDef {
  final String id;
  final String title;
  final String description;
  final List<SafetyRoundTemplateSection> sections;

  const SafetyRoundTemplateDef({
    required this.id,
    required this.title,
    required this.description,
    required this.sections,
  });

  List<Map<String, dynamic>> toChecklistItems() {
    final out = <Map<String, dynamic>>[];
    for (final s in sections) {
      for (final item in s.items) {
        out.add({
          'section_id': s.id,
          'section_title': s.title,
          'legal_ref': s.legalReference,
          'task': item,
          'status': 'pending',
          'comment': '',
        });
      }
    }
    return out;
  }
}

class SafetyRoundTemplates {
  SafetyRoundTemplates._();

  /// Hovedmal: kontor, lager, verksted — dekker typiske krav i norsk regelverk.
  static const norskKontorLager = SafetyRoundTemplateDef(
    id: 'no_kontor_lager_full',
    title: 'Vernerunde – Kontor & lager (norsk lov)',
    description:
        'Omfattende sjekk etter Arbeidsmiljøloven, brannforskriften og internkontroll. '
        'Egnet for verneombud, leder eller superadmin.',
    sections: [
      SafetyRoundTemplateSection(
        id: 'organisering',
        title: 'Organisering og internkontroll',
        legalReference: 'Arbeidsmiljøloven kap. 4–5 (systematisk HMS)',
        items: [
          'HMS-policy og ansvar er kjent for ansatte',
          'Verneombud er valgt og synlig inforert (plakat/kontakt)',
          'AMU eller vernerunde-rutiner er etablert der det kreves',
          'Risikovurderinger er oppdatert for relevante arbeidsoppgaver',
          'Avvikssystem brukes og følges opp',
          'Opplæring i HMS ved nyansettelse og ved endringer',
        ],
      ),
      SafetyRoundTemplateSection(
        id: 'romning',
        title: 'Rømningsveier og nødutganger',
        legalReference: 'Brannforskriften kap. 12 – rømning',
        items: [
          'Rømningsveier er frie for hindringer',
          'Nødutganger åpnes lett og er merket med skilt',
          'Nødlys og ledelys fungerer (visuell kontroll / testlogg)',
          'Samlingsplass er merket og kjent',
          'Dører i rømningsvei åpnes i rømningsretning der påkrevd',
          'Gangbaner og trapper er ryddige og opplyste',
        ],
      ),
      SafetyRoundTemplateSection(
        id: 'brann',
        title: 'Brannvern og slokking',
        legalReference: 'Forskrift om brannforebygging',
        items: [
          'Brannslukningsapparater er tilgjengelige og kontrollert',
          'Brannslanger / hydrant er tilgjengelig der aktuelt',
          'Manuelt brannvern utløses testet etter plan',
          'Røykvarslere og brannalarm er i orden (siste test notert)',
          'Brannfarlig materiale lagres forsvarlig',
          'Røyking kun i anviste soner',
        ],
      ),
      SafetyRoundTemplateSection(
        id: 'elektro',
        title: 'Elektrisk anlegg og utstyr',
        legalReference: 'FEL / internkontroll elektriske anlegg',
        items: [
          'Synlige skader på kabler, stikk og skap',
          'Ikke overbelastede skjøteledninger / skjøteboks',
          'El-sikkerhetskontroll / DLE utført etter plan',
          'Maskiner og utstyr har CE / kontroll der påkrevd',
          'Låsesystem og påvisning ved arbeid på anlegg',
        ],
      ),
      SafetyRoundTemplateSection(
        id: 'kontor',
        title: 'Kontor – ergonomi og arbeidsmiljø',
        legalReference: 'AML § 4-3 (tilrettelegging)',
        items: [
          'Arbeidsstasjoner justerbare (stol/skjerm/høyde)',
          'Tilstrekkelig belysning uten blending',
          'Inneklima (temperatur, luft) oppleves tilfredsstillende',
          'Støynivå akseptabelt i kontorlandskap',
          'Hvile- / pauserom tilgjengelig',
          'Skjermarbeid – øyeavlastning og pauser',
        ],
      ),
      SafetyRoundTemplateSection(
        id: 'lager',
        title: 'Lager – orden, truck og løft',
        legalReference: 'AML + forskrift om bruk av arbeidsutstyr',
        items: [
          'Ganger og reoler er merket og ryddige',
          'Last på reol innen tillatt vekt / høyde',
          'Truckførere har dokumentert opplæring / sertifikat',
          'Truck daglig kontroll / servicehefte føres',
          'Gang- og kjøreveier er atskilt der mulig',
          'Pall og stablehøyder er forsvarlige',
          'Løfteutstyr og sjakler kontrollert',
        ],
      ),
      SafetyRoundTemplateSection(
        id: 'kjemikalier',
        title: 'Kjemikalier og farlig stoff',
        legalReference: 'Produktkontrollforskriften / REACH',
        items: [
          'Kjemikalier er merket og i originalemballasje',
          'SDS (sikkerhetsdatablad) tilgjengelig for ansatte',
          'Spillutstyr og øyeskylle ved kjemikalieområde',
          'Avfallshåndtering sortert (farlig avfall skilt)',
        ],
      ),
      SafetyRoundTemplateSection(
        id: 'ppe',
        title: 'Personlig verneutstyr (PVU)',
        legalReference: 'AML § 4-8',
        items: [
          'PVU tilgjengelig og i bruk der påkrevd',
          'Verneutstyr vedlikeholdes og byttes ved slitasje',
          'Synlighetsbekledning ved lager/uteområde',
          'Hørselvern ved støy over grenseverdi',
        ],
      ),
      SafetyRoundTemplateSection(
        id: 'beredskap',
        title: 'Førstehjelp og beredskap',
        legalReference: 'AML § 4-4 / brannberedskap',
        items: [
          'Førstehjelpsskrin komplett og merket',
          'Ansatte kjenner til nærmeste førstehjelpsutstyr',
          'Varslingsrutiner ved ulykke er kjent',
          'Kontaktliste nødnummer synlig (113, 110, 112)',
        ],
      ),
      SafetyRoundTemplateSection(
        id: 'ansatte',
        title: 'Ansatte – medvirkning og kompetanse',
        legalReference: 'AML kap. 6–7',
        items: [
          'Verneombud har møtt / deltar i runden',
          'Ansatte kan melde forhold uten negative sanksjoner',
          'Arbeidsinstrukser er tilgjengelige på arbeidsplass',
          'Befaring av psykososiale forhold (belastning, mobbing-rutine)',
        ],
      ),
      SafetyRoundTemplateSection(
        id: 'orden',
        title: 'Orden, fallsikring og utendørs',
        legalReference: 'Intern HMS / AML generelt',
        items: [
          'Gulv tørt og ikke glatt (vinter/søl)',
          'Avfall og emballasje fjernes regelmessig',
          'Utendørs gangbaner strødd / merket ved is',
          'Verneinnretninger på maskiner ikke fjernet',
        ],
      ),
    ],
  );

  static const verksted = SafetyRoundTemplateDef(
    id: 'no_verksted',
    title: 'Vernerunde – Verksted / produksjon',
    description: 'Tillegg for verksted med maskiner og kjemikalier.',
    sections: [
      SafetyRoundTemplateSection(
        id: 'maskin',
        title: 'Maskiner og verksted',
        legalReference: 'Forskrift om bruk av arbeidsutstyr',
        items: [
          'Maskinvern og nødstopp fungerer',
          'Verktøy i orden og riktig oppbevart',
          'Sveis/grinding – ventilasjon og briller',
          'Trykkluft / kompressor kontrollert',
        ],
      ),
    ],
  );

  static List<SafetyRoundTemplateDef> get all => [
        norskKontorLager,
        verksted,
      ];

  static SafetyRoundTemplateDef? byId(String? id) {
    if (id == null) return null;
    for (final t in all) {
      if (t.id == id) return t;
    }
    return null;
  }
}
