import 'notification_channel.dart';

/// Én rad i matrisen ansatt × varseltype.
class NotificationRecipientRow {
  final String profileId;
  final String profileName;
  final String profileEmail;
  final String profileRole;
  final String? departmentName;
  final String eventId;
  final String settingKey;
  final String eventTitle;
  final String categoryGroup;
  final bool subscribed;
  final bool isExplicit;
  final String defaultRecipientRule;
  final NotificationChannel channel;

  const NotificationRecipientRow({
    required this.profileId,
    required this.profileName,
    required this.profileEmail,
    required this.profileRole,
    this.departmentName,
    required this.eventId,
    required this.settingKey,
    required this.eventTitle,
    required this.categoryGroup,
    required this.subscribed,
    required this.isExplicit,
    required this.defaultRecipientRule,
    required this.channel,
  });

  factory NotificationRecipientRow.fromJson(Map<String, dynamic> json) {
    return NotificationRecipientRow(
      profileId: json['profile_id'] as String,
      profileName: json['profile_name'] as String? ?? '',
      profileEmail: json['profile_email'] as String? ?? '',
      profileRole: json['profile_role'] as String? ?? 'ansatt',
      departmentName: json['department_name'] as String?,
      eventId: json['event_id'] as String,
      settingKey: json['setting_key'] as String,
      eventTitle: json['event_title'] as String,
      categoryGroup: json['category_group'] as String,
      subscribed: json['subscribed'] as bool? ?? false,
      isExplicit: json['is_explicit'] as bool? ?? false,
      defaultRecipientRule: json['default_recipient_rule'] as String? ?? 'leaders',
      channel: NotificationChannel.fromDb(json['channel'] as String?),
    );
  }

  NotificationRecipientRow copyWith({
    bool? subscribed,
    bool? isExplicit,
    NotificationChannel? channel,
  }) {
    return NotificationRecipientRow(
      profileId: profileId,
      profileName: profileName,
      profileEmail: profileEmail,
      profileRole: profileRole,
      departmentName: departmentName,
      eventId: eventId,
      settingKey: settingKey,
      eventTitle: eventTitle,
      categoryGroup: categoryGroup,
      subscribed: subscribed ?? this.subscribed,
      isExplicit: isExplicit ?? this.isExplicit,
      defaultRecipientRule: defaultRecipientRule,
      channel: channel ?? this.channel,
    );
  }
}
