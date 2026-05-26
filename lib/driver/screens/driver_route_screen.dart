import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../last_mile/models/lm_route.dart';
import 'driver_pod_screen.dart';

class DriverRouteScreen extends StatelessWidget {
  final List<LmRoute> routes;
  final LmRoute? active;
  final ValueChanged<LmRoute> onSelect;
  final VoidCallback onStartGps;
  final VoidCallback onRefresh;
  final bool tracking;

  const DriverRouteScreen({
    super.key,
    required this.routes,
    required this.active,
    required this.onSelect,
    required this.onStartGps,
    required this.onRefresh,
    required this.tracking,
  });

  Future<void> _navigate(String address) async {
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (routes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Ingen publiserte ruter i dag'),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRefresh, child: const Text('Oppdater')),
          ],
        ),
      );
    }

    final route = active;
    if (route == null) {
      return const Center(child: Text('Velg rute'));
    }
    final stops = route.stops;

    return Column(
      children: [
        if (routes.length > 1)
          SizedBox(
            height: 48,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: routes.length,
              itemBuilder: (ctx, i) {
                final r = routes[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(r.unitCode ?? 'Rute'),
                    selected: active?.id == r.id,
                    onSelected: (_) => onSelect(r),
                  ),
                );
              },
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${route.unitCode} · ${stops.length} stopp · ${route.status}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              if (!tracking)
                FilledButton.icon(
                  onPressed: onStartGps,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start GPS'),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: stops.length,
            itemBuilder: (ctx, i) {
              final s = stops[i];
              final o = s.order;
              final addr = o?.addressLine ?? '';
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: ListTile(
                  leading: CircleAvatar(child: Text('${s.sequence}')),
                  title: Text(o?.customerName ?? 'Kunde'),
                  subtitle: Text('$addr\n${s.status}'),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.navigation),
                        onPressed: addr.isEmpty ? null : () => _navigate(addr),
                      ),
                      IconButton(
                        icon: const Icon(Icons.check_circle_outline),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => DriverPodScreen(stop: s),
                            ),
                          );
                        },
                      ),
                    ],
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
