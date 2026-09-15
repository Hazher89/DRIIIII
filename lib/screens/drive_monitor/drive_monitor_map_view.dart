import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../core/services/drive_monitor/drive_monitor_road_match.dart';
import '../../core/theme/app_theme.dart';

/// Kart: vei-følgende rute, hastighetsprikker og hendelser der de skjedde.
class DriveMonitorMapView extends StatefulWidget {
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

  static List<Map<String, dynamic>> cleanSamples(
    List<Map<String, dynamic>> raw,
  ) {
    final parsed =
        <({DateTime t, double lat, double lng, Map<String, dynamic> row})>[];
    for (final s in raw) {
      final lat = (s['lat'] as num?)?.toDouble();
      final lng = (s['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      if (lat.abs() < 0.01 && lng.abs() < 0.01) continue;
      final t = DateTime.tryParse('${s['recorded_at']}') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      parsed.add((t: t, lat: lat, lng: lng, row: s));
    }
    parsed.sort((a, b) => a.t.compareTo(b.t));

    final out = <Map<String, dynamic>>[];
    final dist = const Distance();
    for (final p in parsed) {
      if (out.isEmpty) {
        out.add(p.row);
        continue;
      }
      final prev = out.last;
      final plat = (prev['lat'] as num).toDouble();
      final plng = (prev['lng'] as num).toDouble();
      final d = dist.as(
        LengthUnit.Meter,
        LatLng(plat, plng),
        LatLng(p.lat, p.lng),
      );
      final prevT = DateTime.tryParse('${prev['recorded_at']}');
      if (prevT != null) {
        final dt = p.t.difference(prevT).inMilliseconds / 1000.0;
        if (dt > 0 && dt < 10 && d / dt > 60) continue;
      }
      if (d < 0.4) {
        out[out.length - 1] = p.row;
        continue;
      }
      out.add(p.row);
    }
    return out;
  }

  @override
  State<DriveMonitorMapView> createState() => _DriveMonitorMapViewState();
}

class _DriveMonitorMapViewState extends State<DriveMonitorMapView> {
  List<LatLng> _road = [];
  bool _matching = false;
  String? _matchNote;

  @override
  void initState() {
    super.initState();
    unawaitedMatch();
  }

  @override
  void didUpdateWidget(covariant DriveMonitorMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.samples != widget.samples) {
      unawaitedMatch();
    }
  }

  Future<void> unawaitedMatch() async {
    final cleaned = DriveMonitorMapView.cleanSamples(widget.samples);
    final gps = [
      for (final s in cleaned)
        LatLng(
          (s['lat'] as num).toDouble(),
          (s['lng'] as num).toDouble(),
        ),
    ];
    if (gps.length < 2) {
      if (mounted) {
        setState(() {
          _road = gps;
          _matching = false;
          _matchNote = gps.isEmpty ? null : 'Trenger flere GPS-punkter for veirute';
        });
      }
      return;
    }
    setState(() => _matching = true);
    final road = await DriveMonitorRoadMatch.matchToRoads(gps);
    if (!mounted) return;
    setState(() {
      _road = road.isNotEmpty ? road : gps;
      _matching = false;
      _matchNote = road.length > gps.length
          ? 'Rute lagt langs veinett (${road.length} punkter)'
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cleaned = DriveMonitorMapView.cleanSamples(widget.samples);
    final gpsPoints = [
      for (final s in cleaned)
        LatLng(
          (s['lat'] as num).toDouble(),
          (s['lng'] as num).toDouble(),
        ),
    ];
    final road = _road.isNotEmpty ? _road : gpsPoints;

    final center = road.isNotEmpty
        ? road[road.length ~/ 2]
        : const LatLng(59.91, 10.75);

    // Hastighetsfarget linje langs veinettet — interpoler fart fra nærmeste GPS.
    final polylines = <Polyline>[];
    for (var i = 1; i < road.length; i++) {
      final mid = LatLng(
        (road[i - 1].latitude + road[i].latitude) / 2,
        (road[i - 1].longitude + road[i].longitude) / 2,
      );
      final speed = _nearestSpeed(mid, cleaned);
      polylines.add(
        Polyline(
          points: [road[i - 1], road[i]],
          color: DriveMonitorMapView.speedColor(speed),
          strokeWidth: 5,
        ),
      );
    }

    final markers = <Marker>[];

    // Hastighetsprikker på faktiske GPS-punkter.
    for (final s in cleaned) {
      final lat = (s['lat'] as num).toDouble();
      final lng = (s['lng'] as num).toDouble();
      final speed = (s['speed_kmh'] as num?)?.toDouble() ?? 0;
      final color = DriveMonitorMapView.speedColor(speed);
      markers.add(
        Marker(
          point: LatLng(lat, lng),
          width: 16,
          height: 16,
          child: Tooltip(
            message: '${speed.toStringAsFixed(0)} km/t',
            child: Container(
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(blurRadius: 3, color: Colors.black26),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Hendelser nøyaktig der de skjedde.
    final df = DateFormat('HH:mm:ss');
    for (final e in widget.events) {
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
          width: 34,
          height: 34,
          child: Tooltip(
            message: [
              DriveMonitorMapView.eventLabel(type),
              if (t != null) df.format(t),
              if (speed != null) '${speed.toStringAsFixed(0)} km/t',
            ].join(' · '),
            child: Container(
              decoration: BoxDecoration(
                color: DriveMonitorMapView.eventColor(type, sev),
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
                        : type == 'hard_accel'
                            ? Icons.trending_up
                            : type == 'speeding'
                                ? Icons.speed
                                : type == 'idle'
                                    ? Icons.pause
                                    : Icons.circle,
                size: 16,
                color: Colors.white,
              ),
            ),
          ),
        ),
      );
    }

    if (road.isNotEmpty) {
      markers.add(
        Marker(
          point: road.first,
          width: 28,
          height: 28,
          child: const Icon(Icons.flag, color: Color(0xFF15803D), size: 26),
        ),
      );
      markers.add(
        Marker(
          point: road.last,
          width: 40,
          height: 40,
          child:
              const Icon(Icons.navigation, color: Color(0xFF15803D), size: 34),
        ),
      );
    }

    LatLngBounds? bounds;
    if (road.length >= 2) {
      bounds = LatLngBounds.fromPoints(road);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: widget.height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                if (road.isEmpty)
                  Container(
                    color: Colors.grey.shade100,
                    alignment: Alignment.center,
                    child: const Text(
                      'Ingen GPS-punkter ennå.\nKjør med enheten for å se nøyaktig rute.',
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  FlutterMap(
                    options: MapOptions(
                      initialCenter: center,
                      initialZoom: 13,
                      initialCameraFit: bounds == null
                          ? null
                          : CameraFit.bounds(
                              bounds: bounds,
                              padding: const EdgeInsets.all(40),
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
                if (_matching)
                  const Positioned(
                    top: 10,
                    right: 10,
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 8),
                            Text('Legger rute på veinett…',
                                style: TextStyle(fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (_matchNote != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              _matchNote!,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
            ),
          ),
        if (cleaned.length <= 3 && cleaned.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'Få GPS-punkter (${cleaned.length}) — linjen følger veinettet mellom dem. '
              'Flere punkter fra enheten gir mer detalj.',
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
            _legend(const Color(0xFFEA580C), 'Rå brems'),
            _legend(const Color(0xFFCA8A04), 'Rå aksel.'),
          ],
        ),
      ],
    );
  }

  double _nearestSpeed(LatLng p, List<Map<String, dynamic>> samples) {
    if (samples.isEmpty) return 0;
    final dist = const Distance();
    var best = double.infinity;
    var speed = 0.0;
    for (final s in samples) {
      final lat = (s['lat'] as num).toDouble();
      final lng = (s['lng'] as num).toDouble();
      final d = dist.as(LengthUnit.Meter, p, LatLng(lat, lng));
      if (d < best) {
        best = d;
        speed = (s['speed_kmh'] as num?)?.toDouble() ?? 0;
      }
    }
    return speed;
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
