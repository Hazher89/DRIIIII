/// Forhåndsdefinerte SMS-maler for partner-/ruteutsendelse.
class PartnerSmsTemplate {
  final String id;
  final String title;
  final String body;

  const PartnerSmsTemplate({
    required this.id,
    required this.title,
    required this.body,
  });
}

const List<PartnerSmsTemplate> kPartnerSmsTemplates = [
  PartnerSmsTemplate(
    id: 'delay_elkjop',
    title: 'Forsinket leveranse (Elkjøp)',
    body:
        'Hei, deres leveranse fra Elkjøp vil dessverre bli forsinket. '
        'Sjåføren vil ta kontakt 30 min før levering. Vi beklager dette. Mvh MAVI Logistikk',
  ),
  PartnerSmsTemplate(
    id: 'call_30min',
    title: '30 min før levering',
    body:
        'Hei! Sjåføren fra MAVI Logistikk ringer om ca. 30 minutter — vær forberedt på levering. '
        'Mvh MAVI Logistikk',
  ),
  PartnerSmsTemplate(
    id: 'on_the_way',
    title: 'På vei til deg',
    body:
        'Hei! Sjåføren vår er på vei til deg nå. Ved spørsmål, svar på denne meldingen. '
        'Mvh MAVI Logistikk',
  ),
  PartnerSmsTemplate(
    id: 'cannot_today',
    title: 'Kan ikke levere i dag',
    body:
        'Hei, vi klarer dessverre ikke å levere hos deg i dag som planlagt. '
        'MAVI tar kontakt for ny tid. Vi beklager ulempen. Mvh MAVI Logistikk',
  ),
  PartnerSmsTemplate(
    id: 'new_time_tomorrow',
    title: 'Ny leveringstid i morgen',
    body:
        'Hei, leveransen din er flyttet til i morgen. Sjåføren ringer 30 min før ankomst. '
        'Mvh MAVI Logistikk',
  ),
  PartnerSmsTemplate(
    id: 'access_issue',
    title: 'Trenger tilgang / portkode',
    body:
        'Hei! Sjåføren vår trenger tilgang til leveringsadressen (portkode, heis, etc.). '
        'Kan du svare med info? Mvh MAVI Logistikk',
  ),
  PartnerSmsTemplate(
    id: 'thanks_patience',
    title: 'Takk for tålmodigheten',
    body:
        'Hei, takk for tålmodigheten med forsinkelsen. Vi jobber for å levere til deg så snart som mulig. '
        'Mvh MAVI Logistikk',
  ),
];
