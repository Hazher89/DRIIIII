/// Profesjonelle maler for bot/trekk mot samarbeidspartnere.
class PartnerDeductionTemplate {
  const PartnerDeductionTemplate({
    required this.id,
    required this.title,
    required this.category,
    required this.shortDescription,
    required this.detailParagraph,
    required this.iconName,
  });

  final String id;
  final String title;
  final String category;
  final String shortDescription;
  final String detailParagraph;
  final String iconName;
}

const double kPartnerDeductionDefaultAmount = 500;

const List<PartnerDeductionTemplate> kPartnerDeductionTemplates = [
  PartnerDeductionTemplate(
    id: 'waste_sorting',
    title: 'Feil sortering av avfall',
    category: 'Miljø & orden',
    iconName: 'delete_outline',
    shortDescription: 'Avfall er ikke sortert i henhold til gjeldende rutiner.',
    detailParagraph:
        'Vi har registrert at avfall fra deres leveranser eller drift ikke er sortert '
        'i tråd med avtalte rutiner og gjeldende krav. Dette medfører ekstra håndtering '
        'og risiko for miljøavvik. Trekket dekker administrativ oppfølging og korrigerende tiltak.',
  ),
  PartnerDeductionTemplate(
    id: 'uniform_safety',
    title: 'Mangel på uniform og vernesko',
    category: 'HMS & fremtoning',
    iconName: 'checkroom_outlined',
    shortDescription: 'Påkrevd uniform og/eller vernesko manglet ved kontroll.',
    detailParagraph:
        'Ved kontroll ble det registrert at påkrevd MAVI-uniform og/eller godkjente vernesko '
        'ikke ble benyttet som avtalt. Dette er et brudd på våre HMS- og profilkrav overfor kunde. '
        'Trekket dekker administrativ behandling og oppfølging av avviket.',
  ),
  PartnerDeductionTemplate(
    id: 'wrong_parking',
    title: 'Feilparkert kjøretøy',
    category: 'Drift & logistikk',
    iconName: 'local_parking_outlined',
    shortDescription: 'Kjøretøy var parkert i strid med gjeldende parkeringsregler.',
    detailParagraph:
        'Kjøretøy tilknyttet deres oppdrag ble observert feilparkert, herunder blocking av '
        'rampe, ladeplass eller adkomst for andre transportører. Dette forsinker drift og '
        'skaper unødvendig risiko. Trekket dekker administrativ oppfølging.',
  ),
  PartnerDeductionTemplate(
    id: 'route_ack_late',
    title: 'Manglende rutebekreftelse',
    category: 'Ruter',
    iconName: 'route_outlined',
    shortDescription: 'Rute ble ikke bekreftet innen fastsatt frist.',
    detailParagraph:
        'Tildelt rute ble ikke bekreftet innen avtalt frist, noe som medførte forsinket '
        'planlegging og ekstra koordinering internt hos MAVI. Trekket dekker '
        'administrativt arbeid knyttet til omdisponering og purring.',
  ),
  PartnerDeductionTemplate(
    id: 'vehicle_standard',
    title: 'Utilstrekkelig kjøretøystandard',
    category: 'Kjøretøy',
    iconName: 'directions_car_outlined',
    shortDescription: 'Kjøretøy oppfylte ikke krav til renhold eller teknisk standard.',
    detailParagraph:
        'Kjøretøy benyttet i oppdrag oppfylte ikke avtalt standard for renhold, merking '
        'eller synlig teknisk tilstand. Dette påvirker kundeopplevelse og sikkerhet. '
        'Trekket dekker registrering og oppfølging av avviket.',
  ),
  PartnerDeductionTemplate(
    id: 'delivery_quality',
    title: 'Avvik i leveringskvalitet',
    category: 'Kvalitet',
    iconName: 'inventory_2_outlined',
    shortDescription: 'Leveranse utført i strid med kvalitetskrav eller rutiner.',
    detailParagraph:
        'Det er registrert avvik i leveringskvalitet, herunder skade, feil håndtering '
        'eller manglende dokumentasjon ved overlevering. Trekket dekker saksbehandling, '
        'kundekontakt og intern koordinering.',
  ),
  PartnerDeductionTemplate(
    id: 'documentation',
    title: 'Manglende dokumentasjon',
    category: 'Etterlevelse',
    iconName: 'description_outlined',
    shortDescription: 'Påkrevd dokumentasjon eller kvittering ble ikke levert.',
    detailParagraph:
        'Nødvendig dokumentasjon, signatur eller kvittering fra oppdrag ble ikke levert '
        'innen avtalt tid. Dette medfører ekstra kontroll og manuell oppfølging. '
        'Trekket dekker administrativ behandling.',
  ),
  PartnerDeductionTemplate(
    id: 'safety_breach',
    title: 'Brudd på HMS-/sikkerhetsregler',
    category: 'HMS',
    iconName: 'health_and_safety_outlined',
    shortDescription: 'Handlingsmønster i strid med gjeldende sikkerhetsinstrukser.',
    detailParagraph:
        'Det er registrert brudd på gjeldende HMS- og sikkerhetsinstrukser under utførelse '
        'av oppdrag. Alvorlighetsgrad vurderes særskilt, men trekket dekker '
        'obligatorisk registrering, varsling og intern oppfølging.',
  ),
  PartnerDeductionTemplate(
    id: 'communication',
    title: 'Manglende eller for sen kommunikasjon',
    category: 'Samarbeid',
    iconName: 'forum_outlined',
    shortDescription: 'Viktig henvendelse fra MAVI ble ikke besvart i tide.',
    detailParagraph:
        'Henvendelse fra MAVI vedrørende rute, avvik eller kunde ble ikke besvart innen '
        'rimelig tid, med påfølgende forsinkelse eller ekstra koordinering. '
        'Trekket dekker administrativ oppfølging.',
  ),
  PartnerDeductionTemplate(
    id: 'customer_complaint',
    title: 'Kundeklage med grunnlag',
    category: 'Kvalitet',
    iconName: 'record_voice_over_outlined',
    shortDescription: 'Bekreftet kundeklage knyttet til deres leveranse.',
    detailParagraph:
        'MAVI har mottatt og verifisert kundeklage knyttet til leveranse utført av '
        'deres sjåfør eller kjøretøy. Trekket dekker saksbehandling, dokumentasjon '
        'og intern kvalitetsoppfølging.',
  ),
  PartnerDeductionTemplate(
    id: 'other',
    title: 'Annet avvik',
    category: 'Annet',
    iconName: 'gavel_outlined',
    shortDescription: 'Annet avvik som medfører administrativt trekk.',
    detailParagraph:
        'Det er registrert et avvik som ikke dekkes av standardmal, men som likevel '
        'medfører dokumentert ekstraarbeid eller kostnad for MAVI. Beskriv avviket '
        'tydelig i kommentarfeltet. Trekket registreres etter intern vurdering.',
  ),
];

PartnerDeductionTemplate partnerDeductionTemplateById(String id) {
  return kPartnerDeductionTemplates.firstWhere(
    (t) => t.id == id,
    orElse: () => kPartnerDeductionTemplates.last,
  );
}
