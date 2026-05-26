import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../last_mile/services/lm_gps_service.dart';

/// Live sporing — Realtime GPS fra sjåfør-app.
class DispatchTrackingScreen extends StatefulWidget {
  const DispatchTrackingScreen({super.key});

  @override
  State<DispatchTrackingScreen> createState() => _DispatchTrackingScreenState();
}

class _DispatchTrackingScreenState extends State<DispatchTrackingScreen> {
  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  List<Map<String, dynamic>> _positions = [];
  String? _companyId;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final cid = await SupabaseService.getCurrentCompanyId();
    if (cid == null || !mounted) return;
    setState(() => _companyId = cid);
    _sub = LmGpsService.subscribeFleetPositions(cid).listen((rows) {
      if (mounted) setState(() => _positions = rows);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[];
    final seen = <String>{};
    for (final p in _positions) {
      final vid = p['partner_vehicle_id'] as String?;
      if (vid == null || seen.contains(vid)) continue;
      seen.add(vid);
      final lat = (p['lat'] as num?)?.toDouble();
      final lng = (p['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      markers.add(
        Marker(
          point: LatLng(lat, lng),
          width: 40,
          height: 40,
          child: const Icon(Icons.local_shipping, color: Colors.blue, size: 32),
        ),
      );
    }

    var center = const LatLng(59.95, 10.75);
    if (markers.isNotEmpty) center = markers.first.point;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Text('Live flåte (${seen.length} bil)', style: DriftProTheme.headingMd),
              const Spacer(),
              if (_companyId != null)
                Text('Realtime GPS', style: DriftProTheme.caption),
            ],
          ),
        ),
        Expanded(
          child: FlutterMap(
            options: MapOptions(initialCenter: center, initialZoom: 9),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'no.driftpro.ruteplan',
              ),
              MarkerLayer(markers: markers),
            ],
          ),
        ),
        if (_positions.isNotEmpty)
          SizedBox(
            height: 120,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _positions.length.clamp(0, 20),
              itemBuilder: (ctx, i) {
                final p = _positions[i];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      'Bil ${(p['partner_vehicle_id'] as String?)?.substring(0, 8) ?? ''}\n'
                      '${p['lat']} / ${p['lng']}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
