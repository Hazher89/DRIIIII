import '../permissions/access_keys.dart';

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

  // HMS undermoduler
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
