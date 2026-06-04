class NotificationAuditEntry {
  final String id;
  final DateTime createdAt;
  final String eventChannel;
  final String? category;
  final String? settingKey;
  final String recipient;
  final String status;
  final String? skipReason;
  final String? description;
  final String? partnerName;
  final String deliveryStatus;
  final bool isDismissed;
  final String? messagePreview;

  const NotificationAuditEntry({
    required this.id,
    required this.createdAt,
    required this.eventChannel,
    this.category,
    this.settingKey,
    required this.recipient,
    required this.status,
    this.skipReason,
    this.description,
    this.partnerName,
    this.deliveryStatus = 'queued',
    this.isDismissed = false,
    this.messagePreview,
  });

  factory NotificationAuditEntry.fromJson(Map<String, dynamic> json) {
    return NotificationAuditEntry(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      eventChannel: json['event_channel'] as String,
      category: json['category'] as String?,
      settingKey: json['setting_key'] as String?,
      recipient: json['recipient'] as String? ?? '',
      status: json['status'] as String? ?? 'skipped',
      skipReason: json['skip_reason'] as String?,
      description: json['description'] as String?,
      partnerName: json['partner_name'] as String?,
      deliveryStatus: json['delivery_status'] as String? ?? json['status'] as String? ?? 'queued',
      isDismissed: json['is_dismissed'] as bool? ?? false,
      messagePreview: json['message_preview'] as String?,
    );
  }

  String get channelLabel => eventChannel == 'email' ? 'E-post' : 'SMS';

  String get deliveryStatusLabel {
    switch (deliveryStatus) {
      case 'sent':
        return eventChannel == 'email' ? 'E-post sendt' : 'SMS sendt';
      case 'failed':
        return 'Sending feilet';
      case 'skipped':
        return 'Ikke sendt';
      case 'queued':
      default:
        return eventChannel == 'email' ? 'E-post i kø' : 'SMS venter sending';
    }
  }

  String get statusLabel => deliveryStatusLabel;

  String get skipReasonLabel {
    switch (skipReason) {
      case 'company_channel_off':
        return 'Slått av i firmainnstillinger';
      case 'user_sms_opt_out':
        return 'Bruker har slått av SMS';
      case 'user_email_opt_out':
        return 'Bruker har slått av e-post';
      case 'user_pref_no_sms':
        return 'Bruker vil kun e-post';
      case 'user_pref_no_email':
        return 'Bruker vil kun SMS';
      case 'missing_email':
        return 'Mangler e-postadresse';
      default:
        return skipReason ?? '—';
    }
  }
}
