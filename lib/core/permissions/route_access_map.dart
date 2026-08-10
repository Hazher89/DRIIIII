import '../routing/app_paths.dart';
import 'access_actions.dart';
import 'access_area_catalog.dart';
import 'access_keys.dart';

/// Krav for å åpne en rute.
class RouteAccessRequirement {
  final String areaId;
  final AccessAction action;
  final String? legacyAccessKey;

  const RouteAccessRequirement({
    required this.areaId,
    this.action = AccessAction.view,
    this.legacyAccessKey,
  });
}

/// Path → tilgangskrav (deep links).
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
    AppPaths.moreWhistleblowing: const RouteAccessRequirement(
      areaId: 'more.whistleblowing',
      legacyAccessKey: AccessKeys.whistleblowing,
    ),
    AppPaths.moreDropbox: const RouteAccessRequirement(
      areaId: 'more.dropbox',
    ),
    AppPaths.moreGmStoro: const RouteAccessRequirement(
      areaId: 'more.gm_storo',
    ),
    AppPaths.moreVisionCameras: const RouteAccessRequirement(
      areaId: 'more.vision_cameras',
    ),
    AppPaths.moreVisionEvents: const RouteAccessRequirement(
      areaId: 'more.vision_events',
    ),
  };

  /// Finn krav for [path] (uten query). Returnerer null hvis offentlig/ukjent.
  static RouteAccessRequirement? requirementFor(String path) {
    final normalized = path.split('?').first;
    if (normalized == AppPaths.login ||
        normalized == AppPaths.portal ||
        normalized.startsWith('${AppPaths.portal}/')) {
      return null;
    }
    final exact = _exact[normalized];
    if (exact != null) return exact;

    // Prefix match for nested routes (longest first).
    final keys = _exact.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final key in keys) {
      if (key != '/' && normalized.startsWith('$key/')) {
        return _exact[key];
      }
    }

    // Catalog routePath fallback
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
