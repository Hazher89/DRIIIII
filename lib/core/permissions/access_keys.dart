/// Alle sider og funksjoner i DriftPro (lagres i `profiles.access_settings`).
class AccessKeys {
  AccessKeys._();

  // ── Hovednavigasjon ────────────────────────────────────────────────────────
  static const dashboard = 'dashboard';
  static const surveys = 'surveys';
  static const fravaer = 'fravaer';
  static const avvik = 'avvik';
  static const hms = 'hms';
  static const partners = 'partners';
  static const more = 'more';

  // ── Mer-meny ───────────────────────────────────────────────────────────────
  static const avdelinger = 'avdelinger';
  static const ansatte = 'ansatte';
  static const personalmappe = 'personalmappe';
  static const varsler = 'varsler';
  static const undersokelser = 'undersokelser';
  static const whistleblowing = 'whistleblowing';
  static const kiosk = 'kiosk';
  static const tilgangskontroll = 'tilgangskontroll';
  static const brukergodkjenning = 'brukergodkjenning';
  static const samarbeidspartnere = 'samarbeidspartnere';
  static const profil = 'profil';
  static const appInnstillinger = 'app_innstillinger';

  // ── Fravær & ferie ─────────────────────────────────────────────────────────
  static const fravaerGodkjenn = 'fravaer_godkjenn';
  static const fravaerRegistrerAndre = 'fravaer_registrer_andre';
  static const ferieAdmin = 'ferie_admin';

  // ── Avvik ──────────────────────────────────────────────────────────────────
  static const avvikGodkjenn = 'avvik_godkjenn';
  static const avvikKoordinere = 'avvik_koordinere';
  static const avvikAdmin = 'avvik_admin';

  // ── HMS-moduler ────────────────────────────────────────────────────────────
  static const hmsRisikovurdering = 'hms_risikovurdering';
  static const hmsSja = 'hms_sja';
  static const hmsSikkerhetsrunde = 'hms_sikkerhetsrunde';
  static const hmsRisikomatrise = 'hms_risikomatrise';
  static const hmsUtstyr = 'hms_utstyr';
  static const hmsUtstyrAdmin = 'hms_utstyr_admin';
  static const hmsUtstyrService = 'hms_utstyr_service';
  static const hmsUtstyrServicehefte = 'hms_utstyr_servicehefte';
  static const hmsKompetanse = 'hms_kompetanse';
  static const hmsDokumenter = 'hms_dokumenter';

  // ── Undersøkelser ─────────────────────────────────────────────────────────
  static const surveyBygge = 'survey_bygge';
  static const surveyResultater = 'survey_resultater';

  // ── Samarbeidspartnere / ruter ─────────────────────────────────────────────
  static const partnersAdmin = 'partners_admin';
  static const fleetRuter = 'fleet_ruter';
  static const partnersCreate = 'partners_create';
  static const partnersDelete = 'partners_delete';
  static const partnersEdit = 'partners_edit';
  static const partnersVehicleRental = 'partners_vehicle_rental';
  static const partnersVehicleRentalApprove = 'partners_vehicle_rental_approve';

  /// Faner i bedriftsdetalj (samarbeidspartner).
  static const partnersTabOversikt = 'partners_tab_oversikt';
  static const partnersTabBilkontroll = 'partners_tab_bilkontroll';
  static const partnersTabRuter = 'partners_tab_ruter';
  static const partnersTabDokumenter = 'partners_tab_dokumenter';
  static const partnersTabLoyver = 'partners_tab_loyver';
  static const partnersTabOppfolging = 'partners_tab_oppfolging';
  static const partnersTabOppsummering = 'partners_tab_oppsummering';
  static const partnersTabFri = 'partners_tab_fri';
  static const partnersTabBotTrekk = 'partners_tab_bot_trekk';

  static const partnerDetailTabKeys = [
    partnersTabOversikt,
    partnersTabBilkontroll,
    partnersTabRuter,
    partnersTabDokumenter,
    partnersTabLoyver,
    partnersTabOppfolging,
    partnersTabOppsummering,
    partnersTabFri,
    partnersTabBotTrekk,
  ];

  // ── Administrasjon ─────────────────────────────────────────────────────────
  static const ansatteRediger = 'ansatte_rediger';
  static const avdelingerRediger = 'avdelinger_rediger';

  static const allKeys = [
    dashboard,
    surveys,
    fravaer,
    avvik,
    hms,
    partners,
    more,
    avdelinger,
    ansatte,
    personalmappe,
    varsler,
    undersokelser,
    whistleblowing,
    kiosk,
    tilgangskontroll,
    brukergodkjenning,
    samarbeidspartnere,
    profil,
    appInnstillinger,
    fravaerGodkjenn,
    fravaerRegistrerAndre,
    ferieAdmin,
    avvikGodkjenn,
    avvikKoordinere,
    avvikAdmin,
    hmsRisikovurdering,
    hmsSja,
    hmsSikkerhetsrunde,
    hmsRisikomatrise,
    hmsUtstyr,
    hmsUtstyrAdmin,
    hmsUtstyrService,
    hmsUtstyrServicehefte,
    hmsKompetanse,
    hmsDokumenter,
    surveyBygge,
    surveyResultater,
    partnersAdmin,
    fleetRuter,
    partnersCreate,
    partnersDelete,
    partnersEdit,
    partnersTabOversikt,
    partnersTabBilkontroll,
    partnersTabRuter,
    partnersTabDokumenter,
    partnersTabLoyver,
    partnersTabOppfolging,
    partnersTabOppsummering,
    partnersTabFri,
    partnersTabBotTrekk,
    ansatteRediger,
    avdelingerRediger,
  ];

  static Map<String, dynamic> allOff() =>
      {for (final k in allKeys) k: false};

  static Map<String, dynamic> allOn() => {for (final k in allKeys) k: true};

  static String label(String key) => _labels[key] ?? key;

  static const _labels = {
    dashboard: 'Dashboard / forsiden',
    surveys: 'Undersøkelser (fane)',
    fravaer: 'Fravær & ferie (modul)',
    avvik: 'Avvik (modul)',
    hms: 'HMS (hovedmodul)',
    partners: 'Samarbeidspartnere (fane)',
    more: 'Mer-meny',
    avdelinger: 'Avdelinger',
    ansatte: 'Ansatte',
    personalmappe: 'Personalmappe / DMS',
    varsler: 'Varsler & varselinnstillinger',
    undersokelser: 'Undersøkelser (meny)',
    whistleblowing: 'Anonym anmeldelse',
    kiosk: 'Infoskjerm',
    tilgangskontroll: 'Tilgangskontroll',
    brukergodkjenning: 'Godkjenne nye brukere',
    samarbeidspartnere: 'Samarbeidspartnere (meny)',
    profil: 'Min profil',
    appInnstillinger: 'Appinnstillinger',
    fravaerGodkjenn: 'Godkjenne fravær/ferie',
    fravaerRegistrerAndre: 'Registrere fravær for andre',
    ferieAdmin: 'Ferieadministrasjon',
    avvikGodkjenn: 'Godkjenne / behandle avvik',
    avvikKoordinere: 'Avvik kontrollsenter',
    avvikAdmin: 'Avvik admin-dashboard',
    hmsRisikovurdering: 'Risikovurdering',
    hmsSja: 'SJA',
    hmsSikkerhetsrunde: 'Sikkerhetsrunder',
    hmsRisikomatrise: 'Risikomatrise',
    hmsUtstyr: 'Maskiner & utstyr (se)',
    hmsUtstyrAdmin: 'Utstyr – admin & innstillinger',
    hmsUtstyrService: 'Utstyr – registrere service/vann',
    hmsUtstyrServicehefte: 'Utstyr – servicehefter (ansatt)',
    hmsKompetanse: 'Kompetanse & kurs',
    hmsDokumenter: 'HMS-dokumenter',
    surveyBygge: 'Bygge / redigere undersøkelser',
    surveyResultater: 'Se undersøkelsesresultater',
    partnersAdmin: 'Administrere samarbeidspartnere (full)',
    fleetRuter: 'Ruter & planlegging (hovedfane i Samarbeidspartnere)',
    partnersCreate: 'Opprette nye samarbeidspartnere',
    partnersDelete: 'Slette samarbeidspartnere',
    partnersEdit: 'Redigere partnerdata (lagre/endre)',
    partnersVehicleRental: 'Bilutleie — opprette og følge opp',
    partnersVehicleRentalApprove: 'Bilutleie — godkjenne utleie og retur',
    partnersTabOversikt: 'Partner – Oversikt-fane',
    partnersTabBilkontroll: 'Partner – Bilkontroll-fane',
    partnersTabRuter: 'Ruter & planlegging (inkl. hovedfane + ruter per bedrift)',
    partnersTabDokumenter: 'Partner – Dokumenter-fane',
    partnersTabLoyver: 'Partner – Løyver-fane',
    partnersTabOppfolging: 'Partner – Oppfølging (møter/revisjon/SMS)',
    partnersTabOppsummering: 'Partner – Oppsummering-fane',
    partnersTabFri: 'Partner – Fri-fane',
    partnersTabBotTrekk: 'Partner – Bot/Trekk-fane',
    ansatteRediger: 'Redigere ansatte og tilganger',
    avdelingerRediger: 'Opprette / redigere avdelinger',
  };

  static String description(String key) => _descriptions[key] ?? '';

  static const _descriptions = {
    dashboard: 'Oversikt, snarveier og varsler',
    fravaer: 'Egen fravær/ferie. Uten leder-tilgang: kun egne data',
    avvik: 'Melde og se egne avvik',
    hms: 'Åpne HMS-modulen (undermoduler styres separat)',
    fravaerGodkjenn: 'Godkjenne teamets fravær (kun egen avdeling)',
    avvikGodkjenn: 'Behandle avvik i egen avdeling',
    ferieAdmin: 'Tildele feriedager for hele bedriften',
    ansatteRediger: 'Endre roller og tilganger for andre',
    brukergodkjenning: 'Kun superadmin bør ha denne',
    varsler:
        'Varselsenter under Mer, varselinnstillinger og feilede varsler. '
        'Uavhengig av tilgang til Samarbeidspartnere.',
  };
}
