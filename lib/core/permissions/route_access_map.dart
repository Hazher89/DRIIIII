import '../routing/app_paths.dart';
import 'access_actions.dart';
import 'access_area_catalog.dart';
import 'access_keys.dart';
import 'partner_access.dart';
import 'user_access.dart';

/// Krav for å åpne en rute.
class RouteAccessRequirement {
  final String areaId;
  final AccessAction action;
  final String? legacyAccessKey;
  /// Alternativ: minst én av disse legacy-nøklene (ELLER).
  final List<String>? anyOfLegacyKeys;
  /// Egendefinert sjekk (f.eks. partner-detalj / fane).
  final bool Function(UserAccess access)? customCheck;

  const RouteAccessRequirement({
    required this.areaId,
    this.action = AccessAction.view,
    this.legacyAccessKey,
    this.anyOfLegacyKeys,
    this.customCheck,
  });
}

/// Path/URI → tilgangskrav (deep links + faner).
class RouteAccessMap {
  RouteAccessMap._();

  static final Map<String, RouteAccessRequirement> _exact = {
    AppPaths.dashboard: const RouteAccessRequirement(
      areaId: 'dashboard',
      legacyAccessKey: AccessKeys.dashboard,
    ),
    AppPaths.surveys: const RouteAccessRequirement(
      areaId: 'surveys',
      legacyAccessKey: AccessKeys.surveys,
    ),
    AppPaths.absence: const RouteAccessRequirement(
      areaId: 'fravaer',
      legacyAccessKey: AccessKeys.fravaer,
    ),
    AppPaths.tickets: const RouteAccessRequirement(
      areaId: 'avvik',
      legacyAccessKey: AccessKeys.avvik,
    ),
    AppPaths.hms: const RouteAccessRequirement(
      areaId: 'hms',
      legacyAccessKey: AccessKeys.hms,
    ),
    AppPaths.hmsRisiko: const RouteAccessRequirement(
      areaId: 'hms.risiko',
      legacyAccessKey: AccessKeys.hmsRisikovurdering,
    ),
    AppPaths.hmsRisikomatrise: const RouteAccessRequirement(
      areaId: 'hms.risikomatrise',
      legacyAccessKey: AccessKeys.hmsRisikomatrise,
    ),
    AppPaths.hmsSja: const RouteAccessRequirement(
      areaId: 'hms.sja',
      legacyAccessKey: AccessKeys.hmsSja,
    ),
    AppPaths.hmsVernerunde: const RouteAccessRequirement(
      areaId: 'hms.vernerunde',
      legacyAccessKey: AccessKeys.hmsSikkerhetsrunde,
    ),
    AppPaths.hmsUtstyr: const RouteAccessRequirement(
      areaId: 'hms.utstyr',
      legacyAccessKey: AccessKeys.hmsUtstyr,
    ),
    AppPaths.hmsKompetanse: const RouteAccessRequirement(
      areaId: 'hms.kompetanse',
      legacyAccessKey: AccessKeys.hmsKompetanse,
    ),
    AppPaths.hmsOpplaering: const RouteAccessRequirement(
      areaId: 'hms.opplaering',
    ),
    AppPaths.hmsDms: const RouteAccessRequirement(
      areaId: 'hms.dokumenter',
      legacyAccessKey: AccessKeys.hmsDokumenter,
    ),
    AppPaths.hmsAvvik: const RouteAccessRequirement(
      areaId: 'avvik',
      legacyAccessKey: AccessKeys.avvik,
    ),
    AppPaths.partners: const RouteAccessRequirement(
      areaId: 'partners',
      legacyAccessKey: AccessKeys.partners,
    ),
    AppPaths.partnersChat: const RouteAccessRequirement(
      areaId: 'partners.chat',
      legacyAccessKey: AccessKeys.partners,
    ),
    AppPaths.stempling: const RouteAccessRequirement(
      areaId: 'stempling',
      legacyAccessKey: AccessKeys.stempling,
    ),
    AppPaths.uniform: const RouteAccessRequirement(
      areaId: 'uniform',
      legacyAccessKey: AccessKeys.uniformMonitor,
    ),
    AppPaths.more: const RouteAccessRequirement(
      areaId: 'more',
      legacyAccessKey: AccessKeys.more,
    ),
    AppPaths.moreProfil: const RouteAccessRequirement(
      areaId: 'more.profil',
      legacyAccessKey: AccessKeys.profil,
    ),
    AppPaths.moreAvdelinger: const RouteAccessRequirement(
      areaId: 'more.avdelinger',
      legacyAccessKey: AccessKeys.avdelinger,
    ),
    AppPaths.moreAnsatte: const RouteAccessRequirement(
      areaId: 'more.ansatte',
      legacyAccessKey: AccessKeys.ansatte,
    ),
    AppPaths.morePartnere: const RouteAccessRequirement(
      areaId: 'more.partnere',
      legacyAccessKey: AccessKeys.samarbeidspartnere,
    ),
    AppPaths.morePersonalmappe: const RouteAccessRequirement(
      areaId: 'more.personalmappe',
      legacyAccessKey: AccessKeys.personalmappe,
    ),
    AppPaths.moreVarsler: const RouteAccessRequirement(
      areaId: 'more.varsler',
      legacyAccessKey: AccessKeys.varsler,
    ),
    AppPaths.moreUndersokelser: const RouteAccessRequirement(
      areaId: 'more.undersokelser',
      legacyAccessKey: AccessKeys.undersokelser,
    ),
    AppPaths.moreTilgangskontroll: const RouteAccessRequirement(
      areaId: 'more.tilgangskontroll',
      legacyAccessKey: AccessKeys.tilgangskontroll,
    ),
    AppPaths.moreBrukergodkjenning: const RouteAccessRequirement(
      areaId: 'more.brukergodkjenning',
      legacyAccessKey: AccessKeys.brukergodkjenning,
    ),
    AppPaths.moreInfoskjerm: const RouteAccessRequirement(
      areaId: 'more.kiosk',
      legacyAccessKey: AccessKeys.kiosk,
    ),
    AppPaths.moreForside: const RouteAccessRequirement(
      areaId: 'more.forside',
      action: AccessAction.edit,
      legacyAccessKey: AccessKeys.forsideRedigering,
    ),
    AppPaths.moreWhistleblowing: const RouteAccessRequirement(
      areaId: 'more.whistleblowing',
      legacyAccessKey: AccessKeys.whistleblowing,
    ),
    AppPaths.moreDropbox: const RouteAccessRequirement(
      areaId: 'more.dropbox',
    ),
    AppPaths.moreVisionCameras: const RouteAccessRequirement(
      areaId: 'more.vision_cameras',
    ),
    AppPaths.moreVisionEvents: const RouteAccessRequirement(
      areaId: 'more.vision_events',
    ),
    AppPaths.moreHjelp: const RouteAccessRequirement(
      areaId: 'more',
      legacyAccessKey: AccessKeys.more,
    ),
    AppPaths.moreAssistent: const RouteAccessRequirement(
      areaId: 'more',
      legacyAccessKey: AccessKeys.more,
    ),
    AppPaths.morePersonvern: const RouteAccessRequirement(
      areaId: 'more',
      legacyAccessKey: AccessKeys.more,
    ),
    AppPaths.moreOm: const RouteAccessRequirement(
      areaId: 'more',
      legacyAccessKey: AccessKeys.more,
    ),
    AppPaths.moreOrganisasjonskart: const RouteAccessRequirement(
      areaId: 'more.ansatte',
      legacyAccessKey: AccessKeys.ansatte,
    ),
  };

  static final _partnerDetailPath =
      RegExp(r'^/partners/bedrift/[^/]+$', caseSensitive: false);

  /// Evaluer om [access] oppfyller [req].
  static bool isAllowed(UserAccess access, RouteAccessRequirement req) {
    if (req.customCheck != null) return req.customCheck!(access);
    if (access.canArea(req.areaId, req.action)) return true;
    if (req.legacyAccessKey != null && access.can(req.legacyAccessKey!)) {
      return true;
    }
    if (req.anyOfLegacyKeys != null && access.canAny(req.anyOfLegacyKeys!)) {
      return true;
    }
    return false;
  }

  /// True hvis URI ikke krever tilgang, eller brukeren har tilgang.
  static bool allowsUri(UserAccess access, Uri uri) {
    final req = requirementForUri(uri);
    if (req == null) return true;
    return isAllowed(access, req);
  }

  /// Krav for full URI (inkl. `?tab=` for partnere).
  static RouteAccessRequirement? requirementForUri(Uri uri) {
    final path = uri.path.isEmpty ? AppPaths.dashboard : uri.path;
    final tab = uri.queryParameters['tab']?.trim().toLowerCase();

    if (path == AppPaths.accessDenied ||
        path == AppPaths.login ||
        path == AppPaths.portal ||
        path.startsWith('${AppPaths.portal}/')) {
      return null;
    }

    if (_partnerDetailPath.hasMatch(path)) {
      return _partnerDetailRequirement(tab);
    }

    if (path == AppPaths.partners || path == AppPaths.morePartnere) {
      return _partnersHubTabRequirement(tab);
    }

    return requirementFor(path);
  }

  static RouteAccessRequirement _partnersHubTabRequirement(String? tab) {
    switch (tab) {
      case 'ruter':
        return RouteAccessRequirement(
          areaId: 'partners.fleet',
          legacyAccessKey: AccessKeys.fleetRuter,
          anyOfLegacyKeys: const [
            AccessKeys.fleetRuter,
            AccessKeys.partnersTabRuter,
            AccessKeys.partnersAdmin,
          ],
          customCheck: (a) => a.canPartnerRoutePlanning,
        );
      case 'sms':
        return RouteAccessRequirement(
          areaId: 'partners.tabs.sms',
          customCheck: (a) => a.canPartnersTabSms || a.canPartnersAdmin,
        );
      case 'bot-trekk':
        return RouteAccessRequirement(
          areaId: 'partners.tabs.bot_trekk',
          legacyAccessKey: AccessKeys.partnersTabBotTrekk,
          customCheck: (a) => a.canPartnersTabBotTrekk || a.canPartnersAdmin,
        );
      case 'utleie':
        return RouteAccessRequirement(
          areaId: 'partners.vehicle_rental',
          legacyAccessKey: AccessKeys.partnersVehicleRental,
          customCheck: (a) =>
              a.canPartnersVehicleRental ||
              a.canPartnerRoutePlanning ||
              a.canPartnersAdmin,
        );
      case 'bilkontroll':
        return RouteAccessRequirement(
          areaId: 'partners.tabs.bilkontroll',
          legacyAccessKey: AccessKeys.partnersTabBilkontroll,
          customCheck: (a) =>
              a.canPartnersTabBilkontroll ||
              a.canPartnersAdmin ||
              PartnerAccess.canOpenPartnersModule(a),
        );
      case 'bedrifter':
      case null:
      case '':
        return RouteAccessRequirement(
          areaId: 'partners',
          legacyAccessKey: AccessKeys.partners,
          customCheck: (a) => PartnerAccess.canOpenPartnersModule(a),
        );
      default:
        return RouteAccessRequirement(
          areaId: 'partners',
          legacyAccessKey: AccessKeys.partners,
          customCheck: (a) => PartnerAccess.canOpenPartnersModule(a),
        );
    }
  }

  static RouteAccessRequirement _partnerDetailRequirement(String? tab) {
    final key = _partnerDetailTabKey(tab);
    if (key != null) {
      return RouteAccessRequirement(
        areaId: 'partners',
        legacyAccessKey: key,
        customCheck: (a) {
          if (key == AccessKeys.partnersTabOppsummering) {
            return a.profile.isSuperAdmin;
          }
          return a.can(key);
        },
      );
    }
    return RouteAccessRequirement(
      areaId: 'partners',
      legacyAccessKey: AccessKeys.partners,
      customCheck: (a) => PartnerAccess.canOpenPartnerDetail(a),
    );
  }

  static String? _partnerDetailTabKey(String? tab) {
    if (tab == null || tab.isEmpty) return null;
    const map = <String, String>{
      'oversikt': AccessKeys.partnersTabOversikt,
      'bilkontroll': AccessKeys.partnersTabBilkontroll,
      'ruter': AccessKeys.partnersTabRuter,
      'dokumenter': AccessKeys.partnersTabDokumenter,
      'loyver': AccessKeys.partnersTabLoyver,
      'løyver': AccessKeys.partnersTabLoyver,
      'oppfolging': AccessKeys.partnersTabOppfolging,
      'oppfølging': AccessKeys.partnersTabOppfolging,
      'bot-trekk': AccessKeys.partnersTabBotTrekk,
      'bot_trekk': AccessKeys.partnersTabBotTrekk,
      'oppsummering': AccessKeys.partnersTabOppsummering,
      'fri': AccessKeys.partnersTabFri,
    };
    return map[tab];
  }

  /// Finn krav for [path] (uten query). Returnerer null hvis offentlig/ukjent.
  static RouteAccessRequirement? requirementFor(String path) {
    final normalized = path.split('?').first;
    if (normalized == AppPaths.login ||
        normalized == AppPaths.accessDenied ||
        normalized == AppPaths.portal ||
        normalized.startsWith('${AppPaths.portal}/')) {
      return null;
    }

    if (_partnerDetailPath.hasMatch(normalized)) {
      return _partnerDetailRequirement(null);
    }

    final exact = _exact[normalized];
    if (exact != null) return exact;

    final keys = _exact.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final key in keys) {
      if (key != '/' && normalized.startsWith('$key/')) {
        return _exact[key];
      }
    }

    for (final area in AccessAreaCatalog.areas) {
      final rp = area.routePath;
      if (rp == null || rp.isEmpty) continue;
      if (normalized == rp ||
          (rp != '/' && normalized.startsWith('$rp/'))) {
        return RouteAccessRequirement(
          areaId: area.id,
          legacyAccessKey: area.legacyViewKey,
        );
      }
    }
    return null;
  }
}
