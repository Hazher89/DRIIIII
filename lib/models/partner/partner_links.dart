class PartnerDocument {
  final String id;
  final String partnerId;
  final String companyId;
  final String title;
  final String? storagePath;
  final String? fileName;
  final String? mimeType;
  final String? notes;
  /// general | summary | agreement — summary = oppsummerings-PDF (kun delt med denne partneren)
  final String docCategory;
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
    this.docCategory = 'general',
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
      docCategory: json['doc_category'] as String? ?? 'general',
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
      'doc_category': docCategory,
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
  final String? shiftId;
  final String? partnerVehicleId;
  final DateTime? routeStartAt;
  /// staged = fordelt internt; sent = sendt til sjåfør/partner
  final String dispatchStatus;
  final String? pdfSearchText;
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
    this.shiftId,
    this.partnerVehicleId,
    this.routeStartAt,
    this.dispatchStatus = 'sent',
    this.pdfSearchText,
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
      shiftId: json['shift_id'] as String?,
      partnerVehicleId: json['partner_vehicle_id'] as String?,
      routeStartAt: json['route_start_at'] != null
          ? DateTime.parse(json['route_start_at'] as String)
          : null,
      dispatchStatus: (json['dispatch_status'] as String?) ?? 'sent',
      pdfSearchText: json['pdf_search_text'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  bool get isStaged => dispatchStatus == 'staged';

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
      'dispatch_status': dispatchStatus,
      if (pdfSearchText != null && pdfSearchText!.isNotEmpty) 'pdf_search_text': pdfSearchText,
      if (shiftId != null) 'shift_id': shiftId,
      if (partnerVehicleId != null) 'partner_vehicle_id': partnerVehicleId,
    };
  }
}

class PartnerVehicle {
  final String id;
  final String partnerId;
  final String companyId;
  final String unitCode;
  final String registrationNumber;
  final String? phone;
  final String? notes;
  final int? modelYear;
  final int? payloadKg;
  final DateTime? euLastAt;
  final DateTime? euNextAt;
  final bool? euApproved;
  final List<String> imageUrls;
  final Map<String, dynamic>? vegvesenSnapshot;
  final DateTime createdAt;

  PartnerVehicle({
    required this.id,
    required this.partnerId,
    required this.companyId,
    required this.unitCode,
    required this.registrationNumber,
    this.phone,
    this.notes,
    this.modelYear,
    this.payloadKg,
    this.euLastAt,
    this.euNextAt,
    this.euApproved,
    this.imageUrls = const [],
    this.vegvesenSnapshot,
    required this.createdAt,
  });

  factory PartnerVehicle.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      return DateTime.tryParse(v.toString());
    }

    return PartnerVehicle(
      id: json['id'] as String,
      partnerId: json['partner_id'] as String,
      companyId: json['company_id'] as String,
      unitCode: json['unit_code'] as String,
      registrationNumber: json['registration_number'] as String,
      phone: json['phone'] as String?,
      notes: json['notes'] as String?,
      modelYear: json['model_year'] as int?,
      payloadKg: json['payload_kg'] as int?,
      euLastAt: parseDate(json['eu_last_at']),
      euNextAt: parseDate(json['eu_next_at']),
      euApproved: json['eu_approved'] as bool?,
      imageUrls: (json['image_urls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      vegvesenSnapshot: json['vegvesen_snapshot'] as Map<String, dynamic>?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toUpsertJson() {
    return {
      if (id.isNotEmpty) 'id': id,
      'partner_id': partnerId,
      'company_id': companyId,
      'unit_code': unitCode,
      'registration_number': registrationNumber,
      if (phone != null) 'phone': phone,
      'notes': notes,
      'model_year': modelYear,
      'payload_kg': payloadKg,
      'eu_last_at': euLastAt?.toIso8601String().split('T').first,
      'eu_next_at': euNextAt?.toIso8601String().split('T').first,
      'eu_approved': euApproved,
      'image_urls': imageUrls,
      'vegvesen_snapshot': vegvesenSnapshot,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  bool get euOverdue =>
      euNextAt != null && euNextAt!.isBefore(DateTime.now());

  bool get euDueSoon {
    if (euNextAt == null) return false;
    final limit = DateTime.now().add(const Duration(days: 60));
    return !euNextAt!.isBefore(DateTime.now()) && euNextAt!.isBefore(limit);
  }
}

class PartnerPortalAccount {
  final String id;
  final String partnerId;
  final String companyId;
  final String? partnerVehicleId;
  final String username;
  final String loginEmail;
  final String? phone;
  final String? profileId;
  final bool isActive;
  final DateTime createdAt;

  PartnerPortalAccount({
    required this.id,
    required this.partnerId,
    required this.companyId,
    this.partnerVehicleId,
    required this.username,
    required this.loginEmail,
    this.phone,
    this.profileId,
    this.isActive = true,
    required this.createdAt,
  });

  factory PartnerPortalAccount.fromJson(Map<String, dynamic> json) {
    return PartnerPortalAccount(
      id: json['id'] as String,
      partnerId: json['partner_id'] as String,
      companyId: json['company_id'] as String,
      partnerVehicleId: json['partner_vehicle_id'] as String?,
      username: json['username'] as String,
      loginEmail: json['login_email'] as String,
      phone: json['phone'] as String?,
      profileId: json['profile_id'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class PartnerFriRequest {
  final String id;
  final String companyId;
  final String partnerId;
  final String? partnerVehicleId;
  final DateTime requestDate;
  final String? reason;
  final String status;
  final DateTime? reviewedAt;
  final String? reviewNote;
  final DateTime createdAt;

  const PartnerFriRequest({
    required this.id,
    required this.companyId,
    required this.partnerId,
    this.partnerVehicleId,
    required this.requestDate,
    this.reason,
    this.status = 'pending',
    this.reviewedAt,
    this.reviewNote,
    required this.createdAt,
  });

  factory PartnerFriRequest.fromJson(Map<String, dynamic> json) {
    return PartnerFriRequest(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      partnerId: json['partner_id'] as String,
      partnerVehicleId: json['partner_vehicle_id'] as String?,
      requestDate: DateTime.parse(json['request_date'] as String),
      reason: json['reason'] as String?,
      status: (json['status'] as String?) ?? 'pending',
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.parse(json['reviewed_at'] as String)
          : null,
      reviewNote: json['review_note'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
