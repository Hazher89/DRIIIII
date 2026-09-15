/// Digital leieavtale for kjøretøy (forenklet — parter/dato fylles av systemet).
///
/// Klausulen om kjøretøysporing er utformet med utgangspunkt i:
/// - Datatilsynet: «GPS og sporing av yrkesbiler»
/// - Arbeidsmiljøloven §§ 9-1 og 9-2 (kontrolltiltak / informasjon)
/// - Personvernforordningen (GDPR) art. 5, 6 og 13 (formål, rettslig grunnlag, informasjon)
///
/// Dette er avtale-/maltekst, ikke juridisk rådgivning. Virksomheten bør vurdere
/// egen behandlingsprotokoll og eventuelt DPIA for sporingssystemet.
class VehicleRentalAgreement {
  VehicleRentalAgreement._();

  static const String approverPriorityText =
      'Jassy signerer/godkjenner først. Hvis Jassy er borte, overtar Herish. '
      'Hvis Herish er borte, overtar Julie. Hvis alle er borte, overtar Karwan. '
      'Samme rekkefølge gjelder ved retur.';

  static const List<String> handoutChecklist = [
    'Kontroller at riktig bil, periode og låntaker er valgt.',
    'Gå gjennom leieavtalen med låntaker før bilen utleveres, inkludert klausul om kjøretøysporing.',
    'Dokumenter bilen med 6 bilder: front, bak, høyre, venstre, last/skap og dashboard.',
    'Registrer drivstoff-/ladenivå, kilometerstand og eventuelle merknader.',
    'Sjekk at bilen er ryddet, nøkler er klare og synlige skader er kommentert.',
    'Send deretter avtalen til MAVI for godkjenning i riktig rekkefølge.',
  ];

  static const List<String> returnChecklist = [
    'Sammenlign retur mot bilder og data fra utlevering.',
    'Ta 6 nye bilder ved retur og registrer drivstoff-/ladenivå og kilometerstand.',
    'Noter nye skader, avvik, manglende vask eller annet som må følges opp.',
    'Retur godkjennes av MAVI i samme rekkefølge som ved utlevering.',
  ];

  /// Fast tekst om lovlig kjøretøysporing — brukes i avtalen og i UI-hjelpetekst.
  static const String vehicleTrackingClause = '''
14. Kjøretøysporing, kjørestil og telematikk (informert aksept)
Kjøretøyet er eller kan være utstyrt med en mobil enhet montert i bilen («Monitoren»)
som tilhører eller driftes av MAVI Logistikk AS («MAVI»). Monitoren kan registrere
og overføre blant annet:
- geografisk posisjon og bevegelse (GPS/lokasjon),
- hastighet og kjørerute,
- akselerasjon, bråbremsing, skarpe svinger og andre kjørestil-/sikkerhetsindikatorer,
- tidspunkter for start/stopp og tomgang, samt tekniske statusdata knyttet til bilen.

Formål med behandlingen (spesifisert og begrenset):
a) flåtestyring og operativ drift (finne og tildele bil, ruteplanlegging, oppfølging av leieforholdet),
b) sikring av kjøretøy, gods og verdier,
c) trafikksikkerhet og oppfølging av alvorlig kjørestil (f.eks. bråbrems/hard akselerasjon),
d) dokumentasjon ved skade, misbruk, tyveri eller tvist knyttet til leieforholdet.

Rettslig forankring og begrensninger:
Behandlingen skjer i samsvar med norsk personvernregelverk, herunder personvernforordningen
(GDPR) artikkel 5 (bl.a. formålsbegrensning og dataminimering) og artikkel 6
(typisk avtale/nødvendig for gjennomføring av leieforholdet og/eller berettiget interesse
knyttet til flåtestyring, sikkerhet og verdibeskyttelse, jf. Datatilsynets veiledning
om GPS og sporing av yrkesbiler). Opplysningene skal ikke brukes til nye, uforenelige
formål uten nytt rettslig grunnlag og nødvendig informasjon.

Ved digital signering/aksept av denne avtalen bekrefter leietaker (og den som signerer
på vegne av leietaker) at:
1) leietaker er informert om at Monitoren kan være montert og aktiv under leieperioden,
2) MAVI har tillatelse til å spore og registrere data som beskrevet over, begrenset til
   de angitte formålene, så lenge kjøretøyet er utlånt / under leieforholdet,
3) leietaker selv har ansvar for å informere egne sjåfører/ansatte som bruker bilen om
   sporingen, dens formål og praktiske konsekvenser, i tråd med arbeidsmiljøloven
   §§ 9-1 og 9-2 der dette gjelder for leietakers arbeidsforhold,
4) leietaker ikke skal fjerne, dekke til, slå av eller sabotere Monitoren uten skriftlig
   samtykke fra MAVI.

Tilgang til sporings- og kjørestildata hos MAVI:
Tilgangen er ikke åpen for alle ansatte. Den begrenses til personer med tjenstlig behov
for flåte-/utleieoppfølging, sikkerhet eller tvist (typisk drift, ledelse og særskilt
autoriserte roller i DriftPro). Vanlige ansatte uten slik rolle skal ikke ha innsyn i
live-sporing eller detaljert kjørestildata. Alle med tilgang er underlagt
taushetsplikt og formålsbegrensning. Data lagres ikke lenger enn nødvendig for
formålene over, rettslige krav eller dokumentert tvist.''';

  /// Obligatoriske avkrysninger låntaker må bekrefte før digital signering.
  static const List<String> borrowerAckChecklist = [
    'Jeg har lest hele leieavtalen, inkludert punkt 14 om kjøretøysporing.',
    'Jeg forstår at en mobil kan være montert i bilen og registrerer GPS, bevegelse, hastighet og kjørestil (f.eks. bråbrems).',
    'Jeg gir MAVI tillatelse til slik sporing begrenset til flåtestyring, sikkerhet, verdibeskyttelse og dokumentasjon i leieperioden.',
    'Jeg skal informere egne sjåfører/ansatte som bruker bilen om at den spores.',
    'Jeg skal ikke fjerne, dekke til eller sabotere sporenheten uten skriftlig samtykke fra MAVI.',
    'Jeg aksepterer at avtalen blir digitalt signert når jeg sender inn dokumentasjonen.',
  ];

  static String body({
    required String registrationNumber,
    required String vehicleMake,
    String? unitCode,
    String? lenderName,
    String? lenderOrgNumber,
    String? borrowerName,
    String? borrowerOrgNumber,
    String? rentalPeriodLabel,
  }) {
    bool isMissing(String value) {
      final t = value.trim();
      return t.isEmpty || t == '-' || t == '—';
    }

    final reg = isMissing(registrationNumber) ? 'JD77645' : registrationNumber.trim().toUpperCase();
    final make = isMissing(vehicleMake) ? 'PEUGEOT BOXER' : vehicleMake.trim().toUpperCase();
    final mavi = unitCode?.trim().isEmpty ?? true ? '—' : unitCode!.trim();
    final lender = lenderName?.trim().isEmpty ?? true ? 'MAVI Logistikk AS' : lenderName!.trim();
    final lenderOrg = lenderOrgNumber?.trim().isEmpty ?? true ? '912 332 209' : lenderOrgNumber!.trim();
    final borrower = borrowerName?.trim().isEmpty ?? true ? 'Samarbeidspartner (låntaker)' : borrowerName!.trim();
    final borrowerOrg = borrowerOrgNumber?.trim().isEmpty ?? true ? 'Oppgis automatisk fra partnerregister' : borrowerOrgNumber!.trim();
    final period = rentalPeriodLabel?.trim().isEmpty ?? true ? 'Som registrert i DriftPro.' : rentalPeriodLabel!.trim();

    return '''
LEIEAVTALE FOR KJØRETØY

1. Parter
Denne avtalen («Avtalen») inngås mellom:
Utleier: $lender, Org.nr: $lenderOrg
Adresse: Alf Bjerckes vei 26, 0582 Oslo
Leietaker: $borrower
Leietakers org.nr: $borrowerOrg

2. Avtalens formål
Formålet med avtalen er å regulere leieforholdet for undernevnte kjøretøy mellom MAVI Logistikk AS (utleier) og valgt samarbeidspartner (leietaker).

3. Kjøretøyinformasjon
Merke/modell: $make
Registreringsnummer: $reg
Årsmodell: 2016
Type: Varebil
MAVI-enhet: $mavi

4. Leieperiode
$period
Utlånet skjer først når tilstand er dokumentert (6 bilder, drivstoff og km), avtalen er bekreftet digitalt og MAVI har godkjent utleien i DriftPro.

5. Leiepris, kostnader og fakturering
Leiepris: 1.000,- pr påbegynte dag.
Drivstoff: Etterfylles til samme nivå som ved utlevering. Manglende etterfylling medfører administrasjonsgebyr på 500,- ekskl. drivstoff.
Bompenger: Inkludert i leien.
Vask/rengjøring: Inkludert i leien.
Servicekostnader ved lang leieperiode: Inkludert i leien.
Fakturering skjer ved motregning på oppsummering.

6. Forsikring og egenandel
Kjøretøyet er forsikret gjennom utleier.
Leietaker er ansvarlig for skader som ikke dekkes av forsikringen, samt eventuell egenandel ved skade.

7. Bruk av kjøretøyet
Kjøretøyet skal brukes i samsvar med norsk lov og produsentens anbefalinger.
Alders-/sertifikatkrav: 18 år / Klasse B.
Ikke tillatt bruk:
- Ulovlig transport
- Konkurransekjøring
- Overlasting
- Bruk utenfor Norge uten skriftlig godkjenning

8. Vedlikehold, service og reparasjoner
Leietaker står for daglig tilsyn (olje, lufttrykk, vask, lys m.m.).
Større reparasjoner skal forhåndsgodkjennes av utleier.
Skader meldes umiddelbart.

9. Bøter, overtredelser og gebyrer
Leietaker er ansvarlig for parkeringsgebyrer, fartsbøter og overtredelsesgebyrer.
Utleier kan viderefakturere slike kostnader med administrasjonsgebyr.

10. Ansvarsbegrensninger
Partene er ikke ansvarlige for indirekte tap med mindre skaden skyldes grov uaktsomhet eller forsett.
Utleiers ansvar er begrenset til leiebeløpet for inneværende periode.

11. Force Majeure
Partene fritas for ansvar ved forhold utenfor deres kontroll (streik, krig, naturkatastrofer, myndighetsrestriksjoner).

12. Tvister, lovvalg og verneting
Avtalen reguleres av norsk rett.
Tvister søkes løst i minnelighet, ellers behandles saken i tingretten i Oslo.

13. Tilstandsrapport og digital signering
Tilstandsrapport (6 bilder: front, bak, begge sider, inne i skap og dashboard) registreres ved utlevering og retur.
Kilometerstand, drivstoff og kommentarer lagres digitalt.
Når bileier trykker «akseptert» og sender inn, regnes avtalen som digitalt signert av leietaker/partnerbruker.
Ved signering bekrefter leietaker også punkt 14 om kjøretøysporing.
Alt arkiveres automatisk i DriftPro for sporbarhet for både utleier og system.
MAVI godkjenner i denne rekkefølgen: $approverPriorityText

$vehicleTrackingClause

15. Personvern
Kun autoriserte brukere hos utleier, leietaker og MAVI har tilgang til avtale, bilder, historikk og sporingsdata etter punkt 14.
Behandling skjer i tråd med personvernforordningen og personopplysningsloven. Leietaker kan kontakte MAVI for innsynsspørsmål knyttet til leieforholdet.
''';
  }
}
