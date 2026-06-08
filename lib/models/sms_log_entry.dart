class SmsLogEntry {
  final String id;
  final DateTime createdAt;
  final DateTime? sentAt;
  final String toPhone;
  final String message;
  final String? category;
  final String? referenceType;
  final String? referenceId;
  final String? errorMessage;
  final int attempts;
  final int? sveveMessageId;
  final String recipientName;
  final String? recipientUserId;
  final String triggeredByName;
  final String? triggeredByUserId;
  final String deliveryStatus;
  final String senderName;

  const SmsLogEntry({
    required this.id,
    required this.createdAt,
    this.sentAt,
    required this.toPhone,
    required this.message,
    this.category,
    this.referenceType,
    this.referenceId,
    this.errorMessage,
    this.attempts = 0,
    this.sveveMessageId,
    required this.recipientName,
    this.recipientUserId,
    required this.triggeredByName,
    this.triggeredByUserId,
    required this.deliveryStatus,
    this.senderName = 'MAVI',
  });

  factory SmsLogEntry.fromJson(Map<String, dynamic> json) {
    return SmsLogEntry(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      sentAt: json['sent_at'] != null
          ? DateTime.parse(json['sent_at'] as String)
          : null,
      toPhone: json['to_phone'] as String,
      message: json['message'] as String,
      category: json['category'] as String?,
      referenceType: json['reference_type'] as String?,
      referenceId: json['reference_id'] as String?,
      errorMessage: json['error_message'] as String?,
      attempts: json['attempts'] as int? ?? 0,
      sveveMessageId: json['sveve_message_id'] as int?,
      recipientName: json['recipient_name'] as String? ?? json['to_phone'] as String,
      recipientUserId: json['recipient_user_id'] as String?,
      triggeredByName:
          json['triggered_by_name'] as String? ?? 'System (automatisk / Mavi)',
      triggeredByUserId: json['triggered_by_user_id'] as String?,
      deliveryStatus: json['delivery_status'] as String? ?? 'i_ko',
      senderName: json['sender_name'] as String? ?? 'MAVI',
    );
  }

  String get categoryLabel => SmsLogEntry.labelForCategory(category);

  static String labelForCategory(String? cat) {
    switch (cat) {
      case 'absence_request':
        return 'Fravær – ny søknad';
      case 'absence_decision':
        return 'Fravær – vedtak';
      case 'ticket':
        return 'Avvik – nytt';
      case 'ticket_status':
        return 'Avvik – status';
      case 'ticket_critical':
        return 'Avvik – kritisk';
      case 'equipment_reminder':
        return 'Utstyr / truck';
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
