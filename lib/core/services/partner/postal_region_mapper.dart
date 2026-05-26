/// Mapper stedsnavn (fra postnummer-register) til flåte [region_group] (skiftområde).
class PostalRegionMapper {
  PostalRegionMapper._();

  /// Alle ruteområder (fra POSTKODE.xlsx via region-mapping).
  static const List<String> allRouteRegions = [
    'Oslo',
    'Bærum',
    'Nesodden',
    'Ski',
    'Drammen',
    'Indre',
    'Jessheim',
    'Nittedal',
    'Hønefoss',
    'Kongsvinger',
    'Østfold',
    'Hadeland',
  ];

  static String _norm(String s) =>
      s.toLowerCase().replaceAll('æ', 'ae').replaceAll('ø', 'o').replaceAll('å', 'aa').trim();

  /// Eksakt stedsnavn fra postnummer-register (unngår feil som Jaren → jar → Bærum).
  static const Map<String, String> _exactStedToRegion = {
    'oslo': 'Oslo',
    'jaren': 'Hadeland',
    'harestua': 'Hadeland',
    'maura': 'Hadeland',
    'roa': 'Hadeland',
    'gran': 'Hadeland',
    'brandbu': 'Hadeland',
    'asker': 'Bærum',
    'sandvika': 'Bærum',
    'bekkestua': 'Bærum',
    'stabekk': 'Bærum',
    'lysaker': 'Bærum',
    'fornebu': 'Bærum',
    'jar': 'Bærum',
    'ski': 'Ski',
    'langhus': 'Ski',
    'krakstad': 'Ski',
    'drammen': 'Drammen',
    'jessheim': 'Jessheim',
    'klofta': 'Jessheim',
    'nittedal': 'Nittedal',
    'honefoss': 'Hønefoss',
    'hønefoss': 'Hønefoss',
    'kongsvinger': 'Kongsvinger',
    'moss': 'Østfold',
    'askim': 'Østfold',
    'sarpsborg': 'Østfold',
    'fredrikstad': 'Østfold',
    'lillestrom': 'Indre',
    'lillestrøm': 'Indre',
    'strommen': 'Indre',
    'strømmen': 'Indre',
    'lorenskog': 'Indre',
    'lørenskog': 'Indre',
    'hvam': 'Indre',
    'aarnes': 'Indre',
    'arnes': 'Indre',
    'neskollen': 'Indre',
    'skedsmokorset': 'Indre',
    'fetsund': 'Indre',
    'hakadal': 'Nittedal',
    'halden': 'Østfold',
    'rasta': 'Indre',
    'raelingen': 'Indre',
    'nesoddtangen': 'Nesodden',
    'frogn': 'Nesodden',
  };

  static bool _hasWord(String haystack, String word) {
    if (word.length <= 2) return haystack == word;
    return RegExp('\\b${RegExp.escape(word)}\\b', caseSensitive: false).hasMatch(haystack);
  }

  static bool _hasAnyWord(String haystack, Iterable<String> words) =>
      words.any((w) => _hasWord(haystack, w));

  static String? stedToRegion(String? sted) {
    if (sted == null || sted.isEmpty) return null;
    final s = _norm(sted);

    final exact = _exactStedToRegion[s];
    if (exact != null) return exact;

    if (_hasAnyWord(s, ['hadeland'])) return 'Hadeland';

    if (_hasAnyWord(s, ['nesod', 'frogn', 'fagerstrand', 'fjellstrand', 'son', 'bjornemyr'])) {
      return 'Nesodden';
    }

    if (_hasAnyWord(s, ['ski', 'krakstad', 'skotbu', 'langhus', 'siggerud', 'oppegard', 'oppegård'])) {
      return 'Ski';
    }

    if (_hasAnyWord(s, [
      'asker',
      'billingstad',
      'vollen',
      'heggedal',
      'baerum',
      'bærum',
      'bekkestua',
      'sandvika',
      'stabekk',
      'jar',
      'lysaker',
      'fornebu',
      'hosle',
      'blommenholm',
      'hvalstad',
      'royken',
      'røyken',
    ])) {
      return 'Bærum';
    }

    if (_hasAnyWord(s, ['drammen', 'konnerud', 'gulskogen', 'mjondalen', 'mjøndalen'])) {
      return 'Drammen';
    }

    if (_hasAnyWord(s, [
      'lillestrom',
      'lillestrøm',
      'strommen',
      'strømmen',
      'lorenskog',
      'lørenskog',
      'rotnes',
      'fjellhamar',
      'fjerdingby',
      'aursmo',
      'aurskog',
      'hvam',
      'aarnes',
      'arnes',
      'neskollen',
      'skedsmokorset',
      'fetsund',
      'rasta',
      'raelingen',
    ])) {
      return 'Indre';
    }

    if (_hasAnyWord(s, ['hakadal', 'slattum'])) {
      return 'Nittedal';
    }

    if (_hasAnyWord(s, ['jessheim', 'klofta', 'kløfta', 'garder', 'gjerdrum'])) {
      return 'Jessheim';
    }

    if (_hasAnyWord(s, ['nittedal', 'hakadal', 'slattum'])) {
      return 'Nittedal';
    }

    if (_hasAnyWord(s, ['honefoss', 'hønefoss', 'hallingby'])) {
      return 'Hønefoss';
    }

    if (_hasAnyWord(s, ['kongsvinger', 'flisa'])) {
      return 'Kongsvinger';
    }

    if (_hasAnyWord(s, [
      'askim',
      'moss',
      'sarpsborg',
      'fredrikstad',
      'halden',
      'rade',
      'råde',
      'rygge',
      'valer',
      'våler',
      'spydeberg',
      'ostfold',
      'østfold',
      'mysen',
      'rakkestad',
      'indre ostfold',
    ])) {
      return 'Østfold';
    }

    if (_hasAnyWord(s, [
      'grorud',
      'lambertseter',
      'bryn',
      'stovner',
      'roroslo',
      'ror',
      'majorstuen',
      'sagene',
      'torshov',
      'ekeberg',
      'holmlia',
      'manglerud',
    ])) {
      return 'Oslo';
    }

    return null;
  }

  /// Områdealias og regionnavn i fri tekst (PDF, notater, tittel).
  static const Map<String, String> _textAliases = {
    'romerike': 'Indre',
    'indre akershus': 'Indre',
    'follo': 'Ski',
    'asker og baerum': 'Bærum',
    'asker og bærum': 'Bærum',
  };

  /// Leser område fra PDF-tekst, notater eller tittel når postkode-parsing svikter.
  static String? regionFromFreeText(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final s = _norm(raw);

    for (final e in _textAliases.entries) {
      if (_hasAnyWord(s, [e.key])) return e.value;
    }

    for (final r in allRouteRegions) {
      if (_hasAnyWord(s, [_norm(r)])) return r;
    }

    final steds = _exactStedToRegion.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));
    for (final e in steds) {
      if (_hasAnyWord(s, [e.key])) return e.value;
    }

    for (final m in RegExp(
      r'\b(\d{4})\s+([A-Za-zÆØÅæøå][A-Za-zÆØÅæøå\s.-]{1,35})',
    ).allMatches(raw)) {
      final place = m.group(2)!.trim();
      final r = stedToRegion(place);
      if (r != null) return r;
    }

    return null;
  }

  /// «Område: Indre» / «Skift (auto): Dagrute - Indre» fra auto-notater.
  static String? regionFromShareMetadata({String? title, String? notes}) {
    final blob = '${title ?? ''}\n${notes ?? ''}'.trim();
    if (blob.isEmpty) return null;

    final autoShift = RegExp(
      r'Skift\s*\(auto\):\s*(?:Dagrute|Kveldsrute)\s*-\s*([^\n]+)',
      caseSensitive: false,
    ).firstMatch(blob);
    if (autoShift != null) {
      final name = _norm(autoShift.group(1)!.trim());
      for (final r in allRouteRegions) {
        if (name.contains(_norm(r))) return r;
      }
    }

    final area = RegExp(
      r'Omr[aå]de:\s*([^\n(]+)',
      caseSensitive: false,
    ).firstMatch(blob);
    if (area != null) {
      final raw = area.group(1)!.trim();
      for (final r in allRouteRegions) {
        if (_norm(raw).startsWith(_norm(r))) return r;
      }
      return regionFromFreeText(raw);
    }

    return regionFromFreeText(blob);
  }
}
