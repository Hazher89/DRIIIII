/// Standard skiftliste (MAVI / Connecteam) — erstatter gamle område-skift.
class FleetShiftSeed {
  static const int catalogVersion = 2;

  static const List<String> canonicalNames = [
    'Dagrute - Oslo',
    'Dagrute - Hønefoss',
    'Dagrute - Kongsvinger',
    'Dobbel',
    'Dagrute',
    'Kveldsrute - Oslo',
    'Intern',
    'LEDIG HELE DAG',
    'Kveldsrute',
    'Kveldsrute - Jessheim',
    'Kveldsrute - Nittedal',
    'Kveldsrute - Nesodden',
    'Kveldsrute - Ski',
    'Kveldsrute - Indre',
    'Kveldsrute - Østfold',
    'Kveldsrute - Bærum',
    'Kveldsrute - Drammen',
    'Kveldsrute - Hønefoss',
    'Fri',
    'Dagrute - Østfold',
    'Gitt bort',
    'Dagrute - Ski',
    'Syk',
    'Dagrute - Drammen',
    'Dagrute - Jessheim',
    'Dagrute - Indre',
    'Dagrute - Nesodden',
    'Dagrute - Bærum',
    'Dagrute - Nittedal',
    'Geilo',
    'LEDIG DAG',
    'LEDIG KVELD',
    'DAWID',
    'ADAM',
    'Dag-Hadeland',
    'Kveld-Hadeland',
    'KVELD-KONGSVINGER',
  ];

  static List<Map<String, dynamic>> buildRows(String companyId) {
    var order = 0;
    final rows = <Map<String, dynamic>>[];

    void add(
      String name, {
      String kind = 'route_ops',
      String color = '#2E7D32',
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

    String? bandFromName(String name) {
      final lower = name.toLowerCase();
      if (lower.startsWith('kveld') || lower.contains('kvelds')) return 'kveld';
      if (lower.startsWith('dag') || lower.contains('dagrute')) return 'dag';
      return null;
    }

    String? regionFromName(String name) {
      final parts = name.split(' - ');
      if (parts.length >= 2) return parts.sublist(1).join(' - ');
      if (name.contains('-')) {
        final p = name.split('-');
        if (p.length >= 2) return p.sublist(1).join('-').trim();
      }
      return null;
    }

    const dagGreen = '#43A047';
    const kveldGreen = '#1B5E20';
    const kveldTeal = '#00695C';
    const dagTeal = '#00897B';
    const purple = '#6A1B9A';
    const amber = '#F9A825';
    const blue = '#1565C0';
    const orange = '#EF6C00';
    const grey = '#78909C';
    const red = '#C62828';

    for (final name in canonicalNames) {
      final lower = name.toLowerCase();
      if (lower == 'fri') {
        add(name, kind: 'availability', color: blue, region: 'Tilgjengelighet');
        continue;
      }
      if (lower == 'gitt bort') {
        add(name, kind: 'availability', color: orange, region: 'Tilgjengelighet');
        continue;
      }
      if (lower == 'syk') {
        add(name, kind: 'availability', color: red, region: 'Tilgjengelighet');
        continue;
      }
      if (lower.startsWith('ledig')) {
        add(name, kind: 'availability', color: grey, region: 'Tilgjengelighet');
        continue;
      }
      if (lower == 'intern' || lower == 'dobbel') {
        add(name, kind: 'availability', color: '#9E9E9E', region: 'Tilgjengelighet');
        continue;
      }
      if (name == 'DAWID' || name == 'ADAM') {
        add(name, kind: 'route_ops', color: purple, region: 'Spesial');
        continue;
      }
      if (name == 'Geilo') {
        add(name, kind: 'route_ops', color: '#5D4037', region: 'Geilo', band: 'dag');
        continue;
      }

      final band = bandFromName(name);
      final region = regionFromName(name);
      var color = dagGreen;
      if (band == 'kveld') {
        color = kveldGreen;
      } else if (region != null) {
        if (region.contains('Østfold') || region.contains('Kongsvinger')) {
          color = band == 'kveld' ? kveldTeal : dagTeal;
        } else if (region.contains('Bærum') || region.contains('Hadeland')) {
          color = purple;
        } else if (region.contains('Drammen') || region.contains('Hønefoss')) {
          color = amber;
        }
      }
      add(name, kind: 'route_ops', color: color, region: region, band: band);
    }

    return rows;
  }
}
