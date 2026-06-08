/// Valgbare LogiqRMA-kommentarer ved registrering av trekk.
const List<String> kPartnerDeductionLogiqrmaDescriptions = [
  'Trekk — feil sortering avfall',
  'Trekk — HMS / uniform og vernesko',
  'Trekk — feilparkering',
  'Trekk — manglende rutebekreftelse',
  'Trekk — kjøretøystandard',
  'Trekk — leveringskvalitet',
  'Trekk — manglende dokumentasjon',
  'Trekk — renhold og orden',
  'Trekk — kommunikasjon / oppfølging',
  'Trekk — administrativt gebyr',
  'Trekk — annet (se kommentar)',
];

String? logiqrmaDescriptionForTemplate(String templateId) {
  return switch (templateId) {
    'waste_sorting' => 'Trekk — feil sortering avfall',
    'uniform_safety' => 'Trekk — HMS / uniform og vernesko',
    'wrong_parking' => 'Trekk — feilparkering',
    'route_ack_late' => 'Trekk — manglende rutebekreftelse',
    'vehicle_standard' => 'Trekk — kjøretøystandard',
    'delivery_quality' => 'Trekk — leveringskvalitet',
    'missing_docs' => 'Trekk — manglende dokumentasjon',
    'cleanliness' => 'Trekk — renhold og orden',
    'communication' => 'Trekk — kommunikasjon / oppfølging',
    _ => null,
  };
}
