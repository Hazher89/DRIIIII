import 'package:flutter/material.dart';

class FleetShiftDefinition {
  final String id;
  final String companyId;
  final String name;
  final String? description;
  final String colorHex;
  final String? regionGroup;
  final String? timeBand;
  final String shiftKind; // route_ops | availability
  final int sortOrder;
  final bool isArchived;
  final DateTime createdAt;

  FleetShiftDefinition({
    required this.id,
    required this.companyId,
    required this.name,
    this.description,
    required this.colorHex,
    this.regionGroup,
    this.timeBand,
    required this.shiftKind,
    required this.sortOrder,
    required this.isArchived,
    required this.createdAt,
  });

  factory FleetShiftDefinition.fromJson(Map<String, dynamic> json) {
    return FleetShiftDefinition(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      colorHex: json['color_hex'] as String? ?? '#2E7D32',
      regionGroup: json['region_group'] as String?,
      timeBand: json['time_band'] as String?,
      shiftKind: json['shift_kind'] as String? ?? 'route_ops',
      sortOrder: json['sort_order'] as int? ?? 0,
      isArchived: json['is_archived'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Color get color {
    try {
      var h = colorHex.replaceFirst('#', '');
      if (h.length == 6) h = 'FF$h';
      return Color(int.parse(h, radix: 16));
    } catch (_) {
      return const Color(0xFF2E7D32);
    }
  }

  bool get isAvailability => shiftKind == 'availability';
}

class PartnerVehicleFleetSnapshot {
  final String id;
  final String companyId;
  final String partnerVehicleId;
  final DateTime snapshotDate;
  final String shiftId;
  final String status; // har_rute | ledig | fri | gitt_bort
  final String? partnerRouteShareId;
  final String? notes;
  final DateTime createdAt;

  PartnerVehicleFleetSnapshot({
    required this.id,
    required this.companyId,
    required this.partnerVehicleId,
    required this.snapshotDate,
    required this.shiftId,
    required this.status,
    this.partnerRouteShareId,
    this.notes,
    required this.createdAt,
  });

  factory PartnerVehicleFleetSnapshot.fromJson(Map<String, dynamic> json) {
    return PartnerVehicleFleetSnapshot(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      partnerVehicleId: json['partner_vehicle_id'] as String,
      snapshotDate: DateTime.parse(json['snapshot_date'] as String),
      shiftId: json['shift_id'] as String,
      status: json['status'] as String,
      partnerRouteShareId: json['partner_route_share_id'] as String?,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toUpsertJson() {
    return {
      'company_id': companyId,
      'partner_vehicle_id': partnerVehicleId,
      'snapshot_date': snapshotDate.toIso8601String().split('T').first,
      'shift_id': shiftId,
      'status': status,
      'partner_route_share_id': partnerRouteShareId,
      'notes': notes,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }
}
