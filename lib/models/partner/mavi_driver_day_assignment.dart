class MaviDriverDayAssignment {
  final String id;
  final String companyId;
  final String partnerVehicleId;
  final DateTime assignmentDate;
  final String shiftId;
  final String? notes;
  final DateTime? updatedAt;

  const MaviDriverDayAssignment({
    required this.id,
    required this.companyId,
    required this.partnerVehicleId,
    required this.assignmentDate,
    required this.shiftId,
    this.notes,
    this.updatedAt,
  });

  factory MaviDriverDayAssignment.fromJson(Map<String, dynamic> json) {
    return MaviDriverDayAssignment(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      partnerVehicleId: json['partner_vehicle_id'] as String,
      assignmentDate: DateTime.parse(json['assignment_date'] as String),
      shiftId: json['shift_id'] as String,
      notes: json['notes'] as String?,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toUpsertJson() {
    return {
      'company_id': companyId,
      'partner_vehicle_id': partnerVehicleId,
      'assignment_date': assignmentDate.toIso8601String().split('T').first,
      'shift_id': shiftId,
      'notes': notes,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }
}
