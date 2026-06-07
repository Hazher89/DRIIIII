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

  const NotificationEventDefinition({
    required this.id,
    required this.scope,
    required this.settingKey,
    required this.title,
    this.subtitle,
    required this.categoryGroup,
    required this.sortOrder,
    required this.channel,
  });

  factory NotificationEventDefinition.fromJson(Map<String, dynamic> json) {
    return NotificationEventDefinition(
      id: json['id'] as String,
      scope: json['scope'] as String,
      settingKey: json['setting_key'] as String,
      title: json['title'] as String,
      subtitle: json['subtitle'] as String?,
      categoryGroup: json['category_group'] as String,
      sortOrder: json['sort_order'] as int? ?? 0,
      channel: NotificationChannel.fromDb(json['channel'] as String?),
    );
  }

  NotificationEventDefinition copyWith({NotificationChannel? channel}) {
    return NotificationEventDefinition(
      id: id,
      scope: scope,
      settingKey: settingKey,
      title: title,
      subtitle: subtitle,
      categoryGroup: categoryGroup,
      sortOrder: sortOrder,
      channel: channel ?? this.channel,
    );
  }

  bool get isMavi => scope == 'mavi';
  bool get isPartner => scope == 'partner';
}
