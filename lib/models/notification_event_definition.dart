import 'notification_channel.dart';

/// Varseltype fra Supabase-katalogen `notification_event_definitions`.
class NotificationEventDefinition {
  final String id;
  final String scope;
  final String settingKey;
  final String title;
  final String? subtitle;
  final String categoryGroup;
  final int sortOrder;
  final NotificationChannel channel;
  final bool smsEnabled;
  final bool emailEnabled;
  final bool pushEnabled;

  const NotificationEventDefinition({
    required this.id,
    required this.scope,
    required this.settingKey,
    required this.title,
    this.subtitle,
    required this.categoryGroup,
    required this.sortOrder,
    required this.channel,
    required this.smsEnabled,
    required this.emailEnabled,
    required this.pushEnabled,
  });

  factory NotificationEventDefinition.fromJson(Map<String, dynamic> json) {
    final sms = json['sms_enabled'] as bool? ?? true;
    final email = json['email_enabled'] as bool? ?? true;
    final push = json['push_enabled'] as bool? ?? true;

    return NotificationEventDefinition(
      id: json['id'] as String,
      scope: json['scope'] as String,
      settingKey: json['setting_key'] as String,
      title: json['title'] as String,
      subtitle: json['subtitle'] as String?,
      categoryGroup: json['category_group'] as String,
      sortOrder: json['sort_order'] as int? ?? 0,
      channel: NotificationChannel.fromDb(json['channel'] as String?),
      smsEnabled: sms,
      emailEnabled: email,
      pushEnabled: push,
    );
  }

  NotificationEventDefinition copyWith({
    NotificationChannel? channel,
    bool? smsEnabled,
    bool? emailEnabled,
    bool? pushEnabled,
  }) {
    final sms = smsEnabled ?? this.smsEnabled;
    final email = emailEnabled ?? this.emailEnabled;
    return NotificationEventDefinition(
      id: id,
      scope: scope,
      settingKey: settingKey,
      title: title,
      subtitle: subtitle,
      categoryGroup: categoryGroup,
      sortOrder: sortOrder,
      channel: channel ?? NotificationChannel.fromTriChannel(sms, email),
      smsEnabled: sms,
      emailEnabled: email,
      pushEnabled: pushEnabled ?? this.pushEnabled,
    );
  }

  bool get isMavi => scope == 'mavi';
  bool get isPartner => scope == 'partner';

  bool get allOff => !smsEnabled && !emailEnabled && !pushEnabled;

  String get channelSummary {
    final parts = <String>[];
    if (smsEnabled) parts.add('SMS');
    if (emailEnabled) parts.add('E-post');
    if (pushEnabled) parts.add('Push');
    return parts.isEmpty ? 'Av' : parts.join(' · ');
  }
}
