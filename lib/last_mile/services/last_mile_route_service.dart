import '../../core/services/partner/partner_service.dart';
import '../../core/services/supabase_service.dart';
import '../models/lm_order.dart';
import '../models/lm_route.dart';
import 'last_mile_order_service.dart';
import 'vrptw_optimizer.dart';

class LastMileRouteService {
  LastMileRouteService._();

  static Future<String?> _companyId() => SupabaseService.getCurrentCompanyId();

  static Future<List<LmRoute>> fetchRoutesForDate(DateTime day) async {
    final cid = await _companyId();
    if (cid == null) return [];
    final d = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

    final rows = await SupabaseService.client
        .from('lm_routes')
        .select()
        .eq('company_id', cid)
        .eq('route_date', d)
        .order('created_at');

    final routes = <LmRoute>[];
    for (final raw in rows as List) {
      final json = raw as Map<String, dynamic>;
      final vid = json['partner_vehicle_id'] as String;
      final vehicle = await SupabaseService.client
          .from('partner_vehicles')
          .select('unit_code, driver_name')
          .eq('id', vid)
          .maybeSingle();
      final stops = await _fetchStops(json['id'] as String);
      routes.add(
        LmRoute.fromJson(
          json,
          stops: stops,
          unitCode: vehicle?['unit_code'] as String?,
          driverName: vehicle?['driver_name'] as String?,
        ),
      );
    }
    return routes;
  }

  static Future<List<LmRouteStop>> _fetchStops(String routeId) async {
    final rows = await SupabaseService.client
        .from('lm_route_stops')
        .select()
        .eq('route_id', routeId)
        .order('sequence');

    final stops = <LmRouteStop>[];
    for (final raw in rows as List) {
      final json = raw as Map<String, dynamic>;
      LmOrder? order;
      final oid = json['lm_order_id'] as String?;
      if (oid != null) {
        final list = await LastMileOrderService.fetchByIds([oid]);
        if (list.isNotEmpty) order = list.first;
      }
      stops.add(LmRouteStop.fromJson(json, order: order));
    }
    return stops;
  }

  static Future<List<VrptwPlan>> runOptimization({
    required DateTime routeDate,
    required List<String> orderIds,
  }) async {
    final cid = await _companyId();
    if (cid == null) return [];

    final orders = await LastMileOrderService.fetchByIds(orderIds);
    final fleet = PartnerService.filterMaviFleetOnly(
      await PartnerService.fetchCompanyFleet(cid, forPlanning: true),
    );

    final vehicles = fleet
        .map(
          (r) => VrptwVehicle(
            vehicleId: r.vehicle.id,
            partnerId: r.partner.id,
            payloadKg: (r.vehicle.payloadKg ?? 800).toDouble(),
          ),
        )
        .toList();

    final run = await SupabaseService.client
        .from('lm_optimization_runs')
        .insert({
          'company_id': cid,
          'route_date': routeDate.toIso8601String().split('T').first,
          'status': 'running',
          'input_order_ids': orderIds,
        })
        .select()
        .single();

    final plans = VrptwOptimizer.optimize(
      orders: orders,
      vehicles: vehicles,
      routeDate: routeDate,
    );

    await SupabaseService.client.from('lm_optimization_runs').update({
      'status': 'completed',
      'result': {'plans': plans.map((p) => {'vehicle_id': p.vehicleId, 'order_ids': p.orderIds}).toList()},
      'completed_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', run['id']);

    return plans;
  }

  static Future<List<LmRoute>> persistPlans({
    required DateTime routeDate,
    required List<VrptwPlan> plans,
    required List<FleetPartnerVehicleRow> fleet,
  }) async {
    final cid = await _companyId();
    if (cid == null) return [];

    final created = <LmRoute>[];
    final d = routeDate.toIso8601String().split('T').first;

    for (final plan in plans) {
      final row = fleet.firstWhere((f) => f.vehicle.id == plan.vehicleId);
      final routeRow = await SupabaseService.client
          .from('lm_routes')
          .insert({
            'company_id': cid,
            'route_date': d,
            'partner_vehicle_id': row.vehicle.id,
            'partner_id': row.partner.id,
            'status': 'ready',
            'total_weight_kg': plan.totalWeightKg,
            'payload_limit_kg': row.vehicle.payloadKg ?? 800,
          })
          .select()
          .single();

      final routeId = routeRow['id'] as String;
      var seq = 1;
      for (var i = 0; i < plan.orderIds.length; i++) {
        final oid = plan.orderIds[i];
        await SupabaseService.client.from('lm_route_stops').insert({
          'company_id': cid,
          'route_id': routeId,
          'lm_order_id': oid,
          'sequence': seq++,
          if (i < plan.estimatedArrivals.length)
            'planned_arrival_at': plan.estimatedArrivals[i].toUtc().toIso8601String(),
        });
        await LastMileOrderService.updateStatus(oid, 'planned');
      }

      final stops = await _fetchStops(routeId);
      created.add(
        LmRoute.fromJson(
          routeRow,
          stops: stops,
          unitCode: row.vehicle.unitCode,
          driverName: row.vehicle.driverName,
        ),
      );
    }
    return created;
  }

  static Future<void> reorderStops(String routeId, List<String> stopIdsInOrder) async {
    for (var i = 0; i < stopIdsInOrder.length; i++) {
      await SupabaseService.client
          .from('lm_route_stops')
          .update({'sequence': i + 1})
          .eq('id', stopIdsInOrder[i]);
    }
  }

  static Future<void> publishRoute(String routeId) async {
    final cid = await _companyId();
    if (cid == null) return;

    final stops = await _fetchStops(routeId);

    await SupabaseService.client.from('lm_routes').update({
      'status': 'published',
      'published_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', routeId);

    for (final s in stops) {
      if (s.lmOrderId != null) {
        await LastMileOrderService.updateStatus(s.lmOrderId!, 'assigned');
      }
    }

    await SupabaseService.client.from('lm_tracking_sessions').insert({
      'company_id': cid,
      'route_id': routeId,
      'expires_at': DateTime.now().add(const Duration(days: 2)).toUtc().toIso8601String(),
    });
  }

  static Future<List<LmRoute>> fetchDriverRoutes(String profileId, DateTime day) async {
    final cid = await _companyId();
    if (cid == null) return [];
    final d = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

    final rows = await SupabaseService.client
        .from('lm_routes')
        .select('*, partner_vehicles(unit_code, driver_name)')
        .eq('company_id', cid)
        .eq('route_date', d)
        .inFilter('status', ['published', 'in_progress'])
        .or('driver_profile_id.eq.$profileId,driver_profile_id.is.null');

    final routes = <LmRoute>[];
    for (final raw in rows as List) {
      final json = raw as Map<String, dynamic>;
      final vehicle = json['partner_vehicles'] as Map<String, dynamic>?;
      final stops = await _fetchStops(json['id'] as String);
      routes.add(
        LmRoute.fromJson(
          json,
          stops: stops,
          unitCode: vehicle?['unit_code'] as String?,
          driverName: vehicle?['driver_name'] as String?,
        ),
      );
    }
    return routes;
  }

  static Future<void> startRoute(String routeId, String driverProfileId) async {
    await SupabaseService.client.from('lm_routes').update({
      'status': 'in_progress',
      'driver_profile_id': driverProfileId,
    }).eq('id', routeId);
  }
}
