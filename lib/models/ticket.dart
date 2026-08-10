import '../core/case_trace/case_trace.dart';
import 'hms/hms_ticket_template.dart';

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
  final String? traceRef;
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
  final String? rootCause;
  final List<Map<String, dynamic>> actionPlan;
  /// Kun synlig for koordinatorer i detaljvisning (lagres i DB).
  final String? internalNotes;
  final HmsDomain hmsDomain;
  final List<String> videoUrls;
  final DateTime? observedAt;
  final bool hasPersonalInjury;
  final String? completedMeasures;
  final String? escalationReason;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;
  final String? deletionComment;

  // Joined fields
  final String? reporterName;
  final String? reporterAvatarUrl;
  final String? assigneeName;
  final String? resolvedByName;
  final String? departmentName;

  const Ticket({
    required this.id,
    required this.companyId,
    this.departmentId,
    required this.reportedBy,
    this.assignedTo,
    this.ticketNumber,
    this.traceRef,
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
    this.rootCause,
    this.actionPlan = const [],
    this.internalNotes,
    this.hmsDomain = HmsDomain.hms,
    this.videoUrls = const [],
    this.observedAt,
    this.hasPersonalInjury = false,
    this.completedMeasures,
    this.escalationReason,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
    this.deletionComment,
    this.reporterName,
    this.reporterAvatarUrl,
    this.assigneeName,
    this.resolvedByName,
    this.departmentName,
  });

  bool get isDeleted => deletedAt != null;
  String get traceCode => CaseTrace.codeFromId(id);
  String get displayTraceRef =>
      traceRef ?? (ticketNumber != null ? 'Avvik #$ticketNumber' : 'Avvik');

  factory Ticket.fromJson(Map<String, dynamic> json) {
    return Ticket(
      id: _asString(json['id']) ?? '',
      companyId: _asString(json['company_id']) ?? '',
      departmentId: _asString(json['department_id']),
      reportedBy: _asString(json['reported_by']) ?? '',
      assignedTo: _asString(json['assigned_to']),
      ticketNumber: _asInt(json['ticket_number']),
      traceRef: _asString(json['trace_ref']),
      title: _asString(json['title']) ?? 'Uten tittel',
      description: _asString(json['description']) ?? '',
      category: _asString(json['category']),
      severity: TicketSeverity.fromDb(_asString(json['severity']) ?? 'middels'),
      status: TicketStatus.fromDb(_asString(json['status']) ?? 'aapen'),
      imageUrls: _asStringList(json['image_urls']),
      annotatedImageUrls: _asStringList(json['annotated_image_urls']),
      gpsLatitude: _asDouble(json['gps_latitude']),
      gpsLongitude: _asDouble(json['gps_longitude']),
      gpsAddress: _asString(json['gps_address']),
      locationDescription: _asString(json['location_description']),
      dueDate: _asDateTime(json['due_date']),
      resolvedAt: _asDateTime(json['resolved_at']),
      resolvedBy: _asString(json['resolved_by']),
      resolutionComment: _asString(json['resolution_comment']),
      isAnonymous: _asBool(json['is_anonymous']),
      rootCause: _asString(json['root_cause']),
      actionPlan: _asMapList(json['action_plan']),
      internalNotes: _asString(json['internal_notes']),
      hmsDomain: HmsDomainDb.fromDb(_asString(json['hms_domain'])),
      videoUrls: _asStringList(json['video_urls']),
      observedAt: _asDateTime(json['observed_at']),
      hasPersonalInjury: _asBool(json['has_personal_injury']),
      completedMeasures: _asString(json['completed_measures']),
      escalationReason: _asString(json['escalation_reason']),
      createdAt: _asDateTime(json['created_at']),
      updatedAt: _asDateTime(json['updated_at']),
      deletedAt: _asDateTime(json['deleted_at']),
      deletionComment: _asString(json['deletion_comment']),
      reporterName: _embedField(json['reporter'], 'full_name'),
      reporterAvatarUrl: _embedField(json['reporter'], 'avatar_url'),
      assigneeName: _embedField(json['assignee'], 'full_name'),
      resolvedByName: _embedField(json['resolver'], 'full_name'),
      departmentName: _embedField(json['department'], 'name'),
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
    'root_cause': rootCause,
    'action_plan': actionPlan,
    'internal_notes': internalNotes,
    'hms_domain': hmsDomain.dbValue,
    'video_urls': videoUrls,
    if (observedAt != null) 'observed_at': observedAt!.toIso8601String(),
    'has_personal_injury': hasPersonalInjury,
    if (completedMeasures != null) 'completed_measures': completedMeasures,
  };

  bool get isOpen => status == TicketStatus.aapen || status == TicketStatus.underBehandling;

  Ticket copyWith({
    String? id,
    String? companyId,
    String? departmentId,
    String? reportedBy,
    String? assignedTo,
    int? ticketNumber,
    String? title,
    String? description,
    String? category,
    TicketSeverity? severity,
    TicketStatus? status,
    List<String>? imageUrls,
    List<String>? annotatedImageUrls,
    double? gpsLatitude,
    double? gpsLongitude,
    String? gpsAddress,
    String? locationDescription,
    DateTime? dueDate,
    DateTime? resolvedAt,
    String? resolvedBy,
    String? resolutionComment,
    bool? isAnonymous,
    String? rootCause,
    List<Map<String, dynamic>>? actionPlan,
    String? internalNotes,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? reporterName,
    String? reporterAvatarUrl,
    String? assigneeName,
    String? resolvedByName,
    String? departmentName,
  }) {
    return Ticket(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      departmentId: departmentId ?? this.departmentId,
      reportedBy: reportedBy ?? this.reportedBy,
      assignedTo: assignedTo ?? this.assignedTo,
      ticketNumber: ticketNumber ?? this.ticketNumber,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      severity: severity ?? this.severity,
      status: status ?? this.status,
      imageUrls: imageUrls ?? this.imageUrls,
      annotatedImageUrls: annotatedImageUrls ?? this.annotatedImageUrls,
      gpsLatitude: gpsLatitude ?? this.gpsLatitude,
      gpsLongitude: gpsLongitude ?? this.gpsLongitude,
      gpsAddress: gpsAddress ?? this.gpsAddress,
      locationDescription: locationDescription ?? this.locationDescription,
      dueDate: dueDate ?? this.dueDate,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      resolvedBy: resolvedBy ?? this.resolvedBy,
      resolutionComment: resolutionComment ?? this.resolutionComment,
      isAnonymous: isAnonymous ?? this.isAnonymous,
      rootCause: rootCause ?? this.rootCause,
      actionPlan: actionPlan ?? this.actionPlan,
      internalNotes: internalNotes ?? this.internalNotes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      reporterName: reporterName ?? this.reporterName,
      reporterAvatarUrl: reporterAvatarUrl ?? this.reporterAvatarUrl,
      assigneeName: assigneeName ?? this.assigneeName,
      resolvedByName: resolvedByName ?? this.resolvedByName,
      departmentName: departmentName ?? this.departmentName,
    );
  }
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
      id: _asString(json['id']) ?? '',
      ticketId: _asString(json['ticket_id']) ?? '',
      userId: _asString(json['user_id']) ?? '',
      comment: _asString(json['comment']) ?? '',
      imageUrls: _asStringList(json['image_urls']),
      oldStatus: _asString(json['old_status']) != null
          ? TicketStatus.fromDb(_asString(json['old_status'])!)
          : null,
      newStatus: _asString(json['new_status']) != null
          ? TicketStatus.fromDb(_asString(json['new_status'])!)
          : null,
      isStatusChange: json['is_status_change'] as bool? ?? false,
      createdAt: _asDateTime(json['created_at']),
      userName: _embedField(json['profiles'], 'full_name'),
      userAvatarUrl: _embedField(json['profiles'], 'avatar_url'),
    );
  }
}

String? _asString(dynamic v) {
  if (v == null) return null;
  if (v is String) {
    final t = v.trim();
    return t.isEmpty ? null : t;
  }
  return v.toString();
}

bool _asBool(dynamic v, {bool fallback = false}) {
  if (v == null) return fallback;
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = v.toString().trim().toLowerCase();
  if (s == 'true' || s == 't' || s == '1' || s == 'yes') return true;
  if (s == 'false' || s == 'f' || s == '0' || s == 'no') return false;
  return fallback;
}

int? _asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

double? _asDouble(dynamic v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

DateTime? _asDateTime(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  final s = _asString(v);
  if (s == null) return null;
  return DateTime.tryParse(s);
}

List<String> _asStringList(dynamic v) {
  if (v is! List) return const [];
  return v
      .map(_asString)
      .whereType<String>()
      .where((s) => s.isNotEmpty)
      .toList();
}

List<Map<String, dynamic>> _asMapList(dynamic v) {
  if (v is! List) return const [];
  final out = <Map<String, dynamic>>[];
  for (final e in v) {
    if (e is Map<String, dynamic>) {
      out.add(e);
    } else if (e is Map) {
      out.add(Map<String, dynamic>.from(e));
    }
  }
  return out;
}

String? _embedField(dynamic embed, String key) {
  if (embed == null) return null;
  if (embed is Map) {
    return _asString(embed[key]);
  }
  if (embed is List && embed.isNotEmpty) {
    final first = embed.first;
    if (first is Map) return _asString(first[key]);
  }
  return null;
}
