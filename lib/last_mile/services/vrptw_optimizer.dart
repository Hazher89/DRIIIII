import 'dart:math' as math;

import '../models/lm_order.dart';

class VrptwVehicle {
  final String vehicleId;
  final String partnerId;
  final double payloadKg;
  final double? startLat;
  final double? startLng;

  const VrptwVehicle({
    required this.vehicleId,
    required this.partnerId,
    required this.payloadKg,
    this.startLat,
    this.startLng,
  });
}

class VrptwPlan {
  final String vehicleId;
  final List<String> orderIds;
  final double totalWeightKg;
  final List<DateTime> estimatedArrivals;

  const VrptwPlan({
    required this.vehicleId,
    required this.orderIds,
    required this.totalWeightKg,
    required this.estimatedArrivals,
  });
}

/// Greedy VRPTW-heuristikk: kapasitet, tidsvinduer, geografisk clustering.
class VrptwOptimizer {
  VrptwOptimizer._();

  static const double defaultOrderWeightKg = 35;
  static const double defaultServiceMinutes = 12;
  static const double avgSpeedKmh = 35;

  static List<VrptwPlan> optimize({
    required List<LmOrder> orders,
    required List<VrptwVehicle> vehicles,
    required DateTime routeDate,
    DateTime? depotStart,
  }) {
    if (orders.isEmpty || vehicles.isEmpty) return [];

    final eligible = orders.where((o) => o.hasCoordinates).toList();
    final noCoords = orders.where((o) => !o.hasCoordinates).toList();
    final plans = <VrptwPlan>[];
    final unassigned = List<LmOrder>.from(eligible);

    final start = depotStart ?? DateTime(routeDate.year, routeDate.month, routeDate.day, 7, 0);

    for (final v in vehicles) {
      if (unassigned.isEmpty) break;

      final route = <LmOrder>[];
      final arrivals = <DateTime>[];
      var weight = 0.0;
      var time = start;
      var curLat = v.startLat ?? 59.95;
      var curLng = v.startLng ?? 10.75;

      while (unassigned.isNotEmpty) {
        LmOrder? best;
        var bestScore = double.infinity;

        for (final o in unassigned) {
          final w = o.weightKg ?? defaultOrderWeightKg;
          if (weight + w > v.payloadKg) continue;

          final dist = _km(curLat, curLng, o.lat!, o.lng!);
          final travelMin = (dist / avgSpeedKmh) * 60;
          final arrival = time.add(Duration(minutes: travelMin.round()));

          if (o.timeWindowEnd != null && arrival.isAfter(o.timeWindowEnd!)) continue;
          if (o.timeWindowStart != null && arrival.isBefore(o.timeWindowStart!)) {
            // vent til vindu åpner
            final wait = o.timeWindowStart!.difference(arrival).inMinutes;
            if (wait > 180) continue;
          }

          final score = dist + (o.timeWindowStart != null ? 0.01 * arrival.hour : 0);
          if (score < bestScore) {
            bestScore = score;
            best = o;
          }
        }

        if (best == null) break;

        final dist = _km(curLat, curLng, best.lat!, best.lng!);
        final travelMin = (dist / avgSpeedKmh) * 60;
        time = time.add(Duration(minutes: travelMin.round()));
        if (best.timeWindowStart != null && time.isBefore(best.timeWindowStart!)) {
          time = best.timeWindowStart!;
        }

        route.add(best);
        arrivals.add(time);
        weight += best.weightKg ?? defaultOrderWeightKg;
        time = time.add(Duration(minutes: defaultServiceMinutes.round()));
        curLat = best.lat!;
        curLng = best.lng!;
        unassigned.remove(best);
      }

      if (route.isNotEmpty) {
        plans.add(
          VrptwPlan(
            vehicleId: v.vehicleId,
            orderIds: route.map((o) => o.id).toList(),
            totalWeightKg: weight,
            estimatedArrivals: arrivals,
          ),
        );
      }
    }

    // Rest til første bil med ledig kapasitet
    if (unassigned.isNotEmpty && vehicles.isNotEmpty) {
      final v = vehicles.first;
      final extra = unassigned.map((o) => o.id).toList();
      if (plans.isEmpty) {
        plans.add(
          VrptwPlan(
            vehicleId: v.vehicleId,
            orderIds: extra,
            totalWeightKg: unassigned.fold<double>(
              0,
              (s, o) => s + (o.weightKg ?? defaultOrderWeightKg),
            ),
            estimatedArrivals: List.generate(extra.length, (i) => start.add(Duration(hours: i))),
          ),
        );
      } else {
        final p = plans.first;
        plans[0] = VrptwPlan(
          vehicleId: p.vehicleId,
          orderIds: [...p.orderIds, ...extra],
          totalWeightKg: p.totalWeightKg +
              unassigned.fold<double>(0, (s, o) => s + (o.weightKg ?? defaultOrderWeightKg)),
          estimatedArrivals: [
            ...p.estimatedArrivals,
            ...List.generate(extra.length, (i) => start.add(Duration(hours: i + p.orderIds.length))),
          ],
        );
      }
    }

    // Ordrer uten koordinater — legg på første plan
    if (noCoords.isNotEmpty && plans.isNotEmpty) {
      final p = plans.first;
      plans[0] = VrptwPlan(
        vehicleId: p.vehicleId,
        orderIds: [...p.orderIds, ...noCoords.map((o) => o.id)],
        totalWeightKg: p.totalWeightKg,
        estimatedArrivals: p.estimatedArrivals,
      );
    }

    return plans;
  }

  static double _km(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * math.sin(dLng / 2) * math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double d) => d * math.pi / 180;
}
