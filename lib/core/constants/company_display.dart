/// Visningsnavn for bedrift på dashboard og infoskjerm.
class CompanyDisplay {
  CompanyDisplay._();

  static const String defaultName = 'MAVI Logistikk AS';

  /// Skjuler DriftPro demo / hovedkontor-navn fra databasen.
  static String resolve(String? raw) {
    final t = raw?.trim() ?? '';
    if (t.isEmpty) return defaultName;
    final lower = t.toLowerCase();
    if (lower.contains('driftpro') ||
        lower.contains('demo') ||
        lower == 'driftpro hovedkontor') {
      return defaultName;
    }
    return t;
  }
}
