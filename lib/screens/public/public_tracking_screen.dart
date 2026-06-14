import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_theme.dart';
import '../../last_mile/services/lm_tracking_service.dart';
import '../../widgets/driftpro_loading_indicator.dart';

/// Offentlig kundesporing (?track=token).
class PublicTrackingScreen extends StatefulWidget {
  final String token;

  const PublicTrackingScreen({super.key, required this.token});

  @override
  State<PublicTrackingScreen> createState() => _PublicTrackingScreenState();
}

class _PublicTrackingScreenState extends State<PublicTrackingScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await LmTrackingService.publicTrackingPayload(widget.token);
    if (mounted) {
      setState(() {
        _data = data;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const DriftProLoadingPage();
    }
    if (_data == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sporing')),
        body: const Center(child: Text('Sporingslenken er ugyldig eller utløpt')),
      );
    }

    final route = _data!['route'] as Map<String, dynamic>?;
    final gps = _data!['gps'] as Map<String, dynamic>?;
    final stops = _data!['stops'] as List<dynamic>? ?? [];

    LatLng? center;
    if (gps != null) {
      final lat = (gps['lat'] as num?)?.toDouble();
      final lng = (gps['lng'] as num?)?.toDouble();
      if (lat != null && lng != null) center = LatLng(lat, lng);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Din levering')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bil ${route?['unit_code'] ?? ''}',
                  style: DriftProTheme.headingMd,
                ),
                Text('Status: ${route?['status'] ?? ''}'),
                if (gps?['recorded_at'] != null)
                  Text('Sist posisjon: ${gps!['recorded_at']}', style: DriftProTheme.caption),
              ],
            ),
          ),
          if (center != null)
            Expanded(
              child: FlutterMap(
                options: MapOptions(initialCenter: center, initialZoom: 13),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'no.driftpro.ruteplan',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: center,
                        width: 40,
                        height: 40,
                        child: const Icon(Icons.local_shipping, color: Colors.green, size: 36),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else
            const Expanded(child: Center(child: Text('Venter på GPS-posisjon'))),
          SizedBox(
            height: 100,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: stops.map((s) {
                final m = s as Map<String, dynamic>;
                return ListTile(
                  dense: true,
                  title: Text('Stopp ${m['sequence']}'),
                  trailing: Text(m['status']?.toString() ?? ''),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
