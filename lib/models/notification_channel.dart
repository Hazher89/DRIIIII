/// sms | email | both | none — firmavalg per varseltype.
enum NotificationChannel {
  sms,
  email,
  both,
  none;

  static NotificationChannel fromDb(String? v) {
    switch (v?.toLowerCase()) {
      case 'sms':
        return NotificationChannel.sms;
      case 'email':
        return NotificationChannel.email;
      case 'none':
        return NotificationChannel.none;
      case 'both':
      default:
        return NotificationChannel.both;
    }
  }

  static NotificationChannel fromTriChannel(bool sms, bool email) {
    if (sms && email) return NotificationChannel.both;
    if (sms) return NotificationChannel.sms;
    if (email) return NotificationChannel.email;
    return NotificationChannel.none;
  }

  String get dbValue => name;

  String get label {
    switch (this) {
      case NotificationChannel.sms:
        return 'Kun SMS';
      case NotificationChannel.email:
        return 'Kun e-post';
      case NotificationChannel.both:
        return 'SMS + e-post';
      case NotificationChannel.none:
        return 'Av';
    }
  }

  String get shortLabel {
    switch (this) {
      case NotificationChannel.sms:
        return 'SMS';
      case NotificationChannel.email:
        return 'E-post';
      case NotificationChannel.both:
        return 'Begge';
      case NotificationChannel.none:
        return 'Av';
    }
  }
}
