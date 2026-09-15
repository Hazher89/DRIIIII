import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_theme.dart';

/// Avansert kart for leiebil-sporing: rute, hastighet, rå brems/sving m.m.
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

  @override
  Widget build(BuildContext context) {
    final points = <LatLng>[];
    for (final s in samples) {
      final lat = (s['lat'] as num?)?.toDouble();
      final lng = (s['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      points.add(LatLng(lat, lng));
    }

    final center = points.isNotEmpty
        ? points[points.length ~/ 2]
        : const LatLng(59.91, 10.75);

    final polylines = <Polyline>[];
    for (var i = 1; i < samples.length; i++) {
      final a = samples[i - 1];
      final b = samples[i];
      final lat1 = (a['lat'] as num?)?.toDouble();
      final lng1 = (a['lng'] as num?)?.toDouble();
      final lat2 = (b['lat'] as num?)?.toDouble();
      final lng2 = (b['lng'] as num?)?.toDouble();
      if (lat1 == null || lng1 == null || lat2 == null || lng2 == null) continue;
      final speed = (b['speed_kmh'] as num?)?.toDouble() ?? 0;
      polylines.add(
        Polyline(
          points: [LatLng(lat1, lng1), LatLng(lat2, lng2)],
          color: speedColor(speed),
          strokeWidth: 4.5,
        ),
      );
    }

    final markers = <Marker>[];
    final df = DateFormat('HH:mm:ss');
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
          point: points.last,
          width: 44,
          height: 44,
          child: const Icon(Icons.navigation, color: Color(0xFF15803D), size: 36),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: points.length > 2 ? 13 : 11,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'no.driftpro.driftpro',
                ),
                if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
                if (markers.isNotEmpty) MarkerLayer(markers: markers),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
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
        Container(width: 12, height: 12, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}
