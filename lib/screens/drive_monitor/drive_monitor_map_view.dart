import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_theme.dart';

/// Kart for kjøresporing: faktisk GPS-rute (punkt for punkt), hastighet og hendelser.
class DriveMonitorMapView extends StatelessWidget {
  const DriveMonitorMapView({
    super.key,
    required this.samples,
    required this.events,
    this.height = 420,
  });

  final List<Map<String, dynamic>> samples;
  final List<Map<String, dynamic>> events;
  final double height;

  static Color speedColor(double kmh) {
    if (kmh >= 90) return const Color(0xFFDC2626);
    if (kmh >= 60) return const Color(0xFFD97706);
    if (kmh >= 30) return DriftProTheme.primaryGreen;
    return const Color(0xFF2563EB);
  }

  static Color eventColor(String type, String severity) {
    if (severity == 'rough') return const Color(0xFFDC2626);
    switch (type) {
      case 'hard_brake':
        return const Color(0xFFEA580C);
      case 'hard_accel':
        return const Color(0xFFCA8A04);
      case 'sharp_turn':
        return const Color(0xFF7C3AED);
      case 'speeding':
        return const Color(0xFFDC2626);
      case 'idle':
        return const Color(0xFF64748B);
      default:
        return const Color(0xFF2563EB);
    }
  }

  static String eventLabel(String type) {
    switch (type) {
      case 'hard_brake':
        return 'Rå brems';
      case 'hard_accel':
        return 'Rå akselerasjon';
      case 'sharp_turn':
        return 'Rå sving';
      case 'speeding':
        return 'Hastighet';
      case 'idle':
        return 'Stillstand';
      default:
        return type;
    }
  }

  /// Rydd GPS: sorter, dropp glitches, behold lat/lng.
  static List<Map<String, dynamic>> cleanSamples(
    List<Map<String, dynamic>> raw,
  ) {
    final parsed = <({DateTime t, double lat, double lng, Map<String, dynamic> row})>[];
    for (final s in raw) {
      final lat = (s['lat'] as num?)?.toDouble();
      final lng = (s['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      if (lat.abs() < 0.01 && lng.abs() < 0.01) continue;
      final t = DateTime.tryParse('${s['recorded_at']}') ?? DateTime.fromMillisecondsSinceEpoch(0);
      parsed.add((t: t, lat: lat, lng: lng, row: s));
    }
    parsed.sort((a, b) => a.t.compareTo(b.t));

    final out = <Map<String, dynamic>>[];
    for (final p in parsed) {
      if (out.isEmpty) {
        out.add(p.row);
        continue;
      }
      final prev = out.last;
      final plat = (prev['lat'] as num).toDouble();
      final plng = (prev['lng'] as num).toDouble();
      final d = const Distance().as(
        LengthUnit.Meter,
        LatLng(plat, plng),
        LatLng(p.lat, p.lng),
      );
      final prevT = DateTime.tryParse('${prev['recorded_at']}');
      if (prevT != null) {
        final dt = p.t.difference(prevT).inMilliseconds / 1000.0;
        if (dt > 0 && dt < 10 && d / dt > 60) {
          // Urealistisk hopp — hopp over.
          continue;
        }
      }
      if (d < 0.4) {
        // Nesten samme punkt — behold siste for hastighetsfarge.
        out[out.length - 1] = p.row;
        continue;
      }
      out.add(p.row);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final cleaned = cleanSamples(samples);
    final points = <LatLng>[];
    for (final s in cleaned) {
      points.add(
        LatLng(
          (s['lat'] as num).toDouble(),
          (s['lng'] as num).toDouble(),
        ),
      );
    }

    final center = points.isNotEmpty
        ? points[points.length ~/ 2]
        : const LatLng(59.91, 10.75);

    final polylines = <Polyline>[];
    for (var i = 1; i < cleaned.length; i++) {
      final a = cleaned[i - 1];
      final b = cleaned[i];
      final speed = (b['speed_kmh'] as num?)?.toDouble() ?? 0;
      polylines.add(
        Polyline(
          points: [
            LatLng((a['lat'] as num).toDouble(), (a['lng'] as num).toDouble()),
            LatLng((b['lat'] as num).toDouble(), (b['lng'] as num).toDouble()),
          ],
          color: speedColor(speed),
          strokeWidth: points.length < 40 ? 5.5 : 4.0,
        ),
      );
    }

    final markers = <Marker>[];
    final df = DateFormat('HH:mm:ss');

    // Breadcrumb for tette ruter — viser at det er ekte GPS-punkter, ikke strek.
    if (points.length >= 2 && points.length <= 600) {
      final step = points.length > 200 ? 3 : 1;
      for (var i = 0; i < points.length; i += step) {
        if (i == 0 || i == points.length - 1) continue;
        markers.add(
          Marker(
            point: points[i],
            width: 8,
            height: 8,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF2563EB), width: 1.5),
              ),
            ),
          ),
        );
      }
    }

    for (final e in events) {
      final lat = (e['lat'] as num?)?.toDouble();
      final lng = (e['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final type = '${e['event_type'] ?? ''}';
      final sev = '${e['severity'] ?? 'info'}';
      final t = DateTime.tryParse('${e['recorded_at']}')?.toLocal();
      final speed = (e['speed_kmh'] as num?)?.toDouble();
      markers.add(
        Marker(
          point: LatLng(lat, lng),
          width: 36,
          height: 36,
          child: Tooltip(
            message: [
              eventLabel(type),
              if (t != null) df.format(t),
              if (speed != null) '${speed.toStringAsFixed(0)} km/t',
            ].join(' · '),
            child: Container(
              decoration: BoxDecoration(
                color: eventColor(type, sev),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(blurRadius: 4, color: Colors.black38),
                ],
              ),
              child: Icon(
                type == 'sharp_turn'
                    ? Icons.u_turn_left
                    : type == 'hard_brake'
                        ? Icons.warning_amber
                        : type == 'speeding'
                            ? Icons.speed
                            : Icons.circle,
                size: 16,
                color: Colors.white,
              ),
            ),
          ),
        ),
      );
    }

    if (points.isNotEmpty) {
      markers.add(
        Marker(
          point: points.first,
          width: 28,
          height: 28,
          child: const Icon(Icons.flag, color: Color(0xFF15803D), size: 26),
        ),
      );
      markers.add(
        Marker(
          point: points.last,
          width: 44,
          height: 44,
          child: const Icon(Icons.navigation, color: Color(0xFF15803D), size: 36),
        ),
      );
    }

    LatLngBounds? bounds;
    if (points.length >= 2) {
      bounds = LatLngBounds.fromPoints(points);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: points.isEmpty
                ? Container(
                    color: Colors.grey.shade100,
                    alignment: Alignment.center,
                    child: const Text(
                      'Ingen GPS-punkter ennå.\nKjør med enheten for å se nøyaktig rute.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : FlutterMap(
                    options: MapOptions(
                      initialCenter: center,
                      initialZoom: points.length > 2 ? 14 : 12,
                      initialCameraFit: bounds == null
                          ? null
                          : CameraFit.bounds(
                              bounds: bounds,
                              padding: const EdgeInsets.all(36),
                              maxZoom: 17,
                            ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'no.driftpro.driftpro',
                      ),
                      if (polylines.isNotEmpty)
                        PolylineLayer(polylines: polylines),
                      if (markers.isNotEmpty) MarkerLayer(markers: markers),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 8),
        if (cleaned.length <= 3 && cleaned.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'Kun ${cleaned.length} GPS-punkter — ruten blir mer nøyaktig med flere punkter '
              '(oppdater appen på enheten og kjør med sporing aktiv).',
              style: TextStyle(fontSize: 11, color: Colors.orange.shade900),
            ),
          ),
        Wrap(
          spacing: 10,
          runSpacing: 6,
          children: [
            _legend(const Color(0xFF2563EB), 'Lav fart'),
            _legend(DriftProTheme.primaryGreen, 'Middels'),
            _legend(const Color(0xFFD97706), 'Høy'),
            _legend(const Color(0xFFDC2626), 'Rå / fart'),
            _legend(const Color(0xFF7C3AED), 'Rå sving'),
          ],
        ),
      ],
    );
  }

  Widget _legend(Color c, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}
