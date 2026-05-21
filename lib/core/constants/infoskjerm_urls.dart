import '../config/app_origin.dart';

/// Offentlige URL-er for vegg-skjerm / infoskjerm (krever innlogging én gang).
class InfoskjermUrls {
  InfoskjermUrls._();

  static String get origin {
    final o = Uri.base.origin;
    if (o.isNotEmpty && o != 'null' && !o.contains('localhost')) return o;
    if (o.contains('127.0.0.1') || o.contains('localhost')) return o;
    return kProductionOrigin;
  }

  /// Anbefalt lenke for TV/nettleser (2 min oppdatering som standard).
  static String wallboard({int? refreshSeconds}) {
    if (refreshSeconds == null) return '$origin/live';
    final r = refreshSeconds.clamp(30, 900);
    return '$origin/live?refresh=$r';
  }

  static List<({String label, String url})> linksForAdmin({int refreshSeconds = 120}) => [
        (label: 'Infoskjerm', url: wallboard()),
        (
          label: 'Med annen oppdatering (${refreshSeconds.clamp(30, 900)} sek)',
          url: wallboard(refreshSeconds: refreshSeconds),
        ),
      ];
}
