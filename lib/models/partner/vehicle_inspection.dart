/// Mal for utstyrskontroll på bil (reppe, dekk, osv.).
import '../../core/services/partner/mavi_unit_codes.dart';
import 'partner_links.dart';

class VehicleInspectionTemplate {
  static const items = <VehicleInspectionField>[
    VehicleInspectionField(key: 'repp', label: 'Repp / presenning', type: InspectionFieldType.okAvvik),
    VehicleInspectionField(key: 'lastestopp', label: 'Lastestopp / sperrer', type: InspectionFieldType.okAvvik),
    VehicleInspectionField(key: 'dekk_foran_mm', label: 'Dekkdybde foran (mm)', type: InspectionFieldType.number),
    VehicleInspectionField(key: 'dekk_bak_mm', label: 'Dekkdybde bak (mm)', type: InspectionFieldType.number),
    VehicleInspectionField(key: 'bremser', label: 'Bremser', type: InspectionFieldType.okAvvik),
    VehicleInspectionField(key: 'lys', label: 'Lys og blinklys', type: InspectionFieldType.okAvvik),
    VehicleInspectionField(key: 'refleks', label: 'Refleks og merking', type: InspectionFieldType.okAvvik),
    VehicleInspectionField(key: 'spennreim', label: 'Spennreim / surring', type: InspectionFieldType.okAvvik),
    VehicleInspectionField(key: 'lofteinnretning', label: 'Løfte-/lasteinnretning', type: InspectionFieldType.okAvvik),
    VehicleInspectionField(key: 'karosseri', label: 'Karosseri / rust', type: InspectionFieldType.okAvvik),
    VehicleInspectionField(key: 'annet', label: 'Annet / kommentar', type: InspectionFieldType.text),
  ];
}

enum InspectionFieldType { okAvvik, number, text }

class VehicleInspectionField {
  final String key;
  final String label;
  final InspectionFieldType type;

  const VehicleInspectionField({
    required this.key,
    required this.label,
    required this.type,
  });
}

class PartnerVehicleInspection {
  final String id;
  final String partnerId;
  final String companyId;
  final String? partnerVehicleId;
  final String? registrationNumber;
  final String? unitCode;
  final DateTime inspectedAt;
  final String? inspectedBy;
  final Map<String, dynamic> checklist;
  final bool hasDeviation;
  final String? deviationNotes;
  final String? deviationAssignee;
  final DateTime? nextInspectionAt;
  final DateTime? followUpDueAt;
  final DateTime? followUpAcknowledgedAt;
  final bool isArchived;
  final DateTime createdAt;

  /// Joined fra profiles ved henting.
  final String? inspectedByName;

  /// Joined fra partners ved firmavis henting.
  final String? partnerName;
  final String? partnerTradeName;

  const PartnerVehicleInspection({
    required this.id,
    required this.partnerId,
    required this.companyId,
    this.partnerVehicleId,
    this.registrationNumber,
    this.unitCode,
    required this.inspectedAt,
    this.inspectedBy,
    this.checklist = const {},
    this.hasDeviation = false,
    this.deviationNotes,
    this.deviationAssignee,
    this.nextInspectionAt,
    this.followUpDueAt,
    this.followUpAcknowledgedAt,
    this.isArchived = true,
    required this.createdAt,
    this.inspectedByName,
    this.partnerName,
    this.partnerTradeName,
  });

  factory PartnerVehicleInspection.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      if (v is String && v.length == 10) return DateTime.tryParse(v);
      return DateTime.tryParse(v.toString());
    }

    final partnersRaw = json['partners'];
    Map<String, dynamic>? partnersMap;
    if (partnersRaw is Map) {
      partnersMap = Map<String, dynamic>.from(partnersRaw);
    }

    return PartnerVehicleInspection(
      id: json['id'] as String,
      partnerId: json['partner_id'] as String,
      companyId: json['company_id'] as String,
      partnerVehicleId: json['partner_vehicle_id'] as String?,
      registrationNumber: json['registration_number'] as String?,
      unitCode: json['unit_code'] as String?,
      inspectedAt: DateTime.parse(json['inspected_at'] as String),
      inspectedBy: json['inspected_by'] as String?,
      checklist: Map<String, dynamic>.from(json['checklist'] as Map? ?? {}),
      hasDeviation: json['has_deviation'] as bool? ?? false,
      deviationNotes: json['deviation_notes'] as String?,
      deviationAssignee: json['deviation_assignee'] as String?,
      nextInspectionAt: parseDate(json['next_inspection_at']),
      followUpDueAt: parseDate(json['follow_up_due_at']),
      followUpAcknowledgedAt: json['follow_up_acknowledged_at'] != null
          ? DateTime.parse(json['follow_up_acknowledged_at'] as String)
          : null,
      isArchived: json['is_archived'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      inspectedByName: json['profiles'] != null
          ? json['profiles']['full_name'] as String?
          : null,
      partnerName: partnersMap?['name'] as String?,
      partnerTradeName: partnersMap?['trade_name'] as String?,
    );
  }

  String get partnerDisplayName {
    final trade = (partnerTradeName ?? '').trim();
    if (trade.isNotEmpty) return trade;
    final name = (partnerName ?? '').trim();
    return name.isEmpty ? 'Ukjent bedrift' : name;
  }

  String get vehicleLabel {
    final reg = (registrationNumber ?? '').trim();
    final unit = (unitCode ?? '').trim();
    if (reg.isNotEmpty && unit.isNotEmpty) return '$reg · $unit';
    if (reg.isNotEmpty) return reg;
    if (unit.isNotEmpty) return unit;
    return 'Bil';
  }

  /// Siste kontroll for et kjøretøy (match på id, MAVI eller reg.nr).
  static PartnerVehicleInspection? latestForVehicle(
    PartnerVehicle vehicle,
    Iterable<PartnerVehicleInspection> inspections,
  ) {
    final unit = vehicle.unitCode.trim();
    final reg = vehicle.registrationNumber.trim();
    PartnerVehicleInspection? best;
    for (final ins in inspections) {
      final matchesId =
          ins.partnerVehicleId != null && ins.partnerVehicleId == vehicle.id;
      final matchesUnit = unit.isNotEmpty &&
          ins.unitCode != null &&
          ins.unitCode!.trim() == unit;
      final matchesReg = reg.isNotEmpty &&
          reg != MaviUnitCodes.regNrPlaceholder &&
          ins.registrationNumber != null &&
          ins.registrationNumber!.trim().toUpperCase() ==
              reg.toUpperCase();
      if (!matchesId && !matchesUnit && !matchesReg) continue;
      if (best == null || ins.inspectedAt.isAfter(best.inspectedAt)) {
        best = ins;
      }
    }
    return best;
  }

  static Map<String, PartnerVehicleInspection> latestByVehicleId(
    Iterable<PartnerVehicle> vehicles,
    Iterable<PartnerVehicleInspection> inspections,
  ) {
    final out = <String, PartnerVehicleInspection>{};
    for (final v in vehicles) {
      if (v.id.isEmpty) continue;
      final latest = latestForVehicle(v, inspections);
      if (latest != null) out[v.id] = latest;
    }
    return out;
  }

  String get stampLine {
    final name = inspectedByName?.trim().isNotEmpty == true
        ? inspectedByName!
        : 'Ukjent';
    final local = inspectedAt.toLocal();
    final ts =
        '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')}.${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return 'Kontroll stempling · $name · $ts';
  }

  Map<String, dynamic> toInsertJson({required String inspectedBy}) {
    return {
      'partner_id': partnerId,
      'company_id': companyId,
      if (partnerVehicleId != null) 'partner_vehicle_id': partnerVehicleId,
      if (registrationNumber != null) 'registration_number': registrationNumber,
      if (unitCode != null) 'unit_code': unitCode,
      'inspected_at': inspectedAt.toIso8601String(),
      'inspected_by': inspectedBy,
      'checklist': checklist,
      'has_deviation': hasDeviation,
      'deviation_notes': deviationNotes,
      if (deviationAssignee != null) 'deviation_assignee': deviationAssignee,
      if (nextInspectionAt != null)
        'next_inspection_at': nextInspectionAt!.toIso8601String().split('T').first,
      if (followUpDueAt != null)
        'follow_up_due_at': followUpDueAt!.toIso8601String().split('T').first,
      'is_archived': isArchived,
    };
  }

  bool get followUpOpen =>
      hasDeviation && followUpAcknowledgedAt == null && followUpDueAt != null;

  bool get followUpOverdue =>
      followUpOpen && followUpDueAt!.isBefore(DateTime.now());
}
