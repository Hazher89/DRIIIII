/// Digital leieavtale for kjøretøy (forenklet — parter/dato fylles av systemet).
class VehicleRentalAgreement {
  VehicleRentalAgreement._();

  static String body({
    required String registrationNumber,
    required String vehicleMake,
    String? unitCode,
    String? borrowerName,
    String? rentalPeriodLabel,
  }) {
    final reg = registrationNumber.trim().isEmpty ? '—' : registrationNumber.trim();
    final make = vehicleMake.trim().isEmpty ? '—' : vehicleMake.trim();
    final mavi = unitCode?.trim();
    final borrower = borrowerName?.trim().isEmpty ?? true ? 'valgt samarbeidspartner' : borrowerName!.trim();
    final period = rentalPeriodLabel?.trim().isEmpty ?? true
        ? 'Som avtalt i DriftPro (start/slutt registreres digitalt).'
        : rentalPeriodLabel!.trim();

    return '''
LEIEAVTALE FOR KJØRETØY

1. Avtalens formål
Denne avtalen regulerer midlertidig utlån av kjøretøy mellom samarbeidspartnere i MAVI-nettverket. Kjøretøyet skal brukes i samsvar med gjeldende lover, transportløyver og interne rutiner.

2. Kjøretøyinformasjon
Registreringsnummer: $reg
Merke: $make${mavi != null && mavi.isNotEmpty ? '\nMAVI-enhet: $mavi' : ''}

3. Leieperiode
$period
Utlånet skjer først når bileier har dokumentert tilstand (6 bilder), bekreftet avtalen, og MAVI har godkjent utleien i DriftPro.

4. Leiepris, kostnader og fakturering
Partene er ansvarlige for avtalt vederlag og eventuelle tillegg (drivstoff, bom, parkering, skader) i henhold til samarbeidet mellom $borrower og utleier. Fakturering og oppgjør skjer utenom denne digitale bekreftelsen dersom annet ikke er avtalt skriftlig.

5. Tilstand og dokumentasjon
Bileier bekrefter at opplastede bilder (front, bak, høyre, venstre, last/skap, dashboard) og oppgitt drivstoff- og kilometerstand gjenspeiler kjøretøyets tilstand ved utlån.

6. Ansvar
Låntaker er ansvarlig for kjøretøyet i leieperioden, inkludert forsvarlig bruk, forsikring der dette følger av avtale, og meldeplikt ved skade eller avvik.

7. Godkjenning
Ved å sende til godkjenning bekrefter bileier at avtalen er lest og akseptert. Utleie er bindende først når MAVI har godkjent i DriftPro. Da kan nøkkel/overlevering skje til $borrower.

8. Personvern (GDPR)
Kun autoriserte brukere hos utleier, låntaker og MAVI har tilgang til denne avtalen og tilhørende bilder. Data deles ikke med andre partnere.
''';
  }
}
