class RouteReminderFlag {
  final String shareId;
  final DateTime? lastReminderSmsAt;
  final DateTime? lastReminderEmailAt;
  final int reminderSmsCount;
  final int reminderEmailCount;

  const RouteReminderFlag({
    required this.shareId,
    this.lastReminderSmsAt,
    this.lastReminderEmailAt,
    this.reminderSmsCount = 0,
    this.reminderEmailCount = 0,
  });

  factory RouteReminderFlag.fromJson(Map<String, dynamic> json) {
    DateTime? ts(dynamic v) {
      if (v == null) return null;
      return DateTime.parse(v as String);
    }

    return RouteReminderFlag(
      shareId: json['share_id'] as String,
      lastReminderSmsAt: ts(json['last_reminder_sms_at']),
      lastReminderEmailAt: ts(json['last_reminder_email_at']),
      reminderSmsCount: json['reminder_sms_count'] as int? ?? 0,
      reminderEmailCount: json['reminder_email_count'] as int? ?? 0,
    );
  }

  bool get hasSmsReminder =>
      lastReminderSmsAt != null || reminderSmsCount > 0;

  bool get hasEmailReminder =>
      lastReminderEmailAt != null || reminderEmailCount > 0;

  bool get hasAnyReminder => hasSmsReminder || hasEmailReminder;

  String get badgeLabel {
    if (hasSmsReminder && hasEmailReminder) return 'Purring SMS+e-post';
    if (hasSmsReminder) return 'Purring SMS';
    if (hasEmailReminder) return 'Purring e-post';
    return '';
  }

  DateTime? get lastReminderAt {
    final a = lastReminderSmsAt;
    final b = lastReminderEmailAt;
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  String get tooltipDetail {
    final parts = <String>[];
    if (hasSmsReminder) {
      parts.add(
        'SMS${reminderSmsCount > 1 ? ' ($reminderSmsCount×)' : ''}'
        '${lastReminderSmsAt != null ? ' ${ _fmt(lastReminderSmsAt!)}' : ''}',
      );
    }
    if (hasEmailReminder) {
      parts.add(
        'E-post${reminderEmailCount > 1 ? ' ($reminderEmailCount×)' : ''}'
        '${lastReminderEmailAt != null ? ' ${_fmt(lastReminderEmailAt!)}' : ''}',
      );
    }
    return parts.join(' · ');
  }

  static String _fmt(DateTime t) {
    final l = t.toLocal();
    return '${l.day}.${l.month}. kl. ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}
