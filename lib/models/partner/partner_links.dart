class PartnerDocument {
  final String id;
  final String partnerId;
  final String companyId;
  final String title;
  final String? storagePath;
  final String? fileName;
  final String? mimeType;
  final String? notes;
  final DateTime createdAt;

  PartnerDocument({
    required this.id,
    required this.partnerId,
    required this.companyId,
    required this.title,
    this.storagePath,
    this.fileName,
    this.mimeType,
    this.notes,
    required this.createdAt,
  });

  factory PartnerDocument.fromJson(Map<String, dynamic> json) {
    return PartnerDocument(
      id: json['id'] as String,
      partnerId: json['partner_id'] as String,
      companyId: json['company_id'] as String,
      title: json['title'] as String,
      storagePath: json['storage_path'] as String?,
      fileName: json['file_name'] as String?,
      mimeType: json['mime_type'] as String?,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toInsertJson({String? createdBy}) {
    return {
      'partner_id': partnerId,
      'company_id': companyId,
      'title': title,
      'storage_path': storagePath,
      'file_name': fileName,
      'mime_type': mimeType,
      'notes': notes,
      ...?createdBy != null ? {'created_by': createdBy} : null,
    };
  }
}

class PartnerMeeting {
  final String id;
  final String partnerId;
  final String title;
  final DateTime scheduledAt;
  final bool isDirect;
  final String? location;
  final String? notes;
  final DateTime createdAt;

  PartnerMeeting({
    required this.id,
    required this.partnerId,
    required this.title,
    required this.scheduledAt,
    this.isDirect = true,
    this.location,
    this.notes,
    required this.createdAt,
  });

  factory PartnerMeeting.fromJson(Map<String, dynamic> json) {
    return PartnerMeeting(
      id: json['id'] as String,
      partnerId: json['partner_id'] as String,
      title: json['title'] as String,
      scheduledAt: DateTime.parse(json['scheduled_at'] as String),
      isDirect: json['is_direct'] as bool? ?? true,
      location: json['location'] as String?,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'partner_id': partnerId,
      'title': title,
      'scheduled_at': scheduledAt.toIso8601String(),
      'is_direct': isDirect,
      'location': location,
      'notes': notes,
    };
  }
}

class PartnerRouteShare {
  final String id;
  final String partnerId;
  final String companyId;
  final String? title;
  final String pdfStoragePath;
  final DateTime shareDate;
  final bool isDailyShare;
  final String? notes;
  final String ackStatus; // pending | accepted | rejected
  final DateTime? ackAt;
  final String? ackBy;
  final String? ackComment;
  final DateTime createdAt;

  PartnerRouteShare({
    required this.id,
    required this.partnerId,
    required this.companyId,
    this.title,
    required this.pdfStoragePath,
    required this.shareDate,
    this.isDailyShare = false,
    this.notes,
    this.ackStatus = 'pending',
    this.ackAt,
    this.ackBy,
    this.ackComment,
    required this.createdAt,
  });

  factory PartnerRouteShare.fromJson(Map<String, dynamic> json) {
    return PartnerRouteShare(
      id: json['id'] as String,
      partnerId: json['partner_id'] as String,
      companyId: json['company_id'] as String,
      title: json['title'] as String?,
      pdfStoragePath: json['pdf_storage_path'] as String,
      shareDate: DateTime.parse(json['share_date'] as String),
      isDailyShare: json['is_daily_share'] as bool? ?? false,
      notes: json['notes'] as String?,
      ackStatus: (json['ack_status'] as String?) ?? 'pending',
      ackAt: json['ack_at'] != null ? DateTime.parse(json['ack_at'] as String) : null,
      ackBy: json['ack_by'] as String?,
      ackComment: json['ack_comment'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'partner_id': partnerId,
      'company_id': companyId,
      'title': title,
      'pdf_storage_path': pdfStoragePath,
      'share_date': shareDate.toIso8601String().split('T').first,
      'is_daily_share': isDailyShare,
      'notes': notes,
      'ack_status': ackStatus,
      'ack_at': ackAt?.toIso8601String(),
      'ack_by': ackBy,
      'ack_comment': ackComment,
    };
  }
}

class PartnerVehicle {
  final String id;
  final String partnerId;
  final String companyId;
  final String unitCode; // e.g. M01, M02
  final String registrationNumber;
  final String? notes;
  final DateTime createdAt;

  PartnerVehicle({
    required this.id,
    required this.partnerId,
    required this.companyId,
    required this.unitCode,
    required this.registrationNumber,
    this.notes,
    required this.createdAt,
  });

  factory PartnerVehicle.fromJson(Map<String, dynamic> json) {
    return PartnerVehicle(
      id: json['id'] as String,
      partnerId: json['partner_id'] as String,
      companyId: json['company_id'] as String,
      unitCode: json['unit_code'] as String,
      registrationNumber: json['registration_number'] as String,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'partner_id': partnerId,
      'company_id': companyId,
      'unit_code': unitCode,
      'registration_number': registrationNumber,
      'notes': notes,
    };
  }
}

class PartnerPortalAccount {
  final String id;
  final String partnerId;
  final String companyId;
  final String username;
  final String loginEmail;
  final String? profileId;
  final bool isActive;
  final DateTime createdAt;

  PartnerPortalAccount({
    required this.id,
    required this.partnerId,
    required this.companyId,
    required this.username,
    required this.loginEmail,
    this.profileId,
    this.isActive = true,
    required this.createdAt,
  });

  factory PartnerPortalAccount.fromJson(Map<String, dynamic> json) {
    return PartnerPortalAccount(
      id: json['id'] as String,
      partnerId: json['partner_id'] as String,
      companyId: json['company_id'] as String,
      username: json['username'] as String,
      loginEmail: json['login_email'] as String,
      profileId: json['profile_id'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
