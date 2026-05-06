/// Standard skift for rute-Oslo/Østfold/Bærum/Drammen + dag/kveld + tilgjengelighet.
/// Farger i Connecteam-stil (tydelige, skille dag/kveld).
class FleetShiftSeed {
  static List<Map<String, dynamic>> buildRows(String companyId) {
    var order = 0;
    final rows = <Map<String, dynamic>>[];

    void availability(String name, String color, String desc) {
      rows.add({
        'company_id': companyId,
        'name': name,
        'description': desc,
        'color_hex': color,
        'region_group': 'Tilgjengelighet',
        'time_band': null,
        'shift_kind': 'availability',
        'sort_order': order++,
      });
    }

    void routeOps(String region, String place, String band, String colorHex) {
      final label = band == 'dag' ? 'dagrute' : 'kveldsrute';
      rows.add({
        'company_id': companyId,
        'name': '$place — $label',
        'description': '$place · $region · ${band == 'dag' ? 'Dag' : 'Kveld'}',
        'color_hex': colorHex,
        'region_group': region,
        'time_band': band,
        'shift_kind': 'route_ops',
        'sort_order': order++,
      });
    }

    availability(
      'Ledig bil',
      '#78909C',
      'Markering: ingen rute fordelt for valgt skift/dato (etter massefordeling eller manuelt).',
    );
    availability(
      'Fri',
      '#1565C0',
      'Sjåfør/bil kjører ikke (friøkt, syk, permisjon, osv.).',
    );
    availability(
      'Gitt bort rute',
      '#EF6C00',
      'Rute overført til annen bil eller annen part.',
    );

    const osloPlaces = [
      'Oslo sentrum',
      'Frogner',
      'Ullern',
      'Vestre Aker',
      'Nordre Aker',
      'Bjerke',
      'Grorud',
      'Stovner',
      'Alna',
      'Østensjø',
      'Nordstrand',
      'Sagene',
      'St. Hanshaugen',
      'Gamle Oslo',
      'Søndre Nordstrand',
    ];
    for (final p in osloPlaces) {
      routeOps('Oslo', p, 'dag', '#43A047');
      routeOps('Oslo', p, 'kveld', '#1B5E20');
    }

    const ostfold = [
      'Fredrikstad',
      'Sarpsborg',
      'Halden',
      'Moss',
      'Råde',
      'Rakkestad',
      'Spydeberg',
      'Askim',
      'Marker',
      'Aremark',
      'Trøgstad',
      'Hvaler',
    ];
    for (final p in ostfold) {
      routeOps('Østfold', p, 'dag', '#00897B');
      routeOps('Østfold', p, 'kveld', '#004D40');
    }

    const baerum = ['Sandvika', 'Haslum', 'Rykkinn', 'Hosle', 'Jar', 'Kolsås'];
    for (final p in baerum) {
      routeOps('Bærum', p, 'dag', '#6A1B9A');
      routeOps('Bærum', p, 'kveld', '#4A148C');
    }

    const drammen = ['Drammen', 'Mjøndalen', 'Svelvik', 'Lier', 'Krokstadelva'];
    for (final p in drammen) {
      routeOps('Drammen', p, 'dag', '#F9A825');
      routeOps('Drammen', p, 'kveld', '#F57F17');
    }

    return rows;
  }
}
