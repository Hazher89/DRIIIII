import '../permissions/access_keys.dart';
import 'route_url_sync.dart';

/// Kanoniske URL-stier for DriftPro web (bokmerker, refresh, deling).
abstract final class AppPaths {
  static const login = '/login';
  static const dashboard = '/';
  static const surveys = '/surveys';
  static const absence = '/fravaer';
  static const tickets = '/avvik';
  static const hms = '/hms';
  static const partners = '/partners';
  static const more = '/more';
  static const live = '/live';
  static const portal = '/portal';

  /// Partnerportal — eier
  static const portalOwnerTabs = [
    'oversikt',
    'oppsummering',
    'dokumenter',
    'ruter',
    'utleie',
    'moteter',
    'bilkontroll',
    'profil',
  ];

  /// Partnerportal — sjåfør
  static const portalDriverTabs = [
    'oversikt',
    'ruter',
    'dokumenter',
    'fri',
    'profil',
  ];

  static const partnersTabs = ['bedrifter', 'ruter', 'sms', 'utleie'];
  static const absenceTabs = ['dashboard', 'mine', 'godkjenn', 'team', 'roster'];
  static const equipmentTabs = ['oversikt', 'alle', 'truck', 'arkiv'];
  static const competenceTabs = ['kurs', 'dokumenter', 'oversikt'];
  static const riskTabs = ['risiko', 'interessepart'];
  static const employeeHubTabs = ['alle', 'venter', 'bursdager'];
  static const varslerTabs = ['sms', 'epost', 'audit', 'innstillinger'];

  static String withTab(String path, String? tab, {Map<String, String?> extra = const {}}) {
    return RouteUrlSync.build(path, {
      ...extra,
      if (tab != null && tab.isNotEmpty) 'tab': tab,
    });
  }

  static String portalPath({String? tab}) => withTab(portal, tab);

  static String partnersPath({String? tab}) => withTab(partners, tab);

  static String absencePath({String? tab}) => withTab(absence, tab);

  static String equipmentPath({String? tab}) => withTab(hmsUtstyr, tab);

  static String competencePath({String? tab}) => withTab(hmsKompetanse, tab);

  static String riskPath({String? tab}) => withTab(hmsRisiko, tab);

  static String employeeHubPath({String? tab}) => withTab(moreBrukergodkjenning, tab);

  static String varslerPath({String? tab, String? settingsTab}) {
    final extra = <String, String?>{};
    if (settingsTab != null && settingsTab.isNotEmpty) {
      extra['settings'] = settingsTab;
    }
    return withTab(moreVarsler, tab, extra: extra);
  }

  static String partnerDetailPath(String partnerId, {String? tab}) =>
      withTab('$partners/bedrift/$partnerId', tab);
  static const hmsAvvik = '/hms/avvik';
  static const hmsRisiko = '/hms/risiko';
  static const hmsRisikomatrise = '/hms/risikomatrise';
  static const hmsSja = '/hms/sja';
  static const hmsVernerunde = '/hms/vernerunde';
  static const hmsUtstyr = '/hms/utstyr';
  static const hmsKompetanse = '/hms/kompetanse';
  static const hmsDms = '/hms/dms';

  // Mer-meny undermoduler
  static const moreProfil = '/more/profil';
  static const moreAvdelinger = '/more/avdelinger';
  static const moreAnsatte = '/more/ansatte';
  static const moreOrganisasjonskart = '/more/organisasjonskart';
  static const morePartnere = '/more/partnere';
  static const morePersonalmappe = '/more/personalmappe';
  static const moreVarsler = '/more/varsler';
  static const moreUndersokelser = '/more/undersokelser';
  static const moreTilgangskontroll = '/more/tilgangskontroll';
  static const moreBrukergodkjenning = '/more/brukergodkjenning';
  static const moreInfoskjerm = '/more/infoskjerm';
  static const moreWhistleblowing = '/more/whistleblowing';
  static const moreDropbox = '/more/dropbox';
  static const moreHjelp = '/more/hjelp';
  static const morePersonvern = '/more/personvern';
  static const moreOm = '/more/om';

  /// Hovedfaner i [MainShell] — rekkefølge = bottom nav + skjult avvik-gren.
  static const shellTabs = <({String path, String access})>[
    (path: dashboard, access: AccessKeys.dashboard),
    (path: surveys, access: AccessKeys.surveys),
    (path: absence, access: AccessKeys.fravaer),
    (path: tickets, access: AccessKeys.avvik),
    (path: hms, access: AccessKeys.hms),
    (path: partners, access: AccessKeys.partners),
    (path: more, access: AccessKeys.more),
  ];

  static String? pathForAccess(String accessKey) {
    for (final t in shellTabs) {
      if (t.access == accessKey) return t.path;
    }
    return null;
  }

  static int? branchIndexForPath(String path) {
    final normalized = _normalize(path.split('?').first);
    if (normalized == dashboard) return 0;
    if (normalized.startsWith('$partners/')) return 5;
    for (var i = 1; i < shellTabs.length; i++) {
      final tabPath = _normalize(shellTabs[i].path);
      if (normalized == tabPath || normalized.startsWith('$tabPath/')) {
        return i;
      }
    }
    return null;
  }

  static String _normalize(String path) {
    if (path.isEmpty || path == '/') return dashboard;
    final p = path.endsWith('/') && path.length > 1 ? path.substring(0, path.length - 1) : path;
    return p.toLowerCase();
  }

  /// Leser sti fra nettleser ved cold start / refresh.
  static String initialLocationFromUri(Uri uri) {
    if (uri.queryParameters['dropbox'] == 'connected') {
      return '${AppPaths.moreDropbox}?dropbox=connected';
    }

    final track = uri.queryParameters['track']?.trim();
    if (track != null && track.isNotEmpty) return '/track/$track';

    final survey = uri.queryParameters['survey']?.trim() ??
        uri.queryParameters['s']?.trim();
    if (survey != null && survey.isNotEmpty) return '/s/$survey';

    var path = uri.path;
    if (path.isEmpty) path = dashboard;

    if (path.startsWith('/s/')) return path;

    final fragment = uri.fragment;
    if ((path == dashboard || path.isEmpty) && fragment.isNotEmpty) {
      final fragPath = fragment.split('?').first;
      if (fragPath.startsWith('/')) path = fragPath;
    }

    final view = uri.queryParameters['view']?.toLowerCase();
    if (view == 'online' || view == 'infoskjerm' || view == 'wallboard') {
      return live;
    }

    for (final p in [live, '/online', '/infoskjerm', '/wallboard']) {
      if (_normalize(path) == _normalize(p)) return live;
    }

    if (_normalize(path) == portal || path.startsWith('$portal/')) {
      return uri.hasQuery ? '$path?${uri.query}' : path;
    }

    if (path.startsWith('$hms/') || path.startsWith('$more/')) {
      return uri.hasQuery ? '$path?${uri.query}' : path;
    }

    if (branchIndexForPath(path) != null) {
      return uri.hasQuery ? '$path?${uri.query}' : path;
    }

    return dashboard;
  }

  static bool isPublicPath(String path) {
    final p = _normalize(path.split('?').first);
    return p.startsWith('/s/') || p.startsWith('/track/');
  }

  static String dmsPath({
    String? section,
    String? folderId,
    String? folderName,
  }) {
    final params = <String, String>{};
    if (section != null && section.isNotEmpty && section != 'home') {
      params['section'] = section;
    }
    if (folderId != null && folderId.isNotEmpty) {
      params['folder'] = folderId;
      if (folderName != null && folderName.isNotEmpty) {
        params['folderName'] = folderName;
      }
    }
    return Uri(path: hmsDms, queryParameters: params.isEmpty ? null : params).toString();
  }
}
