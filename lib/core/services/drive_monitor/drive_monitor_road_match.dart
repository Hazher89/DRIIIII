import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Matcher GPS-spor til veinett via OSRM (offentlig demo / egen server).
abstract final class DriveMonitorRoadMatch {
  static const _base = 'https://router.project-osrm.org';

  /// Returnerer vei-følgende punkter. Faller tilbake til rå GPS ved feil.
  static Future<List<LatLng>> matchToRoads(List<LatLng> gps) async {
    if (gps.length < 2) return List<LatLng>.from(gps);

    // Nedsample til maks 80 punkter for offentlig API.
    final input = _downsample(gps, 80);

    try {
      if (input.length == 2) {
        final routed = await _route(input[0], input[1]);
        if (routed.length >= 2) return routed;
      } else {
        final matched = await _match(input);
        if (matched.length >= 2) return matched;
        // Fallback: lim ruter mellom segmenter.
        final chained = await _chainRoutes(input);
        if (chained.length >= 2) return chained;
      }
    } catch (_) {}
    return List<LatLng>.from(gps);
  }

  static List<LatLng> _downsample(List<LatLng> pts, int max) {
    if (pts.length <= max) return pts;
    final out = <LatLng>[pts.first];
    final step = (pts.length - 1) / (max - 1);
    for (var i = 1; i < max - 1; i++) {
      out.add(pts[(i * step).round().clamp(0, pts.length - 1)]);
    }
    out.add(pts.last);
    return out;
  }

  static Future<List<LatLng>> _route(LatLng a, LatLng b) async {
    final url = Uri.parse(
      '$_base/route/v1/driving/'
      '${a.longitude},${a.latitude};${b.longitude},${b.latitude}'
      '?overview=full&geometries=geojson',
    );
    final res = await http.get(url).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return [];
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['code'] != 'Ok') return [];
    final routes = json['routes'] as List?;
    if (routes == null || routes.isEmpty) return [];
    final geom = (routes.first as Map)['geometry'] as Map?;
    final coords = geom?['coordinates'] as List?;
    if (coords == null) return [];
    return [
      for (final c in coords)
        if (c is List && c.length >= 2)
          LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
    ];
  }

  static Future<List<LatLng>> _match(List<LatLng> pts) async {
    final coords = pts
        .map((p) => '${p.longitude},${p.latitude}')
        .join(';');
    final radiuses = List.filled(pts.length, '35').join(';');
    final url = Uri.parse(
      '$_base/match/v1/driving/$coords'
      '?overview=full&geometries=geojson&gaps=split&radiuses=$radiuses',
    );
    final res = await http.get(url).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return [];
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['code'] != 'Ok') return [];
    final matchings = json['matchings'] as List?;
    if (matchings == null || matchings.isEmpty) return [];

    final out = <LatLng>[];
    for (final m in matchings) {
      final geom = (m as Map)['geometry'] as Map?;
      final coordsList = geom?['coordinates'] as List?;
      if (coordsList == null) continue;
      for (final c in coordsList) {
        if (c is List && c.length >= 2) {
          out.add(LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()));
        }
      }
    }
    return out;
  }

  static Future<List<LatLng>> _chainRoutes(List<LatLng> pts) async {
    final out = <LatLng>[];
    for (var i = 1; i < pts.length; i++) {
      final seg = await _route(pts[i - 1], pts[i]);
      if (seg.isEmpty) {
        if (out.isEmpty) out.add(pts[i - 1]);
        out.add(pts[i]);
        continue;
      }
      if (out.isNotEmpty && seg.isNotEmpty) {
        out.addAll(seg.skip(1));
      } else {
        out.addAll(seg);
      }
    }
    return out;
  }
}
