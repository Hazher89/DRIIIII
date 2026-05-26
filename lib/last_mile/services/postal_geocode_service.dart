import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/services/partner/postal_code_registry.dart';

/// Grov geokoding for VRPTW (Nominatim + fallback per postnummer-prefix).
class PostalGeocodeService {
  PostalGeocodeService._();

  static final _cache = <String, ({double lat, double lng})>{};

  static Future<({double lat, double lng})?> resolve({
    required String addressLine,
    String? postalCode,
    String? city,
  }) async {
    final pc = postalCode?.replaceAll(RegExp(r'\D'), '').padLeft(4, '0');
    if (pc != null && pc.length == 4) {
      final cached = _cache[pc];
      if (cached != null) return cached;

      final approx = _approximateNorway(pc);
      if (approx != null) {
        _cache[pc] = approx;
      }

      try {
        await PostalCodeRegistry.ensureLoaded();
        final sted = PostalCodeRegistry.lookupSted(pc);
        final q = Uri.encodeComponent(
          '${addressLine.trim()}, $pc ${sted ?? city ?? ''}, Norway',
        );
        final res = await http
            .get(
              Uri.parse('https://nominatim.openstreetmap.org/search?q=$q&format=json&limit=1'),
              headers: {'User-Agent': 'DriftPro-Ruteplan/1.0'},
            )
            .timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          final list = jsonDecode(res.body) as List<dynamic>;
          if (list.isNotEmpty) {
            final lat = double.tryParse(list.first['lat'].toString());
            final lng = double.tryParse(list.first['lon'].toString());
            if (lat != null && lng != null) {
              final c = (lat: lat, lng: lng);
              _cache[pc] = c;
              return c;
            }
          }
        }
      } catch (_) {}

      return _cache[pc] ?? approx;
    }
    return null;
  }

  /// Grov interpolasjon innen Norge (til VRPTW når Nominatim feiler).
  static ({double lat, double lng})? _approximateNorway(String pc) {
    final n = int.tryParse(pc);
    if (n == null) return null;
    if (n >= 100 && n <= 1299) return (lat: 59.91, lng: 10.75);
    if (n >= 1300 && n <= 1999) return (lat: 59.85, lng: 10.80);
    if (n >= 2000 && n <= 2999) return (lat: 59.95, lng: 11.05);
    if (n >= 3000 && n <= 3999) return (lat: 59.75, lng: 10.20);
    if (n >= 4000 && n <= 4999) return (lat: 58.97, lng: 5.73);
    if (n >= 5000 && n <= 5999) return (lat: 60.39, lng: 5.32);
    if (n >= 6000 && n <= 6999) return (lat: 62.47, lng: 6.15);
    if (n >= 7000 && n <= 7999) return (lat: 63.43, lng: 10.39);
    if (n >= 8000 && n <= 8999) return (lat: 68.44, lng: 17.43);
    if (n >= 9000 && n <= 9999) return (lat: 69.65, lng: 18.96);
    return (lat: 60.0, lng: 10.0);
  }
}
