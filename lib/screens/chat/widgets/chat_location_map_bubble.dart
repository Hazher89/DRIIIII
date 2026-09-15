import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';

/// Inline kartboble for chat-posisjon (iOS + Android).
class ChatLocationMapBubble extends StatelessWidget {
  const ChatLocationMapBubble({
    super.key,
    required this.latitude,
    required this.longitude,
    this.label,
    this.mine = false,
    this.height = 148,
  });

  final double latitude;
  final double longitude;
  final String? label;
  final bool mine;
  final double height;

  static ({double lat, double lng})? parseCoords({
    String? body,
    String? storagePath,
  }) {
    final candidates = <String>[
      if (storagePath != null) storagePath,
      if (body != null) body,
    ];
    for (final raw in candidates) {
      final geo = RegExp(
        r'geo://\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)',
        caseSensitive: false,
      ).firstMatch(raw);
      if (geo != null) {
        final lat = double.tryParse(geo.group(1)!);
        final lng = double.tryParse(geo.group(2)!);
        if (lat != null && lng != null) return (lat: lat, lng: lng);
      }
      final plain = RegExp(
        r'(-?\d{1,2}\.\d+)\s*,\s*(-?\d{1,3}\.\d+)',
      ).firstMatch(raw);
      if (plain != null) {
        final lat = double.tryParse(plain.group(1)!);
        final lng = double.tryParse(plain.group(2)!);
        if (lat != null && lng != null) return (lat: lat, lng: lng);
      }
    }
    return null;
  }

  Future<void> _openExternal() async {
    final q = Uri.encodeComponent('$latitude,$longitude');
    final uri = Uri.parse('https://maps.google.com/?q=$q');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final point = LatLng(latitude, longitude);
    final caption = (label != null && label!.trim().isNotEmpty)
        ? label!.trim()
        : '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openExternal,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              child: SizedBox(
                height: height,
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: point,
                    initialZoom: 15,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.none,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'no.driftpro.driftpro',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: point,
                          width: 40,
                          height: 40,
                          child: const Icon(
                            Icons.location_on_rounded,
                            color: Color(0xFFE11D48),
                            size: 36,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              decoration: BoxDecoration(
                color: mine
                    ? Colors.white.withValues(alpha: 0.14)
                    : const Color(0xFFF3F5F4),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(14),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.map_outlined,
                    size: 16,
                    color: mine ? Colors.white : DriftProTheme.primaryGreen,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: mine ? Colors.white : const Color(0xFF1A1A1A),
                      ),
                    ),
                  ),
                  Text(
                    'Åpne',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: mine
                          ? Colors.white.withValues(alpha: 0.9)
                          : DriftProTheme.primaryGreen,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
