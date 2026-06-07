enum HmsDomain { hms, kvalitet, logistikk }

extension HmsDomainDb on HmsDomain {
  String get dbValue => name;

  static HmsDomain fromDb(String? value) {
    switch (value) {
      case 'kvalitet':
        return HmsDomain.kvalitet;
      case 'logistikk':
        return HmsDomain.logistikk;
      default:
        return HmsDomain.hms;
    }
  }

  String get label {
    switch (this) {
      case HmsDomain.hms:
        return 'HMS';
      case HmsDomain.kvalitet:
        return 'Kvalitet';
      case HmsDomain.logistikk:
        return 'Logistikk';
    }
  }
}

class HmsTicketTemplate {
  final String id;
  final String? companyId;
  final String templateKey;
  final String title;
  final String descriptionTemplate;
  final String? category;
  final String severityDb;
  final HmsDomain domain;
  final int sortOrder;

  const HmsTicketTemplate({
    required this.id,
    this.companyId,
    required this.templateKey,
    required this.title,
    this.descriptionTemplate = '',
    this.category,
    this.severityDb = 'middels',
    this.domain = HmsDomain.hms,
    this.sortOrder = 0,
  });

  factory HmsTicketTemplate.fromJson(Map<String, dynamic> json) {
    return HmsTicketTemplate(
      id: json['id'] as String,
      companyId: json['company_id'] as String?,
      templateKey: json['template_key'] as String,
      title: json['title'] as String,
      descriptionTemplate: json['description_template'] as String? ?? '',
      category: json['category'] as String?,
      severityDb: json['severity'] as String? ?? 'middels',
      domain: HmsDomainDb.fromDb(json['hms_domain'] as String?),
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }
}

class HmsTicketLeaderAction {
  final String id;
  final String ticketId;
  final String actorId;
  final String actionType;
  final String body;
  final DateTime? createdAt;
  final String? actorName;

  const HmsTicketLeaderAction({
    required this.id,
    required this.ticketId,
    required this.actorId,
    required this.actionType,
    required this.body,
    this.createdAt,
    this.actorName,
  });

  factory HmsTicketLeaderAction.fromJson(Map<String, dynamic> json) {
    return HmsTicketLeaderAction(
      id: json['id'] as String,
      ticketId: json['ticket_id'] as String,
      actorId: json['actor_id'] as String,
      actionType: json['action_type'] as String,
      body: json['body'] as String,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      actorName: json['profiles'] != null
          ? json['profiles']['full_name'] as String?
          : null,
    );
  }
}

class HmsTicketSensitive {
  final String ticketId;
  final String? involvedPersonName;
  final String? injuryDescription;
  final String? medicalNotes;

  const HmsTicketSensitive({
    required this.ticketId,
    this.involvedPersonName,
    this.injuryDescription,
    this.medicalNotes,
  });

  factory HmsTicketSensitive.fromJson(Map<String, dynamic> json) {
    return HmsTicketSensitive(
      ticketId: json['ticket_id'] as String,
      involvedPersonName: json['involved_person_name'] as String?,
      injuryDescription: json['injury_description'] as String?,
      medicalNotes: json['medical_notes'] as String?,
    );
  }

  Map<String, dynamic> toUpsertJson({
    required String companyId,
    required String createdBy,
  }) =>
      {
        'ticket_id': ticketId,
        'company_id': companyId,
        'involved_person_name': involvedPersonName,
        'injury_description': injuryDescription,
        'medical_notes': medicalNotes,
        'created_by': createdBy,
        'updated_at': DateTime.now().toIso8601String(),
      };
}

class HmsRosAvvikSignal {
  final String id;
  final String ticketCategory;
  final int ticketCount;
  final String status;
  final DateTime? createdAt;

  const HmsRosAvvikSignal({
    required this.id,
    required this.ticketCategory,
    required this.ticketCount,
    this.status = 'active',
    this.createdAt,
  });

  factory HmsRosAvvikSignal.fromJson(Map<String, dynamic> json) {
    return HmsRosAvvikSignal(
      id: json['id'] as String,
      ticketCategory: json['ticket_category'] as String,
      ticketCount: json['ticket_count'] as int? ?? 0,
      status: json['status'] as String? ?? 'active',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }
}
