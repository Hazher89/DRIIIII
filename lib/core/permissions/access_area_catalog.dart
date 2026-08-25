import 'access_actions.dart';
import 'access_keys.dart';

/// Definisjon av ett tilgangsområde (fane / side / funksjon).
class AccessAreaDef {
  final String id;
  final String title;
  final String? subtitle;
  final String? parentId;
  final Set<AccessAction> actions;
  final String? routePath;
  /// Gammel bool-nøkkel som tilsvarer [AccessAction.view] (v1-kompatibilitet).
  final String? legacyViewKey;

  const AccessAreaDef({
    required this.id,
    required this.title,
    this.subtitle,
    this.parentId,
    this.actions = const {AccessAction.view},
    this.routePath,
    this.legacyViewKey,
  });

  bool supports(AccessAction a) => actions.contains(a);
}

/// Komplett tre av DriftPro-tilgangsområder (v2).
class AccessAreaCatalog {
  AccessAreaCatalog._();

  static const viewOnly = {AccessAction.view};
  static const viewCreate = {AccessAction.view, AccessAction.create};
  static const crud = {
    AccessAction.view,
    AccessAction.create,
    AccessAction.edit,
    AccessAction.delete,
  };
  static const crudApprove = {
    AccessAction.view,
    AccessAction.create,
    AccessAction.edit,
    AccessAction.delete,
    AccessAction.approve,
  };
  static const viewEdit = {AccessAction.view, AccessAction.edit};
  static const viewApprove = {AccessAction.view, AccessAction.approve};
  static const viewCreateEdit = {
    AccessAction.view,
    AccessAction.create,
    AccessAction.edit,
  };

  static const areas = <AccessAreaDef>[
    // ── Shell ───────────────────────────────────────────────────────────────
    AccessAreaDef(
      id: 'dashboard',
      title: 'Dashboard',
      routePath: '/',
      legacyViewKey: AccessKeys.dashboard,
    ),
    AccessAreaDef(
      id: 'surveys',
      title: 'Undersøkelser (fane)',
      actions: viewCreateEdit,
      routePath: '/surveys',
      legacyViewKey: AccessKeys.surveys,
    ),
    AccessAreaDef(
      id: 'surveys.build',
      title: 'Bygge / redigere undersøkelser',
      parentId: 'surveys',
      actions: viewCreateEdit,
      legacyViewKey: AccessKeys.surveyBygge,
    ),
    AccessAreaDef(
      id: 'surveys.results',
      title: 'Se undersøkelsesresultater',
      parentId: 'surveys',
      legacyViewKey: AccessKeys.surveyResultater,
    ),
    AccessAreaDef(
      id: 'fravaer',
      title: 'Fravær & ferie',
      actions: crudApprove,
      routePath: '/fravaer',
      legacyViewKey: AccessKeys.fravaer,
    ),
    AccessAreaDef(
      id: 'fravaer.mine',
      title: 'Mine søknader',
      parentId: 'fravaer',
      actions: viewCreate,
    ),
    AccessAreaDef(
      id: 'fravaer.team',
      title: 'Team / avdeling',
      parentId: 'fravaer',
    ),
    AccessAreaDef(
      id: 'fravaer.godkjenn',
      title: 'Godkjenne fravær/ferie',
      parentId: 'fravaer',
      actions: viewApprove,
      legacyViewKey: AccessKeys.fravaerGodkjenn,
    ),
    AccessAreaDef(
      id: 'fravaer.registrer_andre',
      title: 'Registrere fravær for andre',
      parentId: 'fravaer',
      actions: viewCreate,
      legacyViewKey: AccessKeys.fravaerRegistrerAndre,
    ),
    AccessAreaDef(
      id: 'fravaer.ferie_admin',
      title: 'Ferieadministrasjon',
      parentId: 'fravaer',
      actions: viewEdit,
      legacyViewKey: AccessKeys.ferieAdmin,
    ),
    AccessAreaDef(
      id: 'avvik',
      title: 'Avvik',
      actions: crudApprove,
      routePath: '/avvik',
      legacyViewKey: AccessKeys.avvik,
    ),
    AccessAreaDef(
      id: 'avvik.nytt',
      title: 'Opprette avvik',
      parentId: 'avvik',
      actions: viewCreate,
    ),
    AccessAreaDef(
      id: 'avvik.behandle',
      title: 'Behandle / godkjenne avvik',
      parentId: 'avvik',
      actions: viewApprove,
      legacyViewKey: AccessKeys.avvikGodkjenn,
    ),
    AccessAreaDef(
      id: 'avvik.koordinere',
      title: 'Avvik kontrollsenter',
      parentId: 'avvik',
      actions: viewEdit,
      legacyViewKey: AccessKeys.avvikKoordinere,
    ),
    AccessAreaDef(
      id: 'avvik.admin',
      title: 'Avvik admin-dashboard',
      parentId: 'avvik',
      actions: viewEdit,
      legacyViewKey: AccessKeys.avvikAdmin,
    ),
    AccessAreaDef(
      id: 'hms',
      title: 'HMS',
      actions: viewOnly,
      routePath: '/hms',
      legacyViewKey: AccessKeys.hms,
    ),
    AccessAreaDef(
      id: 'hms.risiko',
      title: 'Risikovurdering',
      parentId: 'hms',
      actions: crud,
      routePath: '/hms/risiko',
      legacyViewKey: AccessKeys.hmsRisikovurdering,
    ),
    AccessAreaDef(
      id: 'hms.sja',
      title: 'SJA',
      parentId: 'hms',
      actions: crud,
      routePath: '/hms/sja',
      legacyViewKey: AccessKeys.hmsSja,
    ),
    AccessAreaDef(
      id: 'hms.vernerunde',
      title: 'Sikkerhetsrunder',
      parentId: 'hms',
      actions: crud,
      routePath: '/hms/vernerunde',
      legacyViewKey: AccessKeys.hmsSikkerhetsrunde,
    ),
    AccessAreaDef(
      id: 'hms.risikomatrise',
      title: 'Risikomatrise',
      parentId: 'hms',
      actions: viewEdit,
      routePath: '/hms/risikomatrise',
      legacyViewKey: AccessKeys.hmsRisikomatrise,
    ),
    AccessAreaDef(
      id: 'hms.utstyr',
      title: 'Maskiner & utstyr',
      parentId: 'hms',
      actions: crud,
      routePath: '/hms/utstyr',
      legacyViewKey: AccessKeys.hmsUtstyr,
    ),
    AccessAreaDef(
      id: 'hms.utstyr.admin',
      title: 'Utstyr – admin',
      parentId: 'hms.utstyr',
      actions: viewEdit,
      legacyViewKey: AccessKeys.hmsUtstyrAdmin,
    ),
    AccessAreaDef(
      id: 'hms.utstyr.service',
      title: 'Utstyr – registrere service',
      parentId: 'hms.utstyr',
      actions: viewCreate,
      legacyViewKey: AccessKeys.hmsUtstyrService,
    ),
    AccessAreaDef(
      id: 'hms.utstyr.servicehefte',
      title: 'Utstyr – servicehefter',
      parentId: 'hms.utstyr',
      legacyViewKey: AccessKeys.hmsUtstyrServicehefte,
    ),
    AccessAreaDef(
      id: 'hms.kompetanse',
      title: 'Kompetanse & kurs',
      parentId: 'hms',
      actions: crud,
      routePath: '/hms/kompetanse',
      legacyViewKey: AccessKeys.hmsKompetanse,
    ),
    AccessAreaDef(
      id: 'hms.dokumenter',
      title: 'HMS-dokumenter',
      parentId: 'hms',
      actions: crud,
      routePath: '/hms/dms',
      legacyViewKey: AccessKeys.hmsDokumenter,
    ),
    AccessAreaDef(
      id: 'hms.opplaering',
      title: 'Opplæring / SOP',
      parentId: 'hms',
      routePath: '/hms/opplaering',
    ),
    AccessAreaDef(
      id: 'uniform',
      title: 'Uniform-monitor',
      actions: viewEdit,
      routePath: '/uniform',
      legacyViewKey: AccessKeys.uniformMonitor,
    ),
    AccessAreaDef(
      id: 'uniform.admin',
      title: 'Uniform – kamera og innstillinger',
      parentId: 'uniform',
      actions: viewEdit,
      legacyViewKey: AccessKeys.uniformMonitorAdmin,
    ),
    AccessAreaDef(
      id: 'partners',
      title: 'Samarbeidspartnere',
      actions: crudApprove,
      routePath: '/partners',
      legacyViewKey: AccessKeys.partners,
    ),
    AccessAreaDef(
      id: 'partners.create',
      title: 'Opprette samarbeidspartnere',
      parentId: 'partners',
      actions: viewCreate,
      legacyViewKey: AccessKeys.partnersCreate,
    ),
    AccessAreaDef(
      id: 'partners.edit',
      title: 'Redigere partnerdata',
      parentId: 'partners',
      actions: viewEdit,
      legacyViewKey: AccessKeys.partnersEdit,
    ),
    AccessAreaDef(
      id: 'partners.delete',
      title: 'Slette samarbeidspartnere',
      parentId: 'partners',
      actions: {AccessAction.view, AccessAction.delete},
      legacyViewKey: AccessKeys.partnersDelete,
    ),
    AccessAreaDef(
      id: 'partners.admin',
      title: 'Full partneradministrasjon',
      parentId: 'partners',
      actions: crud,
      legacyViewKey: AccessKeys.partnersAdmin,
    ),
    AccessAreaDef(
      id: 'partners.fleet',
      title: 'Ruter & planlegging',
      parentId: 'partners',
      actions: viewCreateEdit,
      legacyViewKey: AccessKeys.fleetRuter,
    ),
    AccessAreaDef(
      id: 'partners.vehicle_rental',
      title: 'Bilutleie',
      parentId: 'partners',
      actions: crudApprove,
      legacyViewKey: AccessKeys.partnersVehicleRental,
    ),
    AccessAreaDef(
      id: 'partners.vehicle_rental.approve',
      title: 'Bilutleie – godkjenne',
      parentId: 'partners.vehicle_rental',
      actions: viewApprove,
      legacyViewKey: AccessKeys.partnersVehicleRentalApprove,
    ),
    AccessAreaDef(
      id: 'partners.tabs.oversikt',
      title: 'Partnerfane – Oversikt',
      parentId: 'partners',
      legacyViewKey: AccessKeys.partnersTabOversikt,
    ),
    AccessAreaDef(
      id: 'partners.tabs.ruter',
      title: 'Partnerfane – Ruter',
      parentId: 'partners',
      legacyViewKey: AccessKeys.partnersTabRuter,
    ),
    AccessAreaDef(
      id: 'partners.tabs.bilkontroll',
      title: 'Partnerfane – Bilkontroll',
      parentId: 'partners',
      actions: crud,
      legacyViewKey: AccessKeys.partnersTabBilkontroll,
    ),
    AccessAreaDef(
      id: 'partners.tabs.dokumenter',
      title: 'Partnerfane – Dokumenter',
      parentId: 'partners',
      actions: crud,
      legacyViewKey: AccessKeys.partnersTabDokumenter,
    ),
    AccessAreaDef(
      id: 'partners.tabs.loyver',
      title: 'Partnerfane – Løyver',
      parentId: 'partners',
      actions: crud,
      legacyViewKey: AccessKeys.partnersTabLoyver,
    ),
    AccessAreaDef(
      id: 'partners.tabs.oppfolging',
      title: 'Partnerfane – Oppfølging',
      parentId: 'partners',
      actions: crud,
      legacyViewKey: AccessKeys.partnersTabOppfolging,
    ),
    AccessAreaDef(
      id: 'partners.tabs.sms',
      title: 'Partnerfane – SMS',
      parentId: 'partners',
      actions: viewCreate,
    ),
    AccessAreaDef(
      id: 'partners.tabs.bot_trekk',
      title: 'Partnerfane – Bot/Trekk',
      parentId: 'partners',
      actions: crudApprove,
      legacyViewKey: AccessKeys.partnersTabBotTrekk,
    ),
    AccessAreaDef(
      id: 'partners.tabs.oppsummering',
      title: 'Partnerfane – Oppsummering',
      parentId: 'partners',
      legacyViewKey: AccessKeys.partnersTabOppsummering,
    ),
    AccessAreaDef(
      id: 'partners.tabs.fri',
      title: 'Partnerfane – Fri',
      parentId: 'partners',
      actions: viewEdit,
      legacyViewKey: AccessKeys.partnersTabFri,
    ),
    AccessAreaDef(
      id: 'stempling',
      title: 'Stempling',
      actions: viewEdit,
      routePath: '/stempling',
      legacyViewKey: AccessKeys.stempling,
    ),
    AccessAreaDef(
      id: 'stempling.admin',
      title: 'Stempling – oversikt/timeliste',
      parentId: 'stempling',
      actions: viewEdit,
      legacyViewKey: AccessKeys.stemplingAdmin,
    ),
    AccessAreaDef(
      id: 'stempling.mobile',
      title: 'Stempling – mobil/nett',
      parentId: 'stempling',
      legacyViewKey: AccessKeys.stemplingMobile,
    ),
    AccessAreaDef(
      id: 'stempling.innstillinger',
      title: 'Stempling – kiosk-innstillinger',
      parentId: 'stempling',
      actions: viewEdit,
      legacyViewKey: AccessKeys.stemplingInnstillinger,
    ),
    AccessAreaDef(
      id: 'more',
      title: 'Mer-meny',
      routePath: '/more',
      legacyViewKey: AccessKeys.more,
    ),
    AccessAreaDef(
      id: 'more.profil',
      title: 'Min profil',
      parentId: 'more',
      routePath: '/more/profil',
      legacyViewKey: AccessKeys.profil,
    ),
    AccessAreaDef(
      id: 'more.app_innstillinger',
      title: 'Appinnstillinger',
      parentId: 'more',
      actions: viewEdit,
      legacyViewKey: AccessKeys.appInnstillinger,
    ),
    AccessAreaDef(
      id: 'more.avdelinger',
      title: 'Avdelinger',
      parentId: 'more',
      actions: crud,
      routePath: '/more/avdelinger',
      legacyViewKey: AccessKeys.avdelinger,
    ),
    AccessAreaDef(
      id: 'more.ansatte',
      title: 'Ansatte',
      parentId: 'more',
      actions: crud,
      routePath: '/more/ansatte',
      legacyViewKey: AccessKeys.ansatte,
    ),
    AccessAreaDef(
      id: 'more.personalmappe',
      title: 'Personalmappe / DMS',
      parentId: 'more',
      actions: crud,
      routePath: '/more/personalmappe',
      legacyViewKey: AccessKeys.personalmappe,
    ),
    AccessAreaDef(
      id: 'more.varsler',
      title: 'Varsler & varselinnstillinger',
      parentId: 'more',
      actions: viewEdit,
      routePath: '/more/varsler',
      legacyViewKey: AccessKeys.varsler,
    ),
    AccessAreaDef(
      id: 'more.undersokelser',
      title: 'Undersøkelser (meny)',
      parentId: 'more',
      routePath: '/more/undersokelser',
      legacyViewKey: AccessKeys.undersokelser,
    ),
    AccessAreaDef(
      id: 'more.whistleblowing',
      title: 'Anonym anmeldelse',
      parentId: 'more',
      actions: viewCreate,
      routePath: '/more/whistleblowing',
      legacyViewKey: AccessKeys.whistleblowing,
    ),
    AccessAreaDef(
      id: 'more.kiosk',
      title: 'Infoskjerm',
      parentId: 'more',
      routePath: '/more/infoskjerm',
      legacyViewKey: AccessKeys.kiosk,
    ),
    AccessAreaDef(
      id: 'more.partnere',
      title: 'Samarbeidspartnere (meny)',
      parentId: 'more',
      routePath: '/more/partnere',
      legacyViewKey: AccessKeys.samarbeidspartnere,
    ),
    AccessAreaDef(
      id: 'more.tilgangskontroll',
      title: 'Tilgangskontroll',
      parentId: 'more',
      actions: viewEdit,
      routePath: '/more/tilgangskontroll',
      legacyViewKey: AccessKeys.tilgangskontroll,
    ),
    AccessAreaDef(
      id: 'more.brukergodkjenning',
      title: 'Godkjenne nye brukere',
      parentId: 'more',
      actions: viewApprove,
      routePath: '/more/brukergodkjenning',
      legacyViewKey: AccessKeys.brukergodkjenning,
    ),
    AccessAreaDef(
      id: 'more.dropbox',
      title: 'Fillagring (Dropbox)',
      parentId: 'more',
      actions: viewEdit,
      routePath: '/more/dropbox',
    ),
    AccessAreaDef(
      id: 'more.vision_cameras',
      title: 'Kameraer',
      parentId: 'more',
      actions: viewEdit,
      routePath: '/more/vision-cameras',
    ),
    AccessAreaDef(
      id: 'more.vision_events',
      title: 'Kamerahendelser',
      parentId: 'more',
      routePath: '/more/vision-events',
    ),
    AccessAreaDef(
      id: 'admin.ansatte_rediger',
      title: 'Redigere ansatte og tilganger',
      parentId: 'more.ansatte',
      actions: viewEdit,
      legacyViewKey: AccessKeys.ansatteRediger,
    ),
    AccessAreaDef(
      id: 'admin.avdelinger_rediger',
      title: 'Opprette / redigere avdelinger',
      parentId: 'more.avdelinger',
      actions: viewCreateEdit,
      legacyViewKey: AccessKeys.avdelingerRediger,
    ),
  ];

  static final Map<String, AccessAreaDef> byId = {
    for (final a in areas) a.id: a,
  };

  static List<AccessAreaDef> childrenOf(String? parentId) =>
      areas.where((a) => a.parentId == parentId).toList();

  static List<AccessAreaDef> get roots => childrenOf(null);

  static String? parentOf(String areaId) => byId[areaId]?.parentId;

  static List<String> ancestors(String areaId) {
    final out = <String>[];
    var cur = parentOf(areaId);
    while (cur != null) {
      out.add(cur);
      cur = parentOf(cur);
    }
    return out;
  }

  static List<String> descendants(String areaId) {
    final out = <String>[];
    void walk(String id) {
      for (final c in childrenOf(id)) {
        out.add(c.id);
        walk(c.id);
      }
    }

    walk(areaId);
    return out;
  }

  /// Legacy bool-nøkkel → (area, action) for v1-kompatibilitet.
  static final Map<String, ({String area, AccessAction action})> legacyKeyMap =
      () {
    final m = <String, ({String area, AccessAction action})>{};
    for (final a in areas) {
      final lk = a.legacyViewKey;
      if (lk != null) {
        m[lk] = (area: a.id, action: AccessAction.view);
      }
    }
    // Explicit action mappings from old specialized keys.
    m[AccessKeys.fravaerGodkjenn] =
        (area: 'fravaer', action: AccessAction.approve);
    m[AccessKeys.fravaerRegistrerAndre] =
        (area: 'fravaer.registrer_andre', action: AccessAction.create);
    m[AccessKeys.ferieAdmin] =
        (area: 'fravaer.ferie_admin', action: AccessAction.edit);
    m[AccessKeys.avvikGodkjenn] =
        (area: 'avvik', action: AccessAction.approve);
    m[AccessKeys.avvikKoordinere] =
        (area: 'avvik.koordinere', action: AccessAction.edit);
    m[AccessKeys.avvikAdmin] =
        (area: 'avvik.admin', action: AccessAction.edit);
    m[AccessKeys.ansatteRediger] =
        (area: 'admin.ansatte_rediger', action: AccessAction.edit);
    m[AccessKeys.avdelingerRediger] =
        (area: 'admin.avdelinger_rediger', action: AccessAction.edit);
    m[AccessKeys.partnersCreate] =
        (area: 'partners', action: AccessAction.create);
    m[AccessKeys.partnersEdit] =
        (area: 'partners', action: AccessAction.edit);
    m[AccessKeys.partnersDelete] =
        (area: 'partners', action: AccessAction.delete);
    m[AccessKeys.partnersVehicleRentalApprove] =
        (area: 'partners.vehicle_rental', action: AccessAction.approve);
    m[AccessKeys.surveyBygge] =
        (area: 'surveys.build', action: AccessAction.edit);
    m[AccessKeys.brukergodkjenning] =
        (area: 'more.brukergodkjenning', action: AccessAction.approve);
    return m;
  }();
}
