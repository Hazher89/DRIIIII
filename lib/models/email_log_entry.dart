class EmailLogEntry {
  final String id;
  final DateTime createdAt;
  final DateTime? sentAt;
  final String toEmail;
  final String subject;
  final String body;
  final String? description;
  final String? category;
  final String? referenceType;
  final String? referenceId;
  final String? errorMessage;
  final int attempts;
  final String recipientName;
  final String? recipientUserId;
  final String triggeredByName;
  final String? triggeredByUserId;
  final String deliveryStatus;
  final String senderName;
  final String? partnerName;
  final String? contextLabel;

  const EmailLogEntry({
    required this.id,
    required this.createdAt,
    this.sentAt,
    required this.toEmail,
    required this.subject,
    required this.body,
    this.description,
    this.category,
    this.referenceType,
    this.referenceId,
    this.errorMessage,
    this.attempts = 0,
    required this.recipientName,
    this.recipientUserId,
    required this.triggeredByName,
    this.triggeredByUserId,
    required this.deliveryStatus,
    this.senderName = 'ikkesvar@driftpro.no',
    this.partnerName,
    this.contextLabel,
  });

  factory EmailLogEntry.fromJson(Map<String, dynamic> json) {
    return EmailLogEntry(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      sentAt: json['sent_at'] != null
          ? DateTime.parse(json['sent_at'] as String)
          : null,
      toEmail: json['to_email'] as String,
      subject: json['subject'] as String? ?? '',
      body: json['body'] as String? ?? '',
      description: json['description'] as String?,
      category: json['category'] as String?,
      referenceType: json['reference_type'] as String?,
      referenceId: json['reference_id'] as String?,
      errorMessage: json['error_message'] as String?,
      attempts: json['attempts'] as int? ?? 0,
      recipientName: json['recipient_name'] as String? ?? json['to_email'] as String,
      recipientUserId: json['recipient_user_id'] as String?,
      triggeredByName:
          json['triggered_by_name'] as String? ?? 'System (automatisk)',
      triggeredByUserId: json['triggered_by_user_id'] as String?,
      deliveryStatus: json['delivery_status'] as String? ?? 'i_ko',
      senderName: json['sender_name'] as String? ?? 'ikkesvar@driftpro.no',
      partnerName: json['partner_name'] as String?,
      contextLabel: json['context_label'] as String?,
    );
  }

  String get displayTitle =>
      description?.trim().isNotEmpty == true ? description! : subject;

  String get categoryLabel => labelForCategory(category);

  static String labelForCategory(String? cat) {
    switch (cat) {
      case 'absence':
        return 'Fravær';
      case 'ticket':
        return 'Avvik';
      case 'partner_route_share':
        return 'Rute sendt';
      case 'partner_route_ack':
        return 'Rute kvittering';
      case 'equipment_reminder':
        return 'Utstyr';
      default:
        return cat ?? 'Annet';
    }
  }

  String get statusLabel {
    switch (deliveryStatus) {
      case 'sendt':
        return 'Sendt';
      case 'feilet':
        return 'Feilet';
      case 'feil':
        return 'Feil (retry)';
      default:
        return 'I kø';
    }
  }
}
