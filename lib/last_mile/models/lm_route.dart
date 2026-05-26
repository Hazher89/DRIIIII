import 'lm_order.dart';

class LmRouteStop {
  final String id;
  final String routeId;
  final int sequence;
  final String? lmOrderId;
  final LmOrder? order;
  final DateTime? plannedArrivalAt;
  final String status;

  const LmRouteStop({
    required this.id,
    required this.routeId,
    required this.sequence,
    this.lmOrderId,
    this.order,
    this.plannedArrivalAt,
    this.status = 'pending',
  });

  factory LmRouteStop.fromJson(Map<String, dynamic> json, {LmOrder? order}) {
    DateTime? dt(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());
    return LmRouteStop(
      id: json['id'] as String,
      routeId: json['route_id'] as String,
      sequence: json['sequence'] as int,
      lmOrderId: json['lm_order_id'] as String?,
      order: order,
      plannedArrivalAt: dt(json['planned_arrival_at']),
      status: json['status'] as String? ?? 'pending',
    );
  }
}

class LmRoute {
  final String id;
  final String companyId;
  final DateTime routeDate;
  final String partnerVehicleId;
  final String partnerId;
  final String? shiftId;
  final String? driverProfileId;
  final String status;
  final double? totalWeightKg;
  final double? payloadLimitKg;
  final String? notes;
  final List<LmRouteStop> stops;
  final String? unitCode;
  final String? driverName;

  const LmRoute({
    required this.id,
    required this.companyId,
    required this.routeDate,
    required this.partnerVehicleId,
    required this.partnerId,
    this.shiftId,
    this.driverProfileId,
    this.status = 'draft',
    this.totalWeightKg,
    this.payloadLimitKg,
    this.notes,
    this.stops = const [],
    this.unitCode,
    this.driverName,
  });

  factory LmRoute.fromJson(
    Map<String, dynamic> json, {
    List<LmRouteStop> stops = const [],
    String? unitCode,
    String? driverName,
  }) {
    DateTime day(dynamic v) {
      if (v is String) return DateTime.parse(v.split('T').first);
      return DateTime.now();
    }

    return LmRoute(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      routeDate: day(json['route_date']),
      partnerVehicleId: json['partner_vehicle_id'] as String,
      partnerId: json['partner_id'] as String,
      shiftId: json['shift_id'] as String?,
      driverProfileId: json['driver_profile_id'] as String?,
      status: json['status'] as String? ?? 'draft',
      totalWeightKg: (json['total_weight_kg'] as num?)?.toDouble(),
      payloadLimitKg: (json['payload_limit_kg'] as num?)?.toDouble(),
      notes: json['notes'] as String?,
      stops: stops,
      unitCode: unitCode,
      driverName: driverName,
    );
  }
}
