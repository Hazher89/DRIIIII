/// Offentlige URL-er for vegg-skjerm / infoskjerm (krever innlogging én gang).
class InfoskjermUrls {
  InfoskjermUrls._();

  /// Produksjon; erstattes av [origin] når appen kjører på web.
  static const String productionOrigin = 'https://drifpro.no';

  static String get origin {
    final o = Uri.base.origin;
    if (o.isNotEmpty && o != 'null' && !o.contains('localhost')) return o;
    if (o.contains('127.0.0.1') || o.contains('localhost')) return o;
    return productionOrigin;
  }

  /// Anbefalt lenke for TV/nettleser (2 min oppdatering).
  static String wallboard({int refreshSeconds = 120}) {
    final r = refreshSeconds.clamp(30, 900);
    return '$origin/?view=infoskjerm&refresh=$r';
  }

  static String wallboardAltPath({int refreshSeconds = 120}) {
    final r = refreshSeconds.clamp(30, 900);
    return '$origin/infoskjerm?refresh=$r';
  }

  static List<({String label, String url})> linksForAdmin({int refreshSeconds = 120}) => [
        (label: 'Anbefalt (query)', url: wallboard(refreshSeconds: refreshSeconds)),
        (label: 'Alternativ (/infoskjerm)', url: wallboardAltPath(refreshSeconds: refreshSeconds)),
        (label: 'Eldre (/online)', url: '$origin/?view=online&refresh=${refreshSeconds.clamp(30, 900)}'),
      ];
}
