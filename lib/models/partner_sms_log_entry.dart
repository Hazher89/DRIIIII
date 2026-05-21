class PartnerSmsLogEntry {
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
  final String? partnerName;
  final String? contextLabel;

  const PartnerSmsLogEntry({
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
    this.senderName = 'Mavi',
    this.partnerName,
    this.contextLabel,
  });

  factory PartnerSmsLogEntry.fromJson(Map<String, dynamic> json) {
    return PartnerSmsLogEntry(
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
          json['triggered_by_name'] as String? ?? 'System (automatisk)',
      triggeredByUserId: json['triggered_by_user_id'] as String?,
      deliveryStatus: json['delivery_status'] as String? ?? 'i_ko',
      senderName: json['sender_name'] as String? ?? 'Mavi',
      partnerName: json['partner_name'] as String?,
      contextLabel: json['context_label'] as String?,
    );
  }

  String get categoryLabel => labelForCategory(category);

  static String labelForCategory(String? cat) {
    switch (cat) {
      case 'partner_route':
        return 'Rute — sjåfør';
      case 'partner_route_owner':
        return 'Rute — bil-eier';
      case 'partner_compose':
        return 'Manuell SMS';
      case 'partner_meeting':
        return 'Møte / oppfølging';
      case 'partner_portal':
        return 'Portal-innlogging';
      default:
        if (cat != null && cat.startsWith('partner')) return cat;
        return 'Samarbeid';
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
