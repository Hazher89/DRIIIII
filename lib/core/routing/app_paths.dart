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

  /// Hovedfaner i [MainShell] — rekkefølge = bottom nav.
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
    final normalized = _normalize(path);
    for (var i = 0; i < shellTabs.length; i++) {
      if (_normalize(shellTabs[i].path) == normalized) return i;
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

    if (branchIndexForPath(path) != null) return _normalize(path);

    return dashboard;
  }

  static bool isPublicPath(String path) {
    final p = _normalize(path);
    return p.startsWith('/s/') || p.startsWith('/track/');
  }
}
