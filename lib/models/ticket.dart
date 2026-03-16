enum TicketSeverity {
  lav,
  middels,
  hoy,
  kritisk;

  String get label {
    switch (this) {
      case TicketSeverity.lav: return 'Lav';
      case TicketSeverity.middels: return 'Middels';
      case TicketSeverity.hoy: return 'Høy';
      case TicketSeverity.kritisk: return 'Kritisk';
    }
  }

  String get dbValue => name;

  static TicketSeverity fromDb(String value) {
    switch (value) {
      case 'lav': return TicketSeverity.lav;
      case 'middels': return TicketSeverity.middels;
      case 'hoy': return TicketSeverity.hoy;
      case 'kritisk': return TicketSeverity.kritisk;
      default: return TicketSeverity.middels;
    }
  }
}

enum TicketStatus {
  aapen,
  underBehandling,
  tiltakUtfort,
  lukket;

  String get label {
    switch (this) {
      case TicketStatus.aapen: return 'Åpen';
      case TicketStatus.underBehandling: return 'Under behandling';
      case TicketStatus.tiltakUtfort: return 'Tiltak utført';
      case TicketStatus.lukket: return 'Lukket';
    }
  }

  String get dbValue {
    switch (this) {
      case TicketStatus.aapen: return 'aapen';
      case TicketStatus.underBehandling: return 'under_behandling';
      case TicketStatus.tiltakUtfort: return 'tiltak_utfort';
      case TicketStatus.lukket: return 'lukket';
    }
  }

  static TicketStatus fromDb(String value) {
    switch (value) {
      case 'aapen': return TicketStatus.aapen;
      case 'under_behandling': return TicketStatus.underBehandling;
      case 'tiltak_utfort': return TicketStatus.tiltakUtfort;
      case 'lukket': return TicketStatus.lukket;
      default: return TicketStatus.aapen;
    }
  }
}

class Ticket {
  final String id;
  final String companyId;
  final String? departmentId;
  final String reportedBy;
  final String? assignedTo;
  final int? ticketNumber;
  final String title;
  final String description;
  final String? category;
  final TicketSeverity severity;
  final TicketStatus status;
  final List<String> imageUrls;
  final List<String> annotatedImageUrls;
  final double? gpsLatitude;
  final double? gpsLongitude;
  final String? gpsAddress;
  final String? locationDescription;
  final DateTime? dueDate;
  final DateTime? resolvedAt;
  final String? resolvedBy;
  final String? resolutionComment;
  final bool isAnonymous;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Joined fields
  final String? reporterName;
  final String? reporterAvatarUrl;
  final String? assigneeName;
  final String? departmentName;

  const Ticket({
    required this.id,
    required this.companyId,
    this.departmentId,
    required this.reportedBy,
    this.assignedTo,
    this.ticketNumber,
    required this.title,
    required this.description,
    this.category,
    this.severity = TicketSeverity.middels,
    this.status = TicketStatus.aapen,
    this.imageUrls = const [],
    this.annotatedImageUrls = const [],
    this.gpsLatitude,
    this.gpsLongitude,
    this.gpsAddress,
    this.locationDescription,
    this.dueDate,
    this.resolvedAt,
    this.resolvedBy,
    this.resolutionComment,
    this.isAnonymous = false,
    this.createdAt,
    this.updatedAt,
    this.reporterName,
    this.reporterAvatarUrl,
    this.assigneeName,
    this.departmentName,
  });

  factory Ticket.fromJson(Map<String, dynamic> json) {
    return Ticket(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      departmentId: json['department_id'] as String?,
      reportedBy: json['reported_by'] as String,
      assignedTo: json['assigned_to'] as String?,
      ticketNumber: json['ticket_number'] as int?,
      title: json['title'] as String,
      description: json['description'] as String,
      category: json['category'] as String?,
      severity: TicketSeverity.fromDb(json['severity'] as String? ?? 'middels'),
      status: TicketStatus.fromDb(json['status'] as String? ?? 'aapen'),
      imageUrls: (json['image_urls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      annotatedImageUrls: (json['annotated_image_urls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      gpsLatitude: (json['gps_latitude'] as num?)?.toDouble(),
      gpsLongitude: (json['gps_longitude'] as num?)?.toDouble(),
      gpsAddress: json['gps_address'] as String?,
      locationDescription: json['location_description'] as String?,
      dueDate: json['due_date'] != null
          ? DateTime.parse(json['due_date'] as String)
          : null,
      resolvedAt: json['resolved_at'] != null
          ? DateTime.parse(json['resolved_at'] as String)
          : null,
      resolvedBy: json['resolved_by'] as String?,
      resolutionComment: json['resolution_comment'] as String?,
      isAnonymous: json['is_anonymous'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      reporterName: json['reporter'] != null
          ? json['reporter']['full_name'] as String?
          : null,
      reporterAvatarUrl: json['reporter'] != null
          ? json['reporter']['avatar_url'] as String?
          : null,
    );
  }

  Map<String, dynamic> toInsertJson() => {
    'company_id': companyId,
    'department_id': departmentId,
    'reported_by': reportedBy,
    'title': title,
    'description': description,
    'category': category,
    'severity': severity.dbValue,
    'image_urls': imageUrls,
    'gps_latitude': gpsLatitude,
    'gps_longitude': gpsLongitude,
    'gps_address': gpsAddress,
    'location_description': locationDescription,
    'is_anonymous': isAnonymous,
    'assigned_to': assignedTo,
    'status': status.dbValue,
  };

  bool get isOpen => status == TicketStatus.aapen || status == TicketStatus.underBehandling;
}

class TicketComment {
  final String id;
  final String ticketId;
  final String userId;
  final String comment;
  final List<String> imageUrls;
  final TicketStatus? oldStatus;
  final TicketStatus? newStatus;
  final bool isStatusChange;
  final DateTime? createdAt;

  // Joined
  final String? userName;
  final String? userAvatarUrl;

  const TicketComment({
    required this.id,
    required this.ticketId,
    required this.userId,
    required this.comment,
    this.imageUrls = const [],
    this.oldStatus,
    this.newStatus,
    this.isStatusChange = false,
    this.createdAt,
    this.userName,
    this.userAvatarUrl,
  });

  factory TicketComment.fromJson(Map<String, dynamic> json) {
    return TicketComment(
      id: json['id'] as String,
      ticketId: json['ticket_id'] as String,
      userId: json['user_id'] as String,
      comment: json['comment'] as String,
      imageUrls: (json['image_urls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      oldStatus: json['old_status'] != null
          ? TicketStatus.fromDb(json['old_status'] as String)
          : null,
      newStatus: json['new_status'] != null
          ? TicketStatus.fromDb(json['new_status'] as String)
          : null,
      isStatusChange: json['is_status_change'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      userName: json['profiles'] != null
          ? json['profiles']['full_name'] as String?
          : null,
      userAvatarUrl: json['profiles'] != null
          ? json['profiles']['avatar_url'] as String?
          : null,
    );
  }
}
