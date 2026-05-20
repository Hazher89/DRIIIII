/// Mal for utstyrskontroll på bil (reppe, dekk, osv.).
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
  });

  factory PartnerVehicleInspection.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      if (v is String && v.length == 10) return DateTime.tryParse(v);
      return DateTime.tryParse(v.toString());
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
    );
  }

  Map<String, dynamic> toInsertJson({required String inspectedBy}) {
    return {
      'partner_id': partnerId,
      'company_id': companyId,
      if (partnerVehicleId != null) 'partner_vehicle_id': partnerVehicleId,
      if (registrationNumber != null) 'registration_number': registrationNumber,
      if (unitCode != null) 'unit_code': unitCode,
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
