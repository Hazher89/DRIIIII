/// Digital leieavtale for kjøretøy (forenklet — parter/dato fylles av systemet).
class VehicleRentalAgreement {
  VehicleRentalAgreement._();

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
Alt arkiveres automatisk i DriftPro for sporbarhet for både utleier og system.

14. Personvern
Kun autoriserte brukere hos utleier, leietaker og MAVI har tilgang til avtale, bilder og historikk.
''';
  }
}
