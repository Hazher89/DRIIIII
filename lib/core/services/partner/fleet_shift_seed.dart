import 'postal_region_mapper.dart';

/// Skift generert fra postkode-områder: én dag + én kveld per region.
class FleetShiftSeed {
  static const int catalogVersion = 4;

  /// Tilgjengelighet (flåte-status) — ikke fra POSTKODE.
  static const List<String> availabilityNames = [
    'Fri',
    'Syk',
    'Gitt bort',
    'LEDIG HELE DAG',
    'LEDIG DAG',
    'LEDIG KVELD',
  ];

  /// Områder fra POSTKODE-register (via [PostalRegionMapper]).
  static List<String> get routeRegions => PostalRegionMapper.allRouteRegions;

  static List<String> get canonicalNames => [
    for (final r in routeRegions) ...['Dagrute - $r', 'Kveldsrute - $r'],
    ...availabilityNames,
  ];

  static bool matchesCatalog(List<dynamic> activeShiftNames) {
    final names = activeShiftNames.map((e) => e.toString()).toSet();
    for (final n in canonicalNames) {
      if (!names.contains(n)) return false;
    }
    return names.length >= canonicalNames.length - 2;
  }

  static List<Map<String, dynamic>> buildRows(String companyId) {
    var order = 0;
    final rows = <Map<String, dynamic>>[];

    void add({
      required String name,
      required String kind,
      required String color,
      String? region,
      String? band,
    }) {
      rows.add({
        'company_id': companyId,
        'name': name,
        'description': name,
        'color_hex': color,
        'region_group': region,
        'time_band': band,
        'shift_kind': kind,
        'sort_order': order++,
        'is_archived': false,
      });
    }

    const dagGreen = '#43A047';
    const kveldGreen = '#1B5E20';
    const kveldTeal = '#00695C';
    const dagTeal = '#00897B';
    const purple = '#6A1B9A';
    const amber = '#F9A825';

    for (final region in routeRegions) {
      var dagColor = dagGreen;
      var kveldColor = kveldGreen;
      if (region.contains('Østfold') || region.contains('Kongsvinger')) {
        dagColor = dagTeal;
        kveldColor = kveldTeal;
      } else if (region.contains('Bærum') || region.contains('Hadeland')) {
        dagColor = purple;
        kveldColor = purple;
      } else if (region.contains('Drammen') || region.contains('Hønefoss')) {
        dagColor = amber;
        kveldColor = amber;
      }
      add(
        name: 'Dagrute - $region',
        kind: 'route_ops',
        color: dagColor,
        region: region,
        band: 'dag',
      );
      add(
        name: 'Kveldsrute - $region',
        kind: 'route_ops',
        color: kveldColor,
        region: region,
        band: 'kveld',
      );
    }

    add(name: 'Fri', kind: 'availability', color: '#1565C0', region: 'Tilgjengelighet');
    add(name: 'Gitt bort', kind: 'availability', color: '#EF6C00', region: 'Tilgjengelighet');
    add(name: 'Syk', kind: 'availability', color: '#C62828', region: 'Tilgjengelighet');
    add(name: 'LEDIG HELE DAG', kind: 'availability', color: '#78909C', region: 'Tilgjengelighet');
    add(name: 'LEDIG DAG', kind: 'availability', color: '#90A4AE', region: 'Tilgjengelighet', band: 'dag');
    add(name: 'LEDIG KVELD', kind: 'availability', color: '#607D8B', region: 'Tilgjengelighet', band: 'kveld');

    return rows;
  }
}
