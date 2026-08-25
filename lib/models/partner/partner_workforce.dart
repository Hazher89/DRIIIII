class PartnerStaff {
  final String id;
  final String partnerId;
  final String companyId;
  final String fullName;
  final String? phone;
  final String? address;
  final String? postalCode;
  final String? city;
  final String? portalAccountId;
  final String? profileId;
  final bool isActive;
  final DateTime? deactivatedAt;
  final String? notes;
  final DateTime createdAt;

  const PartnerStaff({
    required this.id,
    required this.partnerId,
    required this.companyId,
    required this.fullName,
    this.phone,
    this.address,
    this.postalCode,
    this.city,
    this.portalAccountId,
    this.profileId,
    this.isActive = true,
    this.deactivatedAt,
    this.notes,
    required this.createdAt,
  });

  factory PartnerStaff.fromJson(Map<String, dynamic> json) {
    return PartnerStaff(
      id: json['id'] as String,
      partnerId: json['partner_id'] as String,
      companyId: json['company_id'] as String,
      fullName: json['full_name'] as String,
      phone: json['phone'] as String?,
      address: json['address'] as String?,
      postalCode: json['postal_code'] as String?,
      city: json['city'] as String?,
      portalAccountId: json['portal_account_id'] as String?,
      profileId: json['profile_id'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      deactivatedAt: json['deactivated_at'] != null
          ? DateTime.parse(json['deactivated_at'] as String)
          : null,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toInsertJson() => {
        'partner_id': partnerId,
        'company_id': companyId,
        'full_name': fullName,
        'phone': phone,
        'address': address,
        'postal_code': postalCode,
        'city': city,
        'notes': notes,
        'is_active': isActive,
      };

  String get addressLine {
    final loc = [postalCode, city]
        .whereType<String>()
        .where((e) => e.trim().isNotEmpty)
        .join(' ');
    final parts = [address, if (loc.isNotEmpty) loc]
        .whereType<String>()
        .where((e) => e.trim().isNotEmpty);
    return parts.join(', ');
  }
}

class PartnerTimeEntry {
  final String id;
  final String partnerId;
  final String companyId;
  final String staffId;
  final DateTime clockIn;
  final DateTime? clockOut;
  final String? note;
  final String source;
  final bool isDeleted;
  final String? staffName;

  const PartnerTimeEntry({
    required this.id,
    required this.partnerId,
    required this.companyId,
    required this.staffId,
    required this.clockIn,
    this.clockOut,
    this.note,
    this.source = 'mobile',
    this.isDeleted = false,
    this.staffName,
  });

  factory PartnerTimeEntry.fromJson(Map<String, dynamic> json) {
    final staff = json['partner_staff'];
    String? name;
    if (staff is Map) name = staff['full_name'] as String?;
    return PartnerTimeEntry(
      id: json['id'] as String,
      partnerId: json['partner_id'] as String,
      companyId: json['company_id'] as String,
      staffId: json['staff_id'] as String,
      clockIn: DateTime.parse(json['clock_in'] as String),
      clockOut: json['clock_out'] != null
          ? DateTime.parse(json['clock_out'] as String)
          : null,
      note: json['note'] as String?,
      source: json['source'] as String? ?? 'mobile',
      isDeleted: json['is_deleted'] as bool? ?? false,
      staffName: name,
    );
  }

  Duration? get duration {
    if (clockOut == null) return null;
    return clockOut!.difference(clockIn);
  }

  bool get isOpen => clockOut == null && !isDeleted;
}

class PartnerTimeAudit {
  final String id;
  final String entryId;
  final String action;
  final String? changedBy;
  final DateTime changedAt;
  final Map<String, dynamic>? beforeJson;
  final Map<String, dynamic>? afterJson;
  final String? reason;
  final String? changedByName;

  const PartnerTimeAudit({
    required this.id,
    required this.entryId,
    required this.action,
    this.changedBy,
    required this.changedAt,
    this.beforeJson,
    this.afterJson,
    this.reason,
    this.changedByName,
  });

  factory PartnerTimeAudit.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'];
    String? name;
    if (profile is Map) {
      name = profile['full_name'] as String? ?? profile['email'] as String?;
    }
    return PartnerTimeAudit(
      id: json['id'] as String,
      entryId: json['entry_id'] as String,
      action: json['action'] as String,
      changedBy: json['changed_by'] as String?,
      changedAt: DateTime.parse(json['changed_at'] as String),
      beforeJson: json['before_json'] as Map<String, dynamic>?,
      afterJson: json['after_json'] as Map<String, dynamic>?,
      reason: json['reason'] as String?,
      changedByName: name,
    );
  }
}
