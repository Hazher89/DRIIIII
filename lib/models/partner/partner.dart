enum EcoDrivingStatus {
  completed,
  required,
  overdue;

  static EcoDrivingStatus fromDeadline(DateTime? deadline, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    if (deadline != null) {
      final d = DateTime(deadline.year, deadline.month, deadline.day);
      if (d.isBefore(day)) return EcoDrivingStatus.overdue;
    }
    return EcoDrivingStatus.required;
  }
}

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
  /// ECO Driving Kurs gjennomført.
  final bool ecoDrivingCompleted;
  /// Frist for å ta kurset (typisk 3 måneder fra registrering).
  final DateTime? ecoDrivingDeadline;
  /// Når kurset ble registrert som tatt.
  final DateTime? ecoDrivingCompletedAt;
  final DateTime createdAt;

  /// Unik kode i bot-/trekk-saksnummer (BOT-{caseCode}-2026-0001).
  final String? caseCode;
  /// Partner workforce (ansatte + stempling) — per-bedrift (se også company-wide flag).
  final bool workforceEnabled;

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
    this.ecoDrivingCompleted = false,
    this.ecoDrivingDeadline,
    this.ecoDrivingCompletedAt,
    required this.createdAt,
    this.caseCode,
    this.workforceEnabled = false,
  });

  EcoDrivingStatus get ecoDrivingStatus {
    if (ecoDrivingCompleted) return EcoDrivingStatus.completed;
    return EcoDrivingStatus.fromDeadline(ecoDrivingDeadline);
  }

  bool get hasEcoDrivingGlow => ecoDrivingCompleted;

  static DateTime defaultEcoDrivingDeadline([DateTime? from]) {
    final base = from ?? DateTime.now();
    final start = DateTime(base.year, base.month, base.day);
    return start.add(const Duration(days: 90));
  }

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
      routesOwnerOnly: json['routes_owner_only'] as bool? ?? true,
      ecoDrivingCompleted: json['eco_driving_completed'] as bool? ?? false,
      ecoDrivingDeadline: json['eco_driving_deadline'] != null
          ? DateTime.parse(json['eco_driving_deadline'] as String)
          : null,
      ecoDrivingCompletedAt: json['eco_driving_completed_at'] != null
          ? DateTime.parse(json['eco_driving_completed_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      caseCode: json['case_code'] as String?,
      workforceEnabled: json['workforce_enabled'] as bool? ?? false,
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
      'eco_driving_completed': ecoDrivingCompleted,
      'eco_driving_deadline': ecoDrivingDeadline?.toIso8601String().split('T').first,
      'eco_driving_completed_at':
          ecoDrivingCompletedAt?.toIso8601String().split('T').first,
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
      'eco_driving_completed': ecoDrivingCompleted,
      'eco_driving_deadline': ecoDrivingDeadline?.toIso8601String().split('T').first,
      'eco_driving_completed_at':
          ecoDrivingCompletedAt?.toIso8601String().split('T').first,
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
