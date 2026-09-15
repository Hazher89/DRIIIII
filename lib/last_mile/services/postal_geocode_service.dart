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

  /// Geokod full adresse (f.eks. «Alf Bjerckes vei 26B, Oslo») via Nominatim.
  static Future<({double lat, double lng, String displayName})?> resolveAddress(
    String address,
  ) async {
    final q = address.trim();
    if (q.isEmpty) return null;
    final cached = _cache['addr:${q.toLowerCase()}'];
    if (cached != null) {
      return (lat: cached.lat, lng: cached.lng, displayName: q);
    }
    try {
      final query = Uri.encodeComponent('$q, Norway');
      final res = await http
          .get(
            Uri.parse(
              'https://nominatim.openstreetmap.org/search?q=$query&format=json&limit=1&countrycodes=no',
            ),
            headers: {'User-Agent': 'DriftPro-WorkSteps/1.0 (MAVI)'},
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final list = jsonDecode(res.body) as List<dynamic>;
      if (list.isEmpty) return null;
      final first = list.first as Map<String, dynamic>;
      final lat = double.tryParse(first['lat'].toString());
      final lng = double.tryParse(first['lon'].toString());
      if (lat == null || lng == null) return null;
      _cache['addr:${q.toLowerCase()}'] = (lat: lat, lng: lng);
      final display = (first['display_name'] as String?)?.trim();
      return (lat: lat, lng: lng, displayName: display?.isNotEmpty == true ? display! : q);
    } catch (_) {
      return null;
    }
  }

  /// Omvendt geokoding: GPS → adresse (for «Min posisjon»).
  static Future<({double lat, double lng, String displayName})?> reverse({
    required double lat,
    required double lng,
  }) async {
    try {
      final res = await http
          .get(
            Uri.parse(
              'https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lng&format=json',
            ),
            headers: {'User-Agent': 'DriftPro-WorkSteps/1.0 (MAVI)'},
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        return (lat: lat, lng: lng, displayName: '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}');
      }
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final display = (map['display_name'] as String?)?.trim();
      return (
        lat: lat,
        lng: lng,
        displayName: display?.isNotEmpty == true
            ? display!
            : '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
      );
    } catch (_) {
      return (lat: lat, lng: lng, displayName: '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}');
    }
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
