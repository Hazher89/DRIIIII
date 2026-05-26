import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_theme.dart';
import '../../last_mile/models/lm_fleet_snapshot.dart';
import '../../last_mile/models/lm_route.dart';
import '../../last_mile/services/last_mile_order_service.dart';
import '../../last_mile/services/last_mile_route_service.dart';
import '../../last_mile/services/lm_tracking_service.dart';

/// Planlegger — TransFleet-erstatning: VRPTW, kart, drag-drop rekkefølge.
class DispatchPlannerScreen extends StatefulWidget {
  final LmFleetSnapshot? fleet;

  const DispatchPlannerScreen({super.key, this.fleet});

  @override
  State<DispatchPlannerScreen> createState() => DispatchPlannerScreenState();
}

class DispatchPlannerScreenState extends State<DispatchPlannerScreen> {
  DateTime _day = DateTime.now();
  List<LmRoute> _routes = [];
  LmRoute? _selected;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final day = DateTime(_day.year, _day.month, _day.day);
    final routes = await LastMileRouteService.fetchRoutesForDate(day);
    if (mounted) {
      setState(() {
        _routes = routes;
        _selected = routes.isNotEmpty ? routes.first : null;
        _loading = false;
      });
    }
  }

  Future<void> _runOptimize() async {
    final pending = await LastMileOrderService.fetchPending();
    if (pending.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingen ventende ordre å optimalisere')),
      );
      return;
    }
    if (widget.fleet == null || widget.fleet!.maviVehicles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Synkroniser flåte fra DriftPro først')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final day = DateTime(_day.year, _day.month, _day.day);
      final plans = await LastMileRouteService.runOptimization(
        routeDate: day,
        orderIds: pending.map((o) => o.id).toList(),
      );
      await LastMileRouteService.persistPlans(
        routeDate: day,
        plans: plans,
        fleet: widget.fleet!.maviVehicles,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${plans.length} ruter optimalisert (VRPTW)')),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Optimalisering feilet: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publishSelected() async {
    if (_selected == null) return;
    setState(() => _busy = true);
    final routeId = _selected!.id;
    await LastMileRouteService.publishRoute(routeId);
    final token = await LmTrackingService.getPublicUrl(routeId);
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            token != null
                ? 'Publisert. Kundesporing: ?track=$token'
                : 'Rute publisert til sjåfør',
          ),
          duration: const Duration(seconds: 8),
        ),
      );
      _load();
    }
  }

  void _moveStop(int from, int to) {
    if (_selected == null) return;
    final stops = List<LmRouteStop>.from(_selected!.stops);
    if (to < 0 || to >= stops.length) return;
    final item = stops.removeAt(from);
    stops.insert(to, item);
    setState(() {
      _selected = LmRoute(
        id: _selected!.id,
        companyId: _selected!.companyId,
        routeDate: _selected!.routeDate,
        partnerVehicleId: _selected!.partnerVehicleId,
        partnerId: _selected!.partnerId,
        status: _selected!.status,
        stops: stops,
        unitCode: _selected!.unitCode,
        driverName: _selected!.driverName,
      );
    });
    LastMileRouteService.reorderStops(_selected!.id, stops.map((s) => s.id).toList());
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final stops = _selected?.stops ?? [];
    final markers = <Marker>[];
    for (final s in stops) {
      final o = s.order;
      if (o?.lat == null || o?.lng == null) continue;
      markers.add(
        Marker(
          point: LatLng(o!.lat!, o.lng!),
          width: 36,
          height: 36,
          child: CircleAvatar(
            backgroundColor: DriftProTheme.primaryGreen,
            child: Text('${s.sequence}', style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ),
      );
    }

    var center = const LatLng(59.95, 10.75);
    if (markers.isNotEmpty) center = markers.first.point;

    return Row(
      children: [
        SizedBox(
          width: 280,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        setState(() => _day = _day.subtract(const Duration(days: 1)));
                        _load();
                      },
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text(
                        '${_day.day}.${_day.month}.${_day.year}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        setState(() => _day = _day.add(const Duration(days: 1)));
                        _load();
                      },
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _runOptimize,
                        icon: const Icon(Icons.auto_fix_high),
                        label: const Text('VRPTW optimaliser'),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _busy || _selected == null ? null : _publishSelected,
                        icon: const Icon(Icons.publish),
                        label: const Text('Publiser rute'),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _routes.length,
                  itemBuilder: (ctx, i) {
                    final r = _routes[i];
                    return ListTile(
                      selected: _selected?.id == r.id,
                      title: Text(r.unitCode ?? 'Bil'),
                      subtitle: Text('${r.stops.length} stopp · ${r.status}'),
                      onTap: () => setState(() => _selected = r),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          flex: 2,
          child: FlutterMap(
            options: MapOptions(initialCenter: center, initialZoom: 10),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'no.driftpro.ruteplan',
              ),
              MarkerLayer(markers: markers),
            ],
          ),
        ),
        SizedBox(
          width: 300,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _selected == null ? 'Velg rute' : '${_selected!.unitCode} · ${_selected!.driverName ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              if (_busy) const LinearProgressIndicator(),
              Expanded(
                child: ReorderableListView.builder(
                  itemCount: stops.length,
                  onReorder: _moveStop,
                  itemBuilder: (ctx, i) {
                    final s = stops[i];
                    final o = s.order;
                    return ListTile(
                      key: ValueKey(s.id),
                      leading: Text('${s.sequence}'),
                      title: Text(o?.customerName ?? 'Stopp'),
                      subtitle: Text(o?.addressLine ?? ''),
                      trailing: const Icon(Icons.drag_handle),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
