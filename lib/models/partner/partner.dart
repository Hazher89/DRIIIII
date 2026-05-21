class Partner {
  final String id;
  final String companyId;
  final String? orgNumber;
  final String name;
  final String? tradeName;
  final String? ownerName;
  final String? phone;
  final String? email;
  final String? address;
  final String? postalCode;
  final String? city;
  final String? country;
  final String? notes;
  final int vehicleCountRegistered;
  final int? vehicleMaxPayloadKg;
  final bool? euApproved;
  final bool hasTransportLicense;
  final int transportLicenseCount;
  final int? employeeCount;
  final String auditStatus;
  final String? auditPlate;
  final Map<String, dynamic>? brregSnapshot;
  final DateTime? lastMeetingAt;
  final DateTime? nextMeetingAt;
  final DateTime? lastAuditAt;
  final DateTime? nextAuditAt;
  final bool isActive;
  /// Kun bil-eier får ruter, SMS og aksept for alle MAVI under bedriften.
  final bool routesOwnerOnly;
  final DateTime createdAt;

  Partner({
    required this.id,
    required this.companyId,
    this.orgNumber,
    required this.name,
    this.tradeName,
    this.ownerName,
    this.phone,
    this.email,
    this.address,
    this.postalCode,
    this.city,
    this.country,
    this.notes,
    this.vehicleCountRegistered = 0,
    this.vehicleMaxPayloadKg,
    this.euApproved,
    this.hasTransportLicense = false,
    this.transportLicenseCount = 0,
    this.employeeCount,
    this.auditStatus = 'ukjent',
    this.auditPlate,
    this.brregSnapshot,
    this.lastMeetingAt,
    this.nextMeetingAt,
    this.lastAuditAt,
    this.nextAuditAt,
    this.isActive = true,
    this.routesOwnerOnly = false,
    required this.createdAt,
  });

  factory Partner.fromJson(Map<String, dynamic> json) {
    return Partner(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      orgNumber: json['org_number'] as String?,
      name: json['name'] as String,
      tradeName: json['trade_name'] as String?,
      ownerName: json['owner_name'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      address: json['address'] as String?,
      postalCode: json['postal_code'] as String?,
      city: json['city'] as String?,
      country: json['country'] as String?,
      notes: json['notes'] as String?,
      vehicleCountRegistered: json['vehicle_count_registered'] as int? ?? 0,
      vehicleMaxPayloadKg: json['vehicle_max_payload_kg'] as int?,
      euApproved: json['eu_approved'] as bool?,
      hasTransportLicense: json['has_transport_license'] as bool? ?? false,
      transportLicenseCount: json['transport_license_count'] as int? ?? 0,
      employeeCount: json['employee_count'] as int?,
      auditStatus: json['audit_status'] as String? ?? 'ukjent',
      auditPlate: json['audit_plate'] as String?,
      brregSnapshot: json['brreg_snapshot'] as Map<String, dynamic>?,
      lastMeetingAt: json['last_meeting_at'] != null
          ? DateTime.parse(json['last_meeting_at'] as String)
          : null,
      nextMeetingAt: json['next_meeting_at'] != null
          ? DateTime.parse(json['next_meeting_at'] as String)
          : null,
      lastAuditAt: json['last_audit_at'] != null
          ? DateTime.parse(json['last_audit_at'] as String)
          : null,
      nextAuditAt: json['next_audit_at'] != null
          ? DateTime.parse(json['next_audit_at'] as String)
          : null,
      isActive: json['is_active'] as bool? ?? true,
      routesOwnerOnly: json['routes_owner_only'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toInsertJson(String companyId, {String? createdBy}) {
    return {
      'company_id': companyId,
      'org_number': orgNumber,
      'name': name,
      'trade_name': tradeName,
      'owner_name': ownerName,
      'phone': phone,
      'email': email,
      'address': address,
      'postal_code': postalCode,
      'city': city,
      'country': country,
      'notes': notes,
      'vehicle_count_registered': vehicleCountRegistered,
      'vehicle_max_payload_kg': vehicleMaxPayloadKg,
      'eu_approved': euApproved,
      'has_transport_license': hasTransportLicense,
      'transport_license_count': transportLicenseCount,
      'employee_count': employeeCount,
      'audit_status': auditStatus,
      'audit_plate': auditPlate,
      'brreg_snapshot': brregSnapshot,
      'last_meeting_at': lastMeetingAt?.toIso8601String(),
      'next_meeting_at': nextMeetingAt?.toIso8601String(),
      'last_audit_at': lastAuditAt?.toIso8601String().split('T').first,
      'next_audit_at': nextAuditAt?.toIso8601String().split('T').first,
      if (createdBy != null) 'created_by': createdBy,
    };
  }

  Map<String, dynamic> toUpdateJson() {
    return {
      'org_number': orgNumber,
      'name': name,
      'trade_name': tradeName,
      'owner_name': ownerName,
      'phone': phone,
      'email': email,
      'address': address,
      'postal_code': postalCode,
      'city': city,
      'country': country,
      'notes': notes,
      'vehicle_count_registered': vehicleCountRegistered,
      'vehicle_max_payload_kg': vehicleMaxPayloadKg,
      'eu_approved': euApproved,
      'has_transport_license': hasTransportLicense,
      'transport_license_count': transportLicenseCount,
      'employee_count': employeeCount,
      'audit_status': auditStatus,
      'audit_plate': auditPlate,
      'brreg_snapshot': brregSnapshot,
      'last_meeting_at': lastMeetingAt?.toIso8601String(),
      'next_meeting_at': nextMeetingAt?.toIso8601String(),
      'last_audit_at': lastAuditAt?.toIso8601String().split('T').first,
      'next_audit_at': nextAuditAt?.toIso8601String().split('T').first,
      'is_active': isActive,
      'routes_owner_only': routesOwnerOnly,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  String get auditStatusLabel {
    switch (auditStatus) {
      case 'planlagt':
        return 'Planlagt';
      case 'ok':
        return 'OK';
      case 'avvik':
        return 'Avvik';
      case 'utlopt':
        return 'Utløpt';
      default:
        return 'Ukjent';
    }
  }
}
